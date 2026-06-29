#!/usr/bin/env bash
# claude_config.sh - Claude Code settings.json with staging
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

# Returns the active config file (staged or real)
_cl_cfg() {
  if [ -n "$CLAUDE_STAGED" ] && [ -f "$CLAUDE_STAGED" ]; then
    echo "$CLAUDE_STAGED"
  else
    echo "$CLAUDE_CONFIG"
  fi
}

# ── JSON helpers (all use staged file) ──────────────────

_cl_json_get() {
  local key="$1"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
try:
    data = json.load(open(sys.argv[1]))
    val = data.get(sys.argv[2], '')
    print(val if isinstance(val, str) else json.dumps(val) if val else '')
except Exception:
    print('')
" "$cfg" "$key" 2>/dev/null
}

_cl_json_set() {
  local key="$1" val="$2"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
key = sys.argv[2]
val = sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
try:
    data[key] = json.loads(val)
except (json.JSONDecodeError, ValueError):
    data[key] = val
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg" "$key" "$val"
}

# ── 3-model support (opus/sonnet/haiku) ──────────────────

CLAUDE_MODEL_TIERS="opus sonnet haiku"

cl_get_models() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
models = data.get('models', {})
for tier in ['opus', 'sonnet', 'haiku']:
    mid = models.get(tier, '')
    active = data.get('model', '') == tier
    mark = '*' if active else ''
    print(f'{tier}|{mid}|{mark}')
" "$cfg" 2>/dev/null
}

cl_get_current_model() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    print('(未设置)')
    sys.exit(0)
model = data.get('model', '')
models = data.get('models', {})
if model in models:
    mid = models[model]
    print(f'{model} ({mid})' if mid else model)
elif model:
    print(model)
else:
    print('(未设置)')
" "$cfg" 2>/dev/null
}

cl_set_current_model() {
  local tier="$1"
  local is_tier=0
  for t in $CLAUDE_MODEL_TIERS; do
    [ "$tier" = "$t" ] && is_tier=1 && break
  done
  _cl_json_set "model" "$tier"
}

cl_set_model_id() {
  local tier="$1" model_id="$2"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
tier = sys.argv[2]
mid = sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
models = data.get('models', {})
models[tier] = mid
data['models'] = models
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg" "$tier" "$model_id"
}

# ── context size ─────────────────────────────────────────

cl_get_max_tokens() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    val = data.get('max_tokens', '')
    print(val if val else '')
except Exception:
    print('')
" "$cfg" 2>/dev/null
}

cl_set_max_tokens() {
  local tokens="$1"
  if [ -n "$tokens" ]; then
    _cl_json_set "max_tokens" "$tokens"
  fi
}

# ── providers ────────────────────────────────────────────

cl_parse_providers() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
providers = data.get('providers', {})
for key, cfg in sorted(providers.items()):
    if isinstance(cfg, dict):
        name = cfg.get('name', key)
        url = cfg.get('base_url', '')
        token = cfg.get('api_key', '')
        model = cfg.get('model', '')
        print(f'{key}|{name}|{url}||{token}|{model}')
" "$cfg" 2>/dev/null
}

cl_get_current_provider() {
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    print('(未配置)')
    sys.exit(0)
providers = data.get('providers', {})
active = data.get('active_provider', '')
if active and active in providers:
    print(active)
elif providers:
    print(list(providers.keys())[0])
else:
    print('(未配置)')
" "$cfg" 2>/dev/null
}

cl_set_current_provider() {
  local provider="$1"
  _cl_json_set "active_provider" "$provider"
}

cl_append_provider() {
  local id="$1" name="$2" url="$3" key="$4"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
pid = sys.argv[2]
name = sys.argv[3]
url = sys.argv[4]
akey = sys.argv[5]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
providers = data.get('providers', {})
providers[pid] = {
    'name': name,
    'base_url': url,
    'api_key': akey,
}
data['providers'] = providers
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg" "$id" "$name" "$url" "$key"
}

cl_update_provider_fields() {
  local provider="$1" new_url="$2" new_token="$3"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
pid = sys.argv[2]
new_url = sys.argv[3]
new_token = sys.argv[4]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
providers = data.get('providers', {})
if pid in providers:
    if new_url:
        providers[pid]['base_url'] = new_url
    if new_token:
        providers[pid]['api_key'] = new_token
    with open(path, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')
" "$cfg" "$provider" "$new_url" "$new_token"
}

cl_remove_provider() {
  local provider="$1"
  local cfg
  cfg="$(_cl_cfg)"
  python3 -c "
import sys, json
path = sys.argv[1]
pid = sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
providers = data.get('providers', {})
providers.pop(pid, None)
if data.get('active_provider') == pid:
    del data['active_provider']
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$cfg" "$provider"
}
