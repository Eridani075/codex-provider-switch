#!/usr/bin/env bash
# config.sh - Codex config.toml reading/writing with staging
# Source this file, don't run directly.

CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"

# Backend detection: "codex" or "claude"
BACKEND="${BACKEND:-}"
_detect_backend() {
  local has_codex=0 has_claude=0
  [ -f "$CODEX_CONFIG" ] && has_codex=1
  [ -f "$CLAUDE_CONFIG" ] && has_claude=1
  if [ -n "$BACKEND" ]; then
    return
  elif [ "$has_codex" -eq 1 ] && [ "$has_claude" -eq 1 ]; then
    BACKEND="codex"
  elif [ "$has_codex" -eq 1 ]; then
    BACKEND="codex"
  elif [ "$has_claude" -eq 1 ]; then
    BACKEND="claude"
  fi
}
_detect_backend

# ── staging ─────────────────────────────────────────────

# All co_* read/write functions use CODEX_STAGED instead of CODEX_CONFIG.
# On init: copy real config → temp, point CODEX_STAGED there.
# On apply: backup real, move staged → real.
# On discard: delete staged.

CODEX_STAGED=""

init_staging_codex() {
  [ ! -f "$CODEX_CONFIG" ] && return
  CODEX_STAGED=$(mktemp)
  cp "$CODEX_CONFIG" "$CODEX_STAGED"
}

has_codex_staging() {
  [ -n "$CODEX_STAGED" ] && [ -f "$CODEX_STAGED" ]
}

apply_staging_codex() {
  if ! has_codex_staging; then
    echo -e "${YELLOW}Codex: 没有待写入的更改${NC}"
    return
  fi
  if [ -f "$CODEX_CONFIG" ]; then
    cp "$CODEX_CONFIG" "${CODEX_CONFIG}.bak"
  fi
  cp "$CODEX_STAGED" "$CODEX_CONFIG"
  rm -f "$CODEX_STAGED"
  CODEX_STAGED=""
  echo -e "${GREEN}Codex 配置已写入 (${CODEX_CONFIG}.bak 已备份)${NC}"
}

discard_staging_codex() {
  if has_codex_staging; then
    rm -f "$CODEX_STAGED"
    CODEX_STAGED=""
    echo -e "${YELLOW}Codex 更改已丢弃${NC}"
  fi
}

# Backend-aware wrappers
get_current_provider() {
  if [ "$BACKEND" = "claude" ]; then
    cl_get_current_provider
  else
    co_get_current_provider
  fi
}
get_current_model() {
  if [ "$BACKEND" = "claude" ]; then
    cl_get_current_model
  else
    co_get_current_model
  fi
}
set_current_model() {
  if [ "$BACKEND" = "claude" ]; then
    cl_set_current_model "$1"
  else
    co_set_current_model "$1"
  fi
}
set_current_provider() {
  if [ "$BACKEND" = "claude" ]; then
    cl_set_current_provider "$1"
  else
    co_set_current_provider "$1"
  fi
}
parse_providers() {
  if [ "$BACKEND" = "claude" ]; then
    cl_parse_providers
  else
    co_parse_providers
  fi
}
append_provider() {
  if [ "$BACKEND" = "claude" ]; then
    cl_append_provider "$@"
  else
    co_append_provider "$@"
  fi
}
update_provider_fields() {
  if [ "$BACKEND" = "claude" ]; then
    cl_update_provider_fields "$@"
  else
    co_update_provider_fields "$@"
  fi
}
remove_provider() {
  if [ "$BACKEND" = "claude" ]; then
    cl_remove_provider "$1"
  else
    co_remove_provider "$1"
  fi
}

# Model tier support (Claude Code has opus/sonnet/haiku)
get_models() {
  if [ "$BACKEND" = "claude" ]; then
    cl_get_models
  else
    echo ""
  fi
}
set_model_id() {
  if [ "$BACKEND" = "claude" ]; then
    cl_set_model_id "$1" "$2"
  fi
}

# Context size
get_context_display() {
  if [ "$BACKEND" = "claude" ]; then
    cl_get_context_1m
  else
    local t
    t=$(co_get_max_tokens)
    if [ -n "$t" ]; then
      if [ "$t" -ge 1048576 ] 2>/dev/null; then
        echo "$((t / 1048576))M ($t)"
      elif [ "$t" -ge 1024 ] 2>/dev/null; then
        echo "$((t / 1024))K ($t)"
      else
        echo "$t"
      fi
    fi
  fi
}

# ── Codex TOML operations (all use CODEX_STAGED) ────────

_co_cfg() {
  if [ -n "$CODEX_STAGED" ] && [ -f "$CODEX_STAGED" ]; then
    echo "$CODEX_STAGED"
  else
    echo "$CODEX_CONFIG"
  fi
}

co_get_current_provider() {
  sed -n 's/^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$(_co_cfg)" 2>/dev/null || echo "openai (默认)"
}

co_get_current_model() {
  sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$(_co_cfg)" 2>/dev/null || echo "(未设置)"
}

