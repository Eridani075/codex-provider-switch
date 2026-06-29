#!/usr/bin/env bash
# switch.sh - Provider switch/add/edit/delete operations
# Source this file, don't run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UV_RUN="${UV_RUN:-uv run --directory "$SCRIPT_DIR/.."}"

do_switch() {
  local current
  current=$(get_current_provider)

  local providers
  providers=$(parse_providers)

  if [[ -z "$providers" ]]; then
    echo -e "${RED}没有已配置的 provider，请先添加。${NC}"
    return
  fi

  local selected
  selected=$(pick_provider "$current" "$providers")

  [[ -z "$selected" ]] && return

  local new_key
  new_key=$(echo "$selected" | cut -d'|' -f1)

  set_current_provider "$new_key"
  echo -e "${GREEN}已切换到: ${BOLD}${new_key}${NC}"
  echo -e "${DIM}提示: 使用「显示所有会话」可查看跨 provider 的全部聊天记录${NC}"
}

do_add() {
  echo -e "${CYAN}添加新 Provider${NC}"
  echo ""

  read -rp "Provider ID (英文, 如 my-api): " provider_id
  [[ -z "$provider_id" ]] && return

  read -rp "显示名称: " display_name
  [[ -z "$display_name" ]] && display_name="$provider_id"

  read -rp "Base URL (如 https://api.example.com/v1): " base_url
  if [[ -z "$base_url" ]]; then
    echo -e "${RED}URL 不能为空${NC}"
    return
  fi

  read -rp "API Key (sk-xxx): " api_key
  echo ""

  append_provider "$provider_id" "$display_name" "$base_url" "$api_key"
  echo -e "${GREEN}已添加 provider: ${provider_id}${NC}"

  read -rp "是否立即切换到此 provider? (y/N): " yn
  if [[ "$yn" =~ ^[Yy] ]]; then
    set_current_provider "$provider_id"
    echo -e "${GREEN}已切换到: ${provider_id}${NC}"
  fi
}

do_edit() {
  local providers
  providers=$(parse_providers)

  if [[ -z "$providers" ]]; then
    echo -e "${RED}没有已配置的 provider${NC}"
    return
  fi

  local selected
  selected=$(pick_provider "" "$providers")
  [[ -z "$selected" ]] && return

  local key cur_url cur_token
  key=$(echo "$selected" | cut -d'|' -f1)
  cur_url=$(echo "$selected" | cut -d'|' -f3)
  cur_token=$(echo "$selected" | cut -d'|' -f5)

  echo -e "编辑 ${BOLD}${key}${NC} (留空保持不变)"
  read -rp "Base URL [${cur_url}]: " new_url
  read -rp "API Key [****]: " new_token

  new_url="${new_url:-$cur_url}"
  new_token="${new_token:-$cur_token}"

  update_provider_fields "$key" "$new_url" "$new_token"
  echo -e "${GREEN}已更新${NC}"
}

do_delete() {
  local providers
  providers=$(parse_providers)

  if [[ -z "$providers" ]]; then
    echo -e "${RED}没有已配置的 provider${NC}"
    return
  fi

  local selected
  selected=$(pick_provider "" "$providers")
  [[ -z "$selected" ]] && return

  local key
  key=$(echo "$selected" | cut -d'|' -f1)

  read -rp "确定删除 ${key}? (y/N): " yn
  [[ ! "$yn" =~ ^[Yy] ]] && return

  remove_provider "$key"

  local current
  current=$(get_current_provider)
  if [ "$current" = "$key" ]; then
    local tmp
    tmp=$(mktemp)
    sed '/^[[:space:]]*model_provider[[:space:]]*=/d' "$CODEX_CONFIG" > "$tmp"
    mv "$tmp" "$CODEX_CONFIG"
    echo -e "${YELLOW}已删除当前 provider，model_provider 已清除${NC}"
  else
    echo -e "${GREEN}已删除: ${key}${NC}"
  fi
}

do_list() {
  local current
  current=$(get_current_provider)
  echo -e "${BOLD}当前: ${GREEN}${current}${NC}"
  echo ""

  local providers
  providers=$(parse_providers)

  if [[ -z "$providers" ]]; then
    echo -e "${YELLOW}无自定义 provider${NC}"
    return
  fi

  echo "$providers" | while IFS='|' read -r key name url wire token model; do
    local masked="****"
    [[ -z "$token" ]] && masked="(无)"
    local marker=" "
    [[ "$key" == "${current% (默认)}" ]] && marker="${GREEN}✓${NC}"
    echo -e "  ${marker} ${BOLD}${key}${NC} — ${name} @ ${url} [${masked}]"
  done
}

do_unlock() {
  if [[ ! -f "$SCRIPT_DIR/unlock.py" ]]; then
    echo -e "${RED}找不到 unlock.py${NC}"
    return
  fi

  # Sync uv environment first
  uv sync --directory "$SCRIPT_DIR/.." 2>/dev/null

  $UV_RUN python3 "$SCRIPT_DIR/unlock.py"
}

