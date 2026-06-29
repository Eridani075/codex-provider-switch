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
# Try to parse as JSON (for dicts/lists), otherwise treat as string
try:
    data[key] = json.loads(val)
except (json.JSONDecodeError, ValueError):
    data[key] = val
with open(path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$CLAUDE_CONFIG" "$key" "$val"
}

cl_get_current_model() {
  local model
  model=$(_cl_json_get "model")
  [ -n "$model" ] && echo "$model" || echo "(未设置)"
}

cl_set_current_model() {
  local model="$1"
  _cl_json_set "model" "$model"
}

# Parse providers from settings.json providers field.
# Output per line: key|name|base_url||token|
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
