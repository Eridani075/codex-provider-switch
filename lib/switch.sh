#!/usr/bin/env bash
# switch.sh - Provider switch/add/edit/delete operations
# Source this file, don't run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UV_RUN="${UV_RUN:-uv run --directory "$SCRIPT_DIR/.."}"

do_switch() {
  if [ "$BACKEND" = "claude" ]; then
    _do_switch_claude
  else
    _do_switch_codex
  fi
}

_do_switch_codex() {
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

_do_switch_claude() {
  local cur_url cur_token
  cur_url=$(cl_get_provider_url)
  cur_token=$(cl_get_provider_token)

  echo -e "${CYAN}切换 Claude Code Provider${NC}"
  echo ""
  echo -e "  当前 URL:   ${GREEN}${cur_url:-未设置}${NC}"
  local masked="(未设置)"
  [ -n "$cur_token" ] && masked="${cur_token:0:8}****"
  echo -e "  当前 Token: ${GREEN}${masked}${NC}"
  echo ""
  echo -e "  ${DIM}留空保持不变${NC}"
  echo ""

  read -rp "新的 Base URL: " new_url
  read -rp "新的 API Key:  " new_token

  new_url="${new_url:-$cur_url}"
  new_token="${new_token:-$cur_token}"

  if [ -z "$new_url" ]; then
    echo -e "${RED}URL 不能为空${NC}"
    return
  fi

  cl_set_current_provider "$new_url" "$new_token"
  echo -e "${GREEN}已更新 provider${NC}"
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

  if [ "$BACKEND" = "claude" ]; then
    echo -e "${GREEN}已删除: ${key}${NC}"
  else
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
  local backend_label="Codex"
  [ "$BACKEND" = "claude" ] && backend_label="Claude Code"

  echo -e "${CYAN}${backend_label} 配置摘要${NC}"
  echo ""

  if [ "$BACKEND" = "claude" ]; then
    local url token model tokens models_raw
    url=$(cl_get_provider_url)
    token=$(cl_get_provider_token)
    model=$(get_current_model)
    tokens=$(get_max_tokens)

    echo -e "${BOLD}Provider:${NC}"
    echo -e "  URL:   ${GREEN}${url:-未设置}${NC}"
    local masked="(未设置)"
    [ -n "$token" ] && masked="${token:0:8}****"
    echo -e "  Token: ${GREEN}${masked}${NC}"
    echo ""

    echo -e "${BOLD}模型:${NC}"
    echo -e "  激活: ${GREEN}${model}${NC}"
    models_raw=$(get_models)
    if [ -n "$models_raw" ]; then
      while IFS='|' read -r tier mid active; do
        local marker=" "
        [ -n "$active" ] && marker="${GREEN}✓${NC}"
        echo -e "  ${marker} ${BOLD}${tier}${NC}: ${GREEN}${mid:-未设置}${NC}"
      done <<< "$models_raw"
    fi
    local ctx
    ctx=$(cl_get_context_1m)
    echo -e "\n  上下文: ${GREEN}${ctx}${NC}"
  else
    local current model ctx
    current=$(get_current_provider)
    model=$(get_current_model)
    ctx=$(get_context_display)

    echo -e "  provider = ${BOLD}${GREEN}${current}${NC}"
    echo -e "  model    = ${BOLD}${GREEN}${model}${NC}"
    [ -n "$ctx" ] && echo -e "  上下文   = ${BOLD}${GREEN}${ctx}${NC}"

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

do_switch_backend() {
  local has_codex=0 has_claude=0
  [ -f "$CODEX_CONFIG" ] && has_codex=1
  [ -f "$CLAUDE_CONFIG" ] && has_claude=1

  local options=()
  if [ "$has_codex" -eq 1 ]; then
    local marker=""
    [ "$BACKEND" = "codex" ] && marker=" ${GREEN}✓${NC}"
    options+=("Codex${marker}")
  fi
  if [ "$has_claude" -eq 1 ]; then
    local marker=""
    [ "$BACKEND" = "claude" ] && marker=" ${GREEN}✓${NC}"
    options+=("Claude Code${marker}")
  fi
  options+=("↩️  保持不变")

  if [ ${#options[@]} -le 1 ]; then
    echo -e "${YELLOW}只检测到一个后端，无需切换${NC}"
    return
  fi

  local choice
  choice=$(choose "切换后端 > " "${options[@]}")

  case "$choice" in
    *Codex*)    BACKEND="codex";  echo -e "${GREEN}已切换到: ${BOLD}Codex${NC}" ;;
    *Claude*)   BACKEND="claude"; echo -e "${GREEN}已切换到: ${BOLD}Claude Code${NC}" ;;
    *)          return ;;
  esac
}

# ── Claude Code 3-model editor ──────────────────────────

do_model_claude() {
  local current_tier
  current_tier=$(_cl_json_get "model")
  [ -z "$current_tier" ] && current_tier="(未设置)"

  echo -e "${CYAN}Claude Code 模型配置${NC}"
  echo -e "  当前激活: ${BOLD}${GREEN}${current_tier}${NC}"
  echo ""

  local models_raw
  models_raw=$(get_models)

  if [ -z "$models_raw" ]; then
    echo -e "${RED}无法读取模型配置。${NC}"
    return
  fi

  # Build options from 3 tiers
  local options=()
  while IFS='|' read -r tier mid active; do
    local label="${tier}"
    [ -n "$mid" ] && label="${tier} — ${mid}"
    [ -n "$active" ] && label="${label} ${GREEN}✓ 当前${NC}"
    options+=("${label}")
  done <<< "$models_raw"
  options+=("✏️  编辑模型 ID")
  options+=("↩️  保持不变")

  local choice
  choice=$(choose "选择模型 > " "${options[@]}")

  case "$choice" in
    *保持*|*↩️*|"")  return ;;
    *编辑*|*✏️*)
      echo ""
      echo -e "${CYAN}编辑模型 ID${NC}"
      local edit_options=()
      while IFS='|' read -r tier mid active; do
        local label="${tier}"
        [ -n "$mid" ] && label="${tier} [${mid}]"
        edit_options+=("${label}")
      done <<< "$models_raw"
      edit_options+=("↩️  返回")

      local edit_choice
      edit_choice=$(choose "编辑哪个 > " "${edit_options[@]}")

      case "$edit_choice" in
        *返回*|*↩️*|"")  return ;;
        *)
          local edit_tier
          edit_tier=$(echo "$edit_choice" | awk '{print $1}')
          echo ""
          read -rp "输入 ${edit_tier} 的模型 ID: " new_id
          if [ -n "$new_id" ]; then
            set_model_id "$edit_tier" "$new_id"
            echo -e "${GREEN}${edit_tier} 已更新为: ${BOLD}${new_id}${NC}"
          fi
          ;;
      esac
      ;;
    *)
      # Select tier as active
      local new_tier
      new_tier=$(echo "$choice" | awk '{print $1}')
      set_current_model "$new_tier"
      echo -e "${GREEN}已切换到: ${BOLD}${new_tier}${NC}"
      ;;
  esac
}

