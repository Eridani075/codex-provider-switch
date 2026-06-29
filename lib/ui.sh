#!/usr/bin/env bash
# ui.sh - Interactive UI helpers (fzf with fallback)
# Source this file, don't run directly.

# Colors (must use $'...' so printf gets real ESC bytes, not literal \033)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

HAS_FZF=0
command -v fzf >/dev/null 2>&1 && HAS_FZF=1

# CJK-aware display width (approximate: each CJK char = 2 cols)
_display_width() {
  python3 -c "
import sys
s = sys.argv[1]
w = 0
for c in s:
    if ord(c) > 0x2E80:
        w += 2
    else:
        w += 1
print(w)
" "$1" 2>/dev/null
}

# Repeat a character N times
_repeat_char() {
  local char="$1" count="$2"
  printf "%0.s${char}" $(seq 1 "$count")
}

# Universal chooser. Usage: choose "prompt" "opt1" "opt2" ...
# Prints selected option to stdout.
choose() {
  local prompt="$1"
  shift
  local options=("$@")

  if [[ ${#options[@]} -eq 0 ]]; then
    echo ""
    return
  fi

  if [[ "$HAS_FZF" -eq 1 ]]; then
    printf '%s\n' "${options[@]}" | fzf --prompt="$prompt" --height=20 --reverse --no-multi --border --ansi
  else
    echo -e "${CYAN}${prompt}${NC}" >&2
    echo "" >&2
    local i=1
    for opt in "${options[@]}"; do
      echo -e "  ${BOLD}${i})${NC} $opt" >&2
      ((i++))
    done
    echo "" >&2
    read -rp "输入编号 [1-${#options[@]}], 0 取消: " choice >&2
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "${options[$((choice-1))]}"
    else
      echo ""
    fi
  fi
}

# Pick a provider from a providers list (output of parse_providers).
# Args: current_provider, providers_lines
# Prints selected "key|name|url|wire|token|model" line.
pick_provider() {
  local current="$1"
  local providers="$2"

  if [[ -z "$providers" ]]; then
    echo ""
    return
  fi

  if [[ "$HAS_FZF" -eq 1 ]]; then
    local header
    header=$(printf "%-20s %-30s %s" "名称" "Base URL" "状态")
    local selected
    selected=$(echo "$providers" | while IFS='|' read -r key name url wire token model; do
      local marker=""
      [[ "$key" == "$current" ]] && marker=" ${GREEN}✓ 当前${NC}"
      printf "%-20s %-30s %s\n" "$name" "$url" "$marker"
    done | fzf --prompt="选择 Provider > " --height=20 --reverse --no-multi --border \
               --ansi --header="$header")

    [[ -z "$selected" ]] && echo "" && return

    local provider_key
    provider_key=$(echo "$selected" | awk '{print $1}' | xargs)

    echo "$providers" | while IFS='|' read -r key name url wire token model; do
      [[ "$name" == "$provider_key" ]] && echo "${key}|${name}|${url}|${wire}|${token}|${model}" && break
    done
  else
    local i=1
    echo -e "${CYAN}选择 Provider:${NC}" >&2
    echo "" >&2
    while IFS='|' read -r key name url wire token model; do
      local marker=""
      [[ "$key" == "$current" ]] && marker=" ${GREEN}✓ 当前${NC}"
      echo -e "  ${BOLD}${i})${NC} ${name} — ${url}${marker}" >&2
      ((i++))
    done <<< "$providers"
    echo "" >&2

    local count
    count=$(echo "$providers" | wc -l)
    read -rp "输入编号 [1-${count}], 0 取消: " choice >&2

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      echo "$providers" | sed -n "${choice}p"
    else
      echo ""
    fi
  fi
}
