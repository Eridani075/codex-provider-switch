#!/usr/bin/env bash
# claude_config.sh - Claude Code settings.json reading/writing
# Source this file, don't run directly.

CLAUDE_CONFIG="${CLAUDE_CONFIG:-$HOME/.claude/settings.json}"

_cl_json_get() {
  local key="$1"
  python3 -c "
import sys, json
try:
    data = json.load(open(sys.argv[1]))
    val = data.get(sys.argv[2], '')
    print(val if isinstance(val, str) else json.dumps(val) if val else '')
except Exception:
    print('')
" "$CLAUDE_CONFIG" "$key" 2>/dev/null
}

_cl_json_set() {
  local key="$1" val="$2"
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
" "$CLAUDE_CONFIG" "$key" "$val"
}

# ── 3-model support (opus/sonnet/haiku) ──────────────────

CLAUDE_MODEL_TIERS="opus sonnet haiku"

cl_get_models() {
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
" "$CLAUDE_CONFIG" 2>/dev/null
}

cl_get_current_model() {
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
" "$CLAUDE_CONFIG" 2>/dev/null
}

cl_set_current_model() {
  local tier="$1"
  # If it's a known tier, set model to that tier
  # Otherwise, set as raw model ID
  local is_tier=0
  for t in $CLAUDE_MODEL_TIERS; do
    [ "$tier" = "$t" ] && is_tier=1 && break
  done
  if [ "$is_tier" -eq 1 ]; then
    _cl_json_set "model" "$tier"
  else
    _cl_json_set "model" "$tier"
  fi
}

cl_set_model_id() {
  local tier="$1" model_id="$2"
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
" "$CLAUDE_CONFIG" "$tier" "$model_id"
}

# ── context size ─────────────────────────────────────────

cl_get_max_tokens() {
  python3 -c "
import sys, json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    val = data.get('max_tokens', '')
    print(val if val else '')
except Exception:
    print('')
" "$CLAUDE_CONFIG" 2>/dev/null
}

cl_set_max_tokens() {
  local tokens="$1"
  if [ -n "$tokens" ]; then
    _cl_json_set "max_tokens" "$tokens"
  fi
}

# ── providers ────────────────────────────────────────────

cl_parse_providers() {
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
" "$CLAUDE_CONFIG" 2>/dev/null
}

cl_get_current_provider() {
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
" "$CLAUDE_CONFIG" 2>/dev/null
}

cl_set_current_provider() {
  local provider="$1"
  _cl_json_set "active_provider" "$provider"
}

cl_append_provider() {
  local id="$1" name="$2" url="$3" key="$4"
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
" "$CLAUDE_CONFIG" "$id" "$name" "$url" "$key"
}

cl_update_provider_fields() {
  local provider="$1" new_url="$2" new_token="$3"
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
" "$CLAUDE_CONFIG" "$provider" "$new_url" "$new_token"
}

cl_remove_provider() {
  local provider="$1"
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
" "$CLAUDE_CONFIG" "$provider"
}
