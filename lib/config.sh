#!/usr/bin/env bash
# config.sh - Codex config.toml reading/writing
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

co_get_current_provider() {
  sed -n 's/^[[:space:]]*model_provider[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$CODEX_CONFIG" 2>/dev/null || echo "openai (默认)"
}

co_get_current_model() {
  sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$CODEX_CONFIG" 2>/dev/null || echo "(未设置)"
}

co_set_current_model() {
  local model="$1"
  local tmp
  tmp=$(mktemp)
  if grep -q '^[[:space:]]*model[[:space:]]*=' "$CODEX_CONFIG"; then
    sed "s|^\([[:space:]]*model[[:space:]]*=[[:space:]]*\)\"[^\"]*\"|\1\"${model}\"|" "$CODEX_CONFIG" > "$tmp"
  else
    printf '%s\n' "model = \"${model}\"" | cat - "$CODEX_CONFIG" > "$tmp"
  fi
  mv "$tmp" "$CODEX_CONFIG"
}

# Parse all [model_providers.X] sections from config.
# Output per line: key|name|base_url|wire_api|token|model
co_parse_providers() {
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
  done < "$CODEX_CONFIG"

  if [[ -n "$in_section" && -n "$base_url" ]]; then
    echo "${in_section}|${name:-$in_section}|${base_url}|${wire_api:-responses}|${token:-}|${model:-}"
  fi
}

# Set model_provider in config. Adds the line if missing.
co_set_current_provider() {
  local provider="$1"
  local tmp
  tmp=$(mktemp)
  if grep -q '^[[:space:]]*model_provider[[:space:]]*=' "$CODEX_CONFIG"; then
    sed "s|^\([[:space:]]*model_provider[[:space:]]*=[[:space:]]*\)\"[^\"]*\"|\1\"${provider}\"|" "$CODEX_CONFIG" > "$tmp"
  else
    printf '%s\n' "model_provider = \"${provider}\"" | cat - "$CODEX_CONFIG" > "$tmp"
  fi
  mv "$tmp" "$CODEX_CONFIG"
}

# Append a new provider section to config.
co_append_provider() {
  local id="$1" name="$2" url="$3" key="$4"
  cat >> "$CODEX_CONFIG" << EOF

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
  local provider="$1" new_url="$2" new_token="$3"
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
  done < "$CODEX_CONFIG" > "$tmp"
  mv "$tmp" "$CODEX_CONFIG"
}

# Remove a provider section from config.
co_remove_provider() {
  local provider="$1"
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
  done < "$CODEX_CONFIG" > "$tmp"
  mv "$tmp" "$CODEX_CONFIG"
}