# ── Context size ─────────────────────────────────────────

do_context() {
  if [ "$BACKEND" = "claude" ]; then
    _do_context_claude
  else
    _do_context_codex
  fi
}

_do_context_claude() {
  local current
  current=$(cl_get_context_1m)

  echo -e "${CYAN}Claude Code 上下文大小${NC}"
  echo -e "  当前: ${BOLD}${GREEN}${current}${NC}"
  echo ""

  local choice
  choice=$(choose "上下文 > " \
    "1M (1048576 tokens)" \
    "标准 (默认)" \
    "↩️  保持不变")

  case "$choice" in
    *1M*)    cl_set_context_1m 1; echo -e "${GREEN}已设置为: ${BOLD}1M${NC}" ;;
    *标准*)  cl_set_context_1m 0; echo -e "${GREEN}已设置为: ${BOLD}标准${NC}" ;;
    *)       return ;;
  esac
}

_do_context_codex() {
  local current
  current=$(co_get_max_tokens)

  echo -e "${CYAN}Codex 上下文大小 (max_tokens)${NC}"
  if [ -n "$current" ]; then
    local display
    display=$(get_context_display)
    echo -e "  当前值: ${BOLD}${GREEN}${display}${NC}"
  fi
  echo ""
  echo -e "  ${DIM}输入格式: 数字 + 单位${NC}"
  echo -e "  ${DIM}  16m → 16384   32m → 32768   64m → 65536${NC}"
  echo -e "  ${DIM}  512k → 512     1m → 1024${NC}"
  echo ""

  read -rp "输入上下文大小 (留空保持不变): " input

  if [ -z "$input" ]; then
    return
  fi

  # Parse M/K units
  local tokens
  input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
  if echo "$input" | grep -q '^[0-9]\+m$'; then
    local num=${input%m}
    tokens=$((num * 1024))
  elif echo "$input" | grep -q '^[0-9]\+k$'; then
    local num=${input%k}
    tokens=$num
  elif echo "$input" | grep -q '^[0-9]\+$'; then
    tokens=$input
  else
    echo -e "${RED}格式错误，示例: 16m / 512k / 16384${NC}"
    return
  fi

  co_set_max_tokens "$tokens"
  echo -e "${GREEN}max_tokens 已设置为: ${BOLD}${tokens}${NC} (${input})"
}

# ── Apply / Discard staging ─────────────────────────────

do_apply() {
  echo -e "${CYAN}写入配置${NC}"
  echo ""

  local has_any=0
  if has_codex_staging; then has_any=1; fi
  if has_claude_staging; then has_any=1; fi

  if [ "$has_any" -eq 0 ]; then
    echo -e "${YELLOW}没有待写入的更改${NC}"
    return
  fi

  if has_codex_staging; then
    echo -e "  ${BOLD}Codex${NC}: ${CODEX_CONFIG}"
  fi
  if has_claude_staging; then
    echo -e "  ${BOLD}Claude Code${NC}: ${CLAUDE_CONFIG}"
  fi
  echo ""

  read -rp "确认写入配置文件？原文件将备份为 .bak (y/N): " yn
  if [[ ! "$yn" =~ ^[Yy] ]]; then
    echo -e "${YELLOW}已取消${NC}"
    return
  fi

  if has_codex_staging; then
    apply_staging_codex
  fi
  if has_claude_staging; then
    apply_staging_claude
  fi
}

do_discard() {
  echo -e "${CYAN}放弃更改${NC}"
  echo ""

  local has_any=0
  if has_codex_staging; then has_any=1; fi
  if has_claude_staging; then has_any=1; fi

  if [ "$has_any" -eq 0 ]; then
    echo -e "${YELLOW}没有待放弃的更改${NC}"
    return
  fi

  read -rp "确认放弃所有未写入的更改？ (y/N): " yn
  if [[ ! "$yn" =~ ^[Yy] ]]; then
    echo -e "${YELLOW}已取消${NC}"
    return
  fi

  discard_staging_codex
  discard_staging_claude
}