do_show_config() {
  echo -e "${CYAN}当前 Codex 配置摘要${NC}"
  echo ""

  local current
  current=$(get_current_provider)
  echo -e "  model_provider = ${BOLD}${GREEN}${current}${NC}"
  echo ""

  local providers
  providers=$(parse_providers)

  if [[ -n "$providers" ]]; then
    echo -e "${BOLD}已配置的 Providers:${NC}"
    echo "$providers" | while IFS='|' read -r key name url wire token model; do
      local marker=" "
      [[ "$key" == "${current% (默认)}" ]] && marker="${GREEN}✓${NC}"
      local masked_token="****"
      [[ -z "$token" ]] && masked_token="(无)"
      echo -e "  ${marker} ${BOLD}${key}${NC}"
      echo -e "    名称: ${name}"
      echo -e "    URL:  ${url}"
      echo -e "    Key:  ${masked_token}"
      echo ""
    done
  else
    echo -e "${YELLOW}无自定义 provider${NC}"
  fi
}

# Fetch available models from provider's /v1/models endpoint.
# Args: base_url, token
# Prints one model id per line to stdout.
fetch_models() {
  local base_url="$1" token="$2"
  local url="${base_url%/}/models"

  local response
  if [ -n "$token" ]; then
    response=$(curl -sS --fail --max-time 10 \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      "$url" 2>&1) || true
  else
    response=$(curl -sS --fail --max-time 10 \
      -H "Content-Type: application/json" \
      "$url" 2>&1) || true
  fi

  if [ -z "$response" ]; then
    echo "请求失败: $url" >&2
    return 1
  fi

  local result
  result=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    models = data.get('data', data) if isinstance(data, dict) else data
    if isinstance(models, list):
        ids = sorted(m.get('id', '') for m in models if isinstance(m, dict) and m.get('id'))
        if ids:
            print('\n'.join(ids))
        else:
            sys.exit(1)
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
" <<< "$response") || true

  echo "$result"
}

do_model() {
  local current
  current=$(get_current_model)

  # Get current provider's base_url and token
  local provider_key
  provider_key=$(get_current_provider)
  provider_key="${provider_key% (默认)}"

  local provider_line
  provider_line=$(parse_providers | while IFS='|' read -r key name url wire token model; do
    [ "$key" = "$provider_key" ] && echo "${key}|${name}|${url}|${wire}|${token}|${model}" && break
  done)

  if [ -z "$provider_line" ]; then
    echo -e "${RED}未找到当前 provider 配置，请先添加。${NC}"
    return
  fi

  local base_url token
  base_url=$(echo "$provider_line" | cut -d'|' -f3)
  token=$(echo "$provider_line" | cut -d'|' -f5)

  echo -e "${CYAN}当前模型: ${BOLD}${GREEN}${current}${NC}"
  echo -e "${DIM}从 ${base_url}/models 获取模型列表...${NC}"
  echo ""

  local models_raw
  while true; do
    models_raw=$(fetch_models "$base_url" "$token")
    if [ -n "$models_raw" ]; then
      break
    fi
    echo -e "${RED}无法获取模型列表，请检查 provider 配置和网络。${NC}"
    local retry
    retry=$(choose "操作 > " "🔄  重试" "↩️  返回上一级")
    case "$retry" in
      *重试*) continue ;;
      *) return ;;
    esac
  done

  # Build options from fetched models
  local options=()
  while IFS= read -r m; do
    local marker=""
    [ "$m" = "$current" ] && marker=" ${GREEN}✓${NC}"
    options+=("${m}${marker}")
  done <<< "$models_raw"
  options+=("✏️  自定义输入")
  options+=("↩️  保持不变")

  local choice
  choice=$(choose "选择模型 > " "${options[@]}")

  case "$choice" in
    *保持*|*↩️*|"")  return ;;
    *自定义*|*✏️*)
      read -rp "输入模型名: " custom_model
      if [ -n "$custom_model" ]; then
        set_current_model "$custom_model"
        echo -e "${GREEN}已切换到: ${BOLD}${custom_model}${NC}"
      fi
      ;;
    *)
      local model_name
      model_name=$(echo "$choice" | sed 's/ *✓.*//')
      set_current_model "$model_name"
      echo -e "${GREEN}已切换到: ${BOLD}${model_name}${NC}"
      ;;
  esac
}

do_show_all() {
  local current
  current=$(get_current_provider)
  current="${current% (默认)}"

  echo -e "${CYAN}显示所有会话${NC}"
  echo -e "  将所有会话统一到当前 provider: ${BOLD}${GREEN}${current}${NC}"
  echo ""

  read -rp "确认? (Y/n): " yn
  [[ "$yn" =~ ^[Nn] ]] && return

  if [[ -f "$SCRIPT_DIR/sync.py" ]]; then
    $UV_RUN python3 "$SCRIPT_DIR/sync.py" "$current"
  else
    echo -e "${RED}找不到 sync.py${NC}"
  fi
}
