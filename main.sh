#!/usr/bin/env bash
# codex-provider-switch - Codex / Claude Code provider switcher
# Works with or without fzf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UV_RUN="uv run --directory $SCRIPT_DIR"

# Source modules
source "$SCRIPT_DIR/lib/claude_config.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/switch.sh"

# Init staging (changes go here first, user writes to real config later)
init_staging_codex
init_staging_claude

# ── staging indicator ───────────────────────────────────

_staging_badge() {
  local has_any=0
  has_codex_staging 2>/dev/null && has_any=1
  has_claude_staging 2>/dev/null && has_any=1
  [ "$has_any" -eq 1 ] && echo -e "  ${YELLOW}⚠ 有未写入的更改${NC}"
}

# ── menus ───────────────────────────────────────────────

show_codex_menu() {
  echo -e "${BOLD}${CYAN}Codex Provider Switch${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  local current
  current=$(get_current_provider)
  echo -e "  当前 provider: ${BOLD}${GREEN}${current}${NC}"
  [[ "$HAS_FZF" -eq 0 ]] && echo -e "  ${DIM}(未安装 fzf，使用数字选择模式)${NC}"
  _staging_badge
  echo ""

  local choice
  choice=$(choose "操作 > " \
    "🔄  切换 Provider" \
    "🤖  切换模型" \
    "➕  添加 Provider" \
    "✏️   编辑 Provider" \
    "🗑️   删除 Provider" \
    "📋  显示所有会话" \
    "🔓  解锁插件市场" \
    "📏  设置上下文大小" \
    "📋  查看当前配置" \
    "💾  写入配置文件" \
    "🗑️   放弃更改" \
    "↩️   返回" \
    "❌  退出")

  case "$choice" in
    *切换*Provider*)  do_switch; show_codex_menu ;;
    *模型*)          do_model; show_codex_menu ;;
    *添加*)          do_add; show_codex_menu ;;
    *编辑*)          do_edit; show_codex_menu ;;
    *删除*Provider*) do_delete; show_codex_menu ;;
    *显示*会话*)     do_show_all; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *解锁*)          do_unlock; show_codex_menu ;;
    *上下文*|*📏*)    do_context; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *查看*配置*)     do_show_config; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *写入*配置*)     do_apply; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *放弃*更改*)     do_discard; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *返回*)          choose_backend ;;
    *)               exit 0 ;;
  esac
}

show_claude_menu() {
  echo -e "${BOLD}${CYAN}Claude Code Provider Switch${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  local current
  current=$(get_current_provider)
  echo -e "  当前 provider: ${BOLD}${GREEN}${current}${NC}"
  [[ "$HAS_FZF" -eq 0 ]] && echo -e "  ${DIM}(未安装 fzf，使用数字选择模式)${NC}"
  _staging_badge
  echo ""

  local choice
  choice=$(choose "操作 > " \
    "🔄  切换 Provider" \
    "🤖  切换模型" \
    "📏  设置上下文大小" \
    "📋  查看当前配置" \
    "💾  写入配置文件" \
    "🗑️   放弃更改" \
    "↩️   返回" \
    "❌  退出")

  case "$choice" in
    *切换*Provider*)  do_switch; show_claude_menu ;;
    *模型*)          do_model_claude; show_claude_menu ;;
    *上下文*|*📏*)    do_context; echo ""; read -rp "按回车返回..."; show_claude_menu ;;
    *查看*配置*)     do_show_config; echo ""; read -rp "按回车返回..."; show_claude_menu ;;
    *写入*配置*)     do_apply; echo ""; read -rp "按回车返回..."; show_claude_menu ;;
    *放弃*更改*)     do_discard; echo ""; read -rp "按回车返回..."; show_claude_menu ;;
    *返回*)          choose_backend ;;
    *)               exit 0 ;;
  esac
}

choose_backend() {
  echo -e "${BOLD}${CYAN}Provider Switch${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  选择配置目标:"
  echo ""

  local has_codex=0 has_claude=0
  [ -f "$CODEX_CONFIG" ] && has_codex=1
  [ -f "$CLAUDE_CONFIG" ] && has_claude=1

  # If only one config exists, skip selection
  if [ "$has_codex" -eq 1 ] && [ "$has_claude" -eq 0 ]; then
    BACKEND="codex"
    show_codex_menu
    return
  elif [ "$has_codex" -eq 0 ] && [ "$has_claude" -eq 1 ]; then
    BACKEND="claude"
    show_claude_menu
    return
  elif [ "$has_codex" -eq 0 ] && [ "$has_claude" -eq 0 ]; then
    echo -e "${RED}未检测到 Codex 或 Claude Code 配置文件。${NC}"
    echo -e "${DIM}  Codex:  ${CODEX_CONFIG}${NC}"
    echo -e "${DIM}  Claude: ${CLAUDE_CONFIG}${NC}"
    exit 1
  fi

  # Both exist, let user choose
  local choice
  choice=$(choose "配置目标 > " \
    "Codex" \
    "Claude Code" \
    "❌  退出")

  case "$choice" in
    *Codex*)   BACKEND="codex";  show_codex_menu ;;
    *Claude*)  BACKEND="claude"; show_claude_menu ;;
    *)         exit 0 ;;
  esac
}

# ── entry ────────────────────────────────────────────────

# CLI backend override
case "${1:-}" in
  --claude)  BACKEND="claude"; shift ;;
  --codex)   BACKEND="codex"; shift ;;
esac

# CLI subcommand mode
if [ -n "${1:-}" ]; then
  # If no backend set via flag, auto-detect
  if [ -z "$BACKEND" ]; then
    if [ -f "$CODEX_CONFIG" ]; then
      BACKEND="codex"
    elif [ -f "$CLAUDE_CONFIG" ]; then
      BACKEND="claude"
    else
      echo -e "${RED}未检测到配置文件。${NC}"
      exit 1
    fi
  fi

  case "$1" in
    switch|s)     do_switch ;;
    model|m)      [ "$BACKEND" = "claude" ] && do_model_claude || do_model ;;
    add|a)        do_add ;;
    edit|e)       do_edit ;;
    delete|d)     do_delete ;;
    list|ls)      do_list ;;
    config|c)     do_show_config ;;
    context|ctx)  do_context ;;
    apply)        do_apply ;;
    discard)      do_discard ;;
    unlock|u)     do_unlock ;;
    show-all|sa)  $UV_RUN python3 "$SCRIPT_DIR/lib/sync.py" "${2:-}" ;;
    *)            echo "用法: $0 [--codex|--claude] [switch|model|add|edit|delete|list|config|context|apply|discard|unlock|show-all]" ;;
  esac
  exit 0
fi

# Interactive mode
choose_backend
