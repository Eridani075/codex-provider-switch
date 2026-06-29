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

# ── startup summary ────────────────────────────────────

show_startup_summary() {
  local has_codex=0 has_claude=0
  [ -f "$CODEX_CONFIG" ] && has_codex=1
  [ -f "$CLAUDE_CONFIG" ] && has_claude=1

  if [ "$has_codex" -eq 0 ] && [ "$has_claude" -eq 0 ]; then
    return
  fi

  local title="当前配置"
  local tw
  tw=$(_display_width "$title")
  local border=$(_repeat_char "━" $((tw + 4)))

  echo ""
  echo -e "${BOLD}${CYAN}━━${title}━━${NC}"
  echo ""

  if [ "$has_codex" -eq 1 ]; then
    local provider model ctx provider_count
    provider=$(co_get_current_provider)
    model=$(co_get_current_model)
    ctx=$(get_context_display)
    provider_count=$(co_parse_providers | wc -l)

    echo -e "  ${BOLD}Codex${NC}  ${DIM}${CODEX_CONFIG}${NC}"
    echo -e "    provider:  ${GREEN}${provider}${NC}"
    echo -e "    model:     ${GREEN}${model}${NC}"
    [ -n "$ctx" ] && echo -e "    上下文:    ${GREEN}${ctx}${NC}"
    echo -e "    providers: ${GREEN}${provider_count}${NC} 个"
    echo ""
  fi

  if [ "$has_claude" -eq 1 ]; then
    local url tier ctx
    url=$(cl_get_provider_url)
    tier=$(_cl_read "model")
    ctx=$(cl_get_context_1m)

    echo -e "  ${BOLD}Claude Code${NC}  ${DIM}${CLAUDE_CONFIG}${NC}"
    echo -e "    URL:   ${GREEN}${url:-未设置}${NC}"
    echo -e "    激活:  ${GREEN}${tier:-未设置}${NC}"

    local models_raw
    models_raw=$(cl_get_models)
    if [ -n "$models_raw" ]; then
      while IFS='|' read -r mtier mid active; do
        local mark=" "
        [ -n "$active" ] && mark="${GREEN}✓${NC}"
        echo -e "    ${mark} ${mtier}: ${GREEN}${mid:-未设置}${NC}"
      done <<< "$models_raw"
    fi

    echo -e "    上下文: ${GREEN}${ctx}${NC}"
    echo ""
  fi

  echo -e "${BOLD}${CYAN}${border}${NC}"
}

show_startup_summary

# ── staging indicator ───────────────────────────────────

_staging_badge() {
  if [ "$BACKEND" = "claude" ]; then
    has_claude_staging 2>/dev/null && echo -e "  ${YELLOW}⚠ 有未写入的更改${NC}"
  else
    has_codex_staging 2>/dev/null && echo -e "  ${YELLOW}⚠ 有未写入的更改${NC}"
  fi
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
    "➕  添加 Provider" \
    "✏️  编辑 Provider" \
    "🚫  删除 Provider" \
    "🤖  切换模型" \
    "📏  设置上下文大小" \
    "📑  显示所有会话" \
    "🔓  解锁插件市场" \
    "🔍  查看当前配置" \
    "💾  写入配置文件" \
    "⏪  放弃更改" \
    "↩️  返回" \
    "❌  退出")

  case "$choice" in
    *切换*Provider*)  do_switch; show_codex_menu ;;
    *添加*)          do_add; show_codex_menu ;;
    *编辑*)          do_edit; show_codex_menu ;;
    *删除*Provider*) do_delete; show_codex_menu ;;
    *模型*)          do_model; show_codex_menu ;;
    *上下文*|*📏*)    do_context; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *显示*会话*)     do_show_all; echo ""; read -rp "按回车返回..."; show_codex_menu ;;
    *解锁*)          do_unlock; show_codex_menu ;;
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
    "🔍  查看当前配置" \
    "💾  写入配置文件" \
    "⏪  放弃更改" \
    "↩️  返回" \
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

  local has_codex=0 has_claude=0
  [ -f "$CODEX_CONFIG" ] && has_codex=1
  [ -f "$CLAUDE_CONFIG" ] && has_claude=1

  # Always show selection, but mark unavailable backends
  local options=()
  if [ "$has_codex" -eq 1 ]; then
    options+=("Codex")
  else
    options+=("Codex ${DIM}(未检测到 ${CODEX_CONFIG})${NC}")
  fi
  if [ "$has_claude" -eq 1 ]; then
    options+=("Claude Code")
  else
    options+=("Claude Code ${DIM}(未检测到 ${CLAUDE_CONFIG})${NC}")
  fi
  options+=("❌  退出")

  local choice
  choice=$(choose "配置目标 > " "${options[@]}")

  case "$choice" in
    *Codex*)
      if [ "$has_codex" -eq 0 ]; then
        echo -e "${RED}未检测到 Codex 配置文件: ${CODEX_CONFIG}${NC}"
        read -rp "按回车返回..."; choose_backend; return
      fi
      BACKEND="codex"
      show_codex_menu
      ;;
    *Claude*)
      if [ "$has_claude" -eq 0 ]; then
        echo -e "${RED}未检测到 Claude Code 配置文件: ${CLAUDE_CONFIG}${NC}"
        read -rp "按回车返回..."; choose_backend; return
      fi
      BACKEND="claude"
      show_claude_menu
      ;;
    *) exit 0 ;;
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
