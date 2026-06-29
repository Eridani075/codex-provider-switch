# codex-provider-switch

Codex / Claude Code provider 切换工具。

## 功能

- 切换/添加/编辑/删除模型提供商
- 切换模型（从 provider API 动态获取）
- Claude Code 三模型配置（opus / sonnet / haiku）
- 设置上下文大小（max_tokens）
- 解锁插件市场（仅 Codex）
- 统一会话显示（跨 provider 会话合并，仅 Codex）
- 自动检测并切换 Codex / Claude Code 后端

## 安装

```bash
git clone <repo-url>
cd codex-provider-switch
chmod +x main.sh
```

依赖：bash、curl、python3、fzf（可选）

## 使用

```bash
# 交互菜单（自动检测后端）
./main.sh

# 指定后端
./main.sh --codex
./main.sh --claude

# CLI
./main.sh switch    # 切换 provider
./main.sh model     # 切换模型
./main.sh add       # 添加 provider
./main.sh list      # 列出所有 provider
./main.sh unlock    # 解锁插件市场（Codex）
./main.sh show-all  # 统一会话显示（Codex）
./main.sh backend   # 切换后端
```

## Claude Code 配置

在 `~/.claude/settings.json` 中配置：

```json
{
  "model": "sonnet",
  "models": {
    "opus": "claude-opus-4-20250514",
    "sonnet": "claude-sonnet-4-20250514",
    "haiku": "claude-haiku-4-20251001"
  },
  "max_tokens": 16384,
  "active_provider": "my-api",
  "providers": {
    "my-api": {
      "name": "My API",
      "base_url": "https://api.example.com/v1",
      "api_key": "sk-xxx"
    }
  }
}
```

## 平台支持

- Linux（原生）
- macOS（原生，BSD 工具链兼容）
- Windows（WSL / Git Bash）

## 致谢

- 插件市场解锁功能参考 [CodexPlusPlus](https://github.com/BigPizzaV3/CodexPlusPlus) 项目的 CDP 注入方案

## License

MIT
