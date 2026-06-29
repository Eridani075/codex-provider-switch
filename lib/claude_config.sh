#!/usr/bin/env bash
# claude_config.sh - Claude Code settings.json with staging
# Real config structure:
#   env.ANTHROPIC_BASE_URL          → provider URL
#   env.ANTHROPIC_AUTH_TOKEN        → API key
#   env.ANTHROPIC_DEFAULT_{TIER}_MODEL      → model ID
#   env.ANTHROPIC_DEFAULT_{TIER}_MODEL_NAME → model display name
#   model → active tier (opus/sonnet/haiku)
# Source this file, don't run directly.

CLAUDE_CONFIG="${CLAUDE_CONFIG:-$HOME/.claude/settings.json}"

# ── staging ─────────────────────────────────────────────

CLAUDE_STAGED=""

init_staging_claude() {
  [ ! -f "$CLAUDE_CONFIG" ] && return
  CLAUDE_STAGED=$(mktemp)
  cp "$CLAUDE_CONFIG" "$CLAUDE_STAGED"
}

has_claude_staging() {
  [ -n "$CLAUDE_STAGED" ] && [ -f "$CLAUDE_STAGED" ]
}

apply_staging_claude() {
  if ! has_claude_staging; then
    echo -e "${YELLOW}Claude Code: 没有待写入的更改${NC}"
    return
  fi
  if [ -f "$CLAUDE_CONFIG" ]; then
    cp "$CLAUDE_CONFIG" "${CLAUDE_CONFIG}.bak"
  fi
  cp "$CLAUDE_STAGED" "$CLAUDE_CONFIG"
  rm -f "$CLAUDE_STAGED"
  CLAUDE_STAGED=""
  echo -e "${GREEN}Claude Code 配置已写入 (${CLAUDE_CONFIG}.bak 已备份)${NC}"
}

discard_staging_claude() {
  if has_claude_staging; then
    rm -f "$CLAUDE_STAGED"
    CLAUDE_STAGED=""
    echo -e "${YELLOW}Claude Code 更改已丢弃${NC}"
  fi
}

_cl_cfg() {
  if [ -n "$CLAUDE_STAGED" ] && [ -f "$CLAUDE_STAGED" ]; then
    echo "$CLAUDE_STAGED"
  else
    echo "$CLAUDE_CONFIG"
  fi
}

# ── Python JSON helpers ─────────────────────────────────

_cl_read() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
# Navigate dot-separated path: 'env.ANTHROPIC_BASE_URL' → data['env']['ANTHROPIC_BASE_URL']
keys = sys.argv[2].split('.')
val = data
for k in keys:
    if isinstance(val, dict):
        val = val.get(k, '')
    else:
        val = ''
        break
print(val if isinstance(val, str) else json.dumps(val) if val else '')
" "$cfg" "$1" 2>/dev/null
}

_cl_write_env() {
  local key="$1" val="$2"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
ekey = sys.argv[2]
eval_ = sys.argv[3]
with open(path) as f:
    data = json.load(f)
if 'env' not in data:
    data['env'] = {}
data['env'][ekey] = eval_
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg" "$key" "$val"
}

_cl_write_top() {
  local key="$1" val="$2"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
key = sys.argv[2]
val = sys.argv[3]
with open(path) as f:
    data = json.load(f)
try:
    data[key] = json.loads(val)
except (json.JSONDecodeError, ValueError):
    data[key] = val
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg" "$key" "$val"
}

# ── Provider (reads/writes env vars) ───────────────────

cl_get_current_provider() {
  local url
  url=$(_cl_read "env.ANTHROPIC_BASE_URL")
  if [ -n "$url" ]; then
    echo "$url"
  else
    echo "(未配置)"
  fi
}

cl_set_current_provider() {
  local url="$1" token="$2"
  _cl_write_env "ANTHROPIC_BASE_URL" "$url"
  if [ -n "$token" ]; then
    _cl_write_env "ANTHROPIC_AUTH_TOKEN" "$token"
  fi
}

# Parse provider info from env vars.
# Output: url|token (single line, Claude Code only has one provider)
cl_parse_providers() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
env = data.get('env', {})
url = env.get('ANTHROPIC_BASE_URL', '')
token = env.get('ANTHROPIC_AUTH_TOKEN', '')
if url:
    masked = token[:8] + '****' if len(token) > 8 else token
    print(f'{url}|{masked}')
" "$cfg" 2>/dev/null
}

cl_get_provider_url() {
  _cl_read "env.ANTHROPIC_BASE_URL"
}

cl_get_provider_token() {
  _cl_read "env.ANTHROPIC_AUTH_TOKEN"
}

# Claude Code doesn't have multi-provider CRUD.
# These are no-ops kept for interface compatibility.
cl_append_provider() {
  echo -e "${YELLOW}Claude Code 只支持单 provider，使用「切换 Provider」修改${NC}"
}
cl_update_provider_fields() {
  local url="$2" token="$3"
  [ -n "$url" ] && _cl_write_env "ANTHROPIC_BASE_URL" "$url"
  [ -n "$token" ] && _cl_write_env "ANTHROPIC_AUTH_TOKEN" "$token"
}
cl_remove_provider() {
  echo -e "${YELLOW}Claude Code 不支持删除 provider，请直接切换${NC}"
}

# ── Model tiers (opus/sonnet/haiku) ─────────────────────

CLAUDE_MODEL_TIERS="opus sonnet haiku"

cl_get_models() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
env = data.get('env', {})
active_tier = data.get('model', '')
for tier in ['opus', 'sonnet', 'haiku']:
    key = f'ANTHROPIC_DEFAULT_{tier.upper()}_MODEL'
    mid = env.get(key, '')
    active = '*' if tier == active_tier else ''
    print(f'{tier}|{mid}|{active}')
" "$cfg" 2>/dev/null
}

cl_get_current_model() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
env = data.get('env', {})
tier = data.get('model', '')
if tier:
    key = f'ANTHROPIC_DEFAULT_{tier.upper()}_MODEL'
    mid = env.get(key, '')
    print(f'{tier} ({mid})' if mid else tier)
else:
    print('(未设置)')
" "$cfg" 2>/dev/null
}

cl_set_current_model() {
  local tier="$1"
  _cl_write_top "model" "$tier"
}

cl_set_model_id() {
  local tier="$1" model_id="$2"
  local env_key="ANTHROPIC_DEFAULT_${tier^^}_MODEL"
  _cl_write_env "$env_key" "$model_id"
}

# ── Context size ─────────────────────────────────────────
# Claude Code: binary toggle via CLAUDE_CODE_MAX_CONTEXT_TOKENS env var
# 1M = 1048576 tokens, or unset for standard

cl_get_context_1m() {
  local val
  val=$(_cl_read "env.CLAUDE_CODE_MAX_CONTEXT_TOKENS")
  if [ "$val" = "1048576" ]; then
    echo "1M"
  else
    echo "标准"
  fi
}

cl_set_context_1m() {
  local enabled="$1"  # "1" to enable 1M, "0" to disable
  if [ "$enabled" = "1" ]; then
    _cl_write_env "CLAUDE_CODE_MAX_CONTEXT_TOKENS" "1048576"
  else
    # Remove the key
    local cfg
    cfg="$(_cl_cfg)"
    python3 -c "
import sys, json
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
env = data.get('env', {})
env.pop('CLAUDE_CODE_MAX_CONTEXT_TOKENS', None)
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg"
  fi
}
