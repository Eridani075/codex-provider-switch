#!/usr/bin/env python3
"""codex-unlock: One-click plugin marketplace unlock for Codex desktop.

Starts Codex with --remote-debugging-port, connects via CDP,
and injects the plugin unlock script.

Usage:
  python3 unlock.py                  # Start Codex + inject unlock
  python3 unlock.py --inject-only PORT  # Just inject to running Codex
"""
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
import websocket  # pip install websocket-client, or use stdlib fallback

CODEX_BIN_CANDIDATES = [
    "openai-codex-desktop",
    "codex-desktop",
    "/usr/bin/openai-codex-desktop",
    "/opt/OpenAI/Codex/codex-desktop",
]

DEBUG_PORT = 9222

# The unlock script: bypasses plugin auth + re-enables nav buttons
UNLOCK_SCRIPT = r"""
(function() {
  'use strict';

  // === Auth bypass ===
  // Override the plugin auth check to always return false (unlocked)
  const origFetch = window.fetch;
  window.fetch = function(url, opts) {
    if (typeof url === 'string' && url.includes('/plugins/auth')) {
      return Promise.resolve(new Response(JSON.stringify({ authorized: false }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      }));
    }
    return origFetch.apply(this, arguments);
  };

  // === UI unlock: re-enable disabled plugin nav buttons ===
  function clearDisabled(el) {
    if (!(el instanceof HTMLElement)) return;
    if ('disabled' in el) el.disabled = false;
    el.removeAttribute('disabled');
    el.removeAttribute('aria-disabled');
    el.removeAttribute('data-disabled');
    el.removeAttribute('inert');
    el.classList.remove('disabled', 'opacity-50', 'cursor-not-allowed', 'pointer-events-none');
    el.style.pointerEvents = 'auto';
    el.style.opacity = '';
    el.style.cursor = 'pointer';
    el.tabIndex = 0;
  }

  function findPluginButtons() {
    // Match plugin nav buttons by text content or SVG path
    return Array.from(document.querySelectorAll('button, [role="button"]')).filter(btn => {
      const text = (btn.textContent || '').trim();
      if (/^(Plugins|插件)/.test(text)) return true;
      // Check for plugin icon SVG path
      return !!btn.querySelector?.('path[d*="M12 2L"]');
    });
  }

  function unlockButtons() {
    findPluginButtons().forEach(btn => {
      clearDisabled(btn);
      // Also unlock parent chain
      let parent = btn.parentElement;
      for (let i = 0; parent && i < 3; i++) {
        if (parent.matches?.('button, [role="button"], [disabled], [aria-disabled]')) {
          clearDisabled(parent);
        }
        parent = parent.parentElement;
      }
      // Unlock children
      btn.querySelectorAll('[disabled], [aria-disabled], [data-disabled]').forEach(clearDisabled);
      // Patch React props to restore onClick
      Object.keys(btn).filter(k => k.startsWith('__reactProps')).forEach(key => {
        const props = btn[key];
        if (props) {
          props.disabled = false;
          props['aria-disabled'] = false;
        }
      });
    });
  }

  // Run unlock periodically
  unlockButtons();
  setInterval(unlockButtons, 2000);

  console.log('[Codex++ Unlock] Plugin marketplace unlock injected');
})();
"""


def find_codex_binary():
    for candidate in CODEX_BIN_CANDIDATES:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
        # Try which
        try:
            result = subprocess.run(["which", candidate], capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.strip()
        except FileNotFoundError:
            pass
    return None


def get_ws_url(port):
    """Get WebSocket debugger URL from CDP /json endpoint."""
    try:
        url = f"http://127.0.0.1:{port}/json"
        req = urllib.request.urlopen(url, timeout=5)
        targets = json.loads(req.read())
        for target in targets:
            if target.get("type") == "page":
                return target.get("webSocketDebuggerUrl")
        # Fallback: use first target
        if targets:
            return targets[0].get("webSocketDebuggerUrl")
    except Exception as e:
        print(f"  连接 CDP 失败: {e}", file=sys.stderr)
    return None


def inject_via_cdp(port, script):
    """Inject script via CDP WebSocket."""
    ws_url = get_ws_url(port)
    if not ws_url:
        print("  找不到可注入的页面", file=sys.stderr)
        return False

    try:
        ws = websocket.create_connection(ws_url, timeout=10)
        msg = json.dumps({
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": script,
                "allowUnsafeEvalBlockedByCSP": True,
            }
        })
        ws.send(msg)
        result = json.loads(ws.recv())
        ws.close()
        if "result" in result and "result" in result["result"]:
            print("  ✓ 注入成功")
            return True
        else:
            print(f"  注入返回: {result}", file=sys.stderr)
            return False
    except ImportError:
        # Fallback: use urllib to send CDP command via HTTP
        print("  websocket-client 未安装，尝试 HTTP 注入...", file=sys.stderr)
        return inject_via_http(port, script)
    except Exception as e:
        print(f"  WebSocket 注入失败: {e}", file=sys.stderr)
        return False


def inject_via_http(port, script):
    """Fallback: inject via CDP HTTP endpoint."""
    try:
        # CDP doesn't have a direct HTTP evaluate endpoint,
        # but we can try the /json/protocol approach
        # Actually, we need websocket for Runtime.evaluate
        # Let's try a simpler approach: write a .js file and use --require
        print("  需要 websocket-client，请安装: pip install websocket-client", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  HTTP 注入失败: {e}", file=sys.stderr)
        return False


def start_codex_with_cdp(binary):
    """Start Codex with remote debugging enabled."""
    print(f"  启动 Codex (debug port: {DEBUG_PORT})...")
    env = os.environ.copy()
    # Ensure no existing instance blocks
    proc = subprocess.Popen(
        [binary, f"--remote-debugging-port={DEBUG_PORT}", "--remote-allow-origins=*"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc


def main():
    inject_only = False
    port = DEBUG_PORT

    if len(sys.argv) > 1:
        if sys.argv[1] == "--inject-only" and len(sys.argv) > 2:
            inject_only = True
            port = int(sys.argv[2])
        elif sys.argv[1] in ("-h", "--help"):
            print(__doc__)
            return

    print("Codex++ 插件市场解锁")
    print("━" * 30)

    codex_proc = None

    if not inject_only:
        binary = find_codex_binary()
        if not binary:
            print("  ✗ 找不到 Codex 桌面版，请确认已安装 openai-codex-desktop")
            sys.exit(1)
        print(f"  Codex: {binary}")
        codex_proc = start_codex_with_cdp(binary)
        # Wait for Codex to start
        print("  等待 Codex 启动...")
        time.sleep(5)

    # Inject
    print(f"  连接 CDP (port: {port})...")
    success = inject_via_cdp(port, UNLOCK_SCRIPT)

    if success:
        print("")
        print("  ✓ 插件市场已解锁！可以关闭此终端。")
        # JS 里的 setInterval 会持续运行，无需保持连接
    else:
        print("  ✗ 注入失败")
        if codex_proc:
            codex_proc.terminate()
        sys.exit(1)


if __name__ == "__main__":
    main()