co_set_current_model() {
  local model="$1" cfg
  cfg="$(_co_cfg)"
  local tmp
  tmp=$(mktemp)
  if grep -q '^[[:space:]]*model[[:space:]]*=' "$cfg"; then
    sed "s|^\([[:space:]]*model[[:space:]]*=[[:space:]]*\)\"[^\"]*\"|\1\"${model}\"|" "$cfg" > "$tmp"
  else
    printf '%s\n' "model = \"${model}\"" | cat - "$cfg" > "$tmp"
  fi
  mv "$tmp" "$cfg"
}

# Parse all [model_providers.X] sections from config.
# Output per line: key|name|base_url|wire_api|token|model
co_parse_providers() {
  local cfg
  cfg="$(_co_cfg)"
  local in_section=""
  local name="" base_url="" wire_api="" token="" model=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^\[model_providers\.([^]]+)\] ]]; then
      if [[ -n "$in_section" && -n "$base_url" ]]; then
        echo "${in_section}|${name:-$in_section}|${base_url}|${wire_api:-responses}|${token:-}|${model:-}"
      fi
      in_section="${BASH_REMATCH[1]}"
      name="" base_url="" wire_api="" token="" model=""
    elif [[ "$line" =~ ^\[ && -n "$in_section" ]]; then
      if [[ -n "$base_url" ]]; then
        echo "${in_section}|${name:-$in_section}|${base_url}|${wire_api:-responses}|${token:-}|${model:-}"
      fi
      in_section=""
    elif [[ -n "$in_section" ]]; then
      [[ "$line" =~ ^name\ *=\ *\"([^\"]+)\" ]] && name="${BASH_REMATCH[1]}"
      [[ "$line" =~ ^base_url\ *=\ *\"([^\"]+)\" ]] && base_url="${BASH_REMATCH[1]}"
      [[ "$line" =~ ^wire_api\ *=\ *\"([^\"]+)\" ]] && wire_api="${BASH_REMATCH[1]}"
      [[ "$line" =~ ^experimental_bearer_token\ *=\ *\"([^\"]+)\" ]] && token="${BASH_REMATCH[1]}"
      [[ "$line" =~ ^model\ *=\ *\"([^\"]+)\" ]] && model="${BASH_REMATCH[1]}"
    fi
  done < "$cfg"

  if [[ -n "$in_section" && -n "$base_url" ]]; then
    echo "${in_section}|${name:-$in_section}|${base_url}|${wire_api:-responses}|${token:-}|${model:-}"
  fi
}

# Set model_provider in config. Adds the line if missing.
co_set_current_provider() {
  local provider="$1" cfg
  cfg="$(_co_cfg)"
  local tmp
  tmp=$(mktemp)
  if grep -q '^[[:space:]]*model_provider[[:space:]]*=' "$cfg"; then
    sed "s|^\([[:space:]]*model_provider[[:space:]]*=[[:space:]]*\)\"[^\"]*\"|\1\"${provider}\"|" "$cfg" > "$tmp"
  else
    printf '%s\n' "model_provider = \"${provider}\"" | cat - "$cfg" > "$tmp"
  fi
  mv "$tmp" "$cfg"
}

# Append a new provider section to config.
co_append_provider() {
  local id="$1" name="$2" url="$3" key="$4" cfg
  cfg="$(_co_cfg)"
  cat >> "$cfg" << EOF

[model_providers.${id}]
name = "${name}"
base_url = "${url}"
wire_api = "responses"
requires_openai_auth = true
experimental_bearer_token = "${key}"
EOF
}

# Update fields of an existing provider section in config.
co_update_provider_fields() {
  local provider="$1" new_url="$2" new_token="$3" cfg
  cfg="$(_co_cfg)"
  local in_section=0
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line; do
    if [ "$line" = "[model_providers.${provider}]" ]; then
      in_section=1
    elif echo "$line" | grep -q '^\[' && [ "$in_section" = 1 ]; then
      in_section=0
    fi
    if [ "$in_section" = 1 ]; then
      echo "$line" | grep -q '^base_url' && line="base_url = \"${new_url}\""
      echo "$line" | grep -q '^experimental_bearer_token' && line="experimental_bearer_token = \"${new_token}\""
    fi
    echo "$line"
  done < "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

co_get_max_tokens() {
  sed -n 's/^[[:space:]]*max_tokens[[:space:]]*=[[:space:]]*\([0-9]*\)/\1/p' "$(_co_cfg)" 2>/dev/null
}

co_set_max_tokens() {
  local tokens="$1" cfg
  cfg="$(_co_cfg)"
  local tmp
  tmp=$(mktemp)
  if grep -q '^[[:space:]]*max_tokens[[:space:]]*=' "$cfg"; then
    sed "s|^\([[:space:]]*max_tokens[[:space:]]*=[[:space:]]*\)[0-9]*|\1${tokens}|" "$cfg" > "$tmp"
  else
    cat "$cfg" > "$tmp"
    printf '%s\n' "max_tokens = ${tokens}" >> "$tmp"
  fi
  mv "$tmp" "$cfg"
}

# Remove a provider section from config.
co_remove_provider() {
  local provider="$1" cfg
  cfg="$(_co_cfg)"
  local tmp
  tmp=$(mktemp)
  local skip=0
  while IFS= read -r line; do
    if [[ "$line" == "[model_providers.${provider}]" ]]; then
      skip=1
      continue
    fi
    [[ "$line" =~ ^\[ && "$skip" == 1 ]] && skip=0
    [[ "$skip" == 1 ]] && continue
    echo "$line"
  done < "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}
