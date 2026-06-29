#!/usr/bin/env bash
# codex-provider-switch - Codex provider switcher
# Works with or without fzf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UV_RUN="uv run --directory $SCRIPT_DIR"

# Source modules
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/switch.sh"

# ── main menu ────────────────────────────────────────────

show_menu() {
  echo -e "${BOLD}${CYAN}Codex Provider Switch${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  local current
  current=$(get_current_provider)
  echo -e "  当前 provider: ${BOLD}${GREEN}${current}${NC}"
  [[ "$HAS_FZF" -eq 0 ]] && echo -e "  ${DIM}(未安装 fzf，使用数字选择模式)${NC}"
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
    "📋  查看当前配置" \
    "❌  退出")

  case "$choice" in
    *切换*Provider*)  do_switch; show_menu ;;
    *模型*)  do_model; show_menu ;;
    *添加*)  do_add; show_menu ;;
    *编辑*)  do_edit; show_menu ;;
    *删除*)  do_delete; show_menu ;;
    *显示*)  do_show_all; echo ""; read -rp "按回车返回..."; show_menu ;;
    *解锁*)  do_unlock; show_menu ;;
    *查看*)  do_show_config; echo ""; read -rp "按回车返回..."; show_menu ;;
    *)       exit 0 ;;
  esac
}

# ── entry ────────────────────────────────────────────────

if [[ ! -f "$CODEX_CONFIG" ]]; then
  echo -e "${RED}找不到 ${CODEX_CONFIG}${NC}"
  exit 1
fi

case "${1:-}" in
  switch|s)  do_switch ;;
  model|m)   do_model ;;
  add|a)     do_add ;;
  edit|e)    do_edit ;;
  delete|d)  do_delete ;;
  list|ls)   do_list ;;
  config|c)  do_show_config ;;
  unlock|u)  do_unlock ;;
  show-all|sa)
    $UV_RUN python3 "$SCRIPT_DIR/lib/sync.py" "${2:-}"
    ;;
  *)         show_menu ;;
esac
