#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGROK_ENV="$ROOT_DIR/.env.ngrok"
ROOT_ENV="$ROOT_DIR/.env"
FRONT_ENV="$ROOT_DIR/frontend/.env"
INFRA_ENV="$ROOT_DIR/infra/.env"

trim() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  echo "$value"
}

get_var() {
  local file="$1"
  local key="$2"
  local line=""
  if [[ -f "$file" ]]; then
    line=$(grep -m1 -E "^${key}=" "$file" 2>/dev/null || true)
  fi
  if [[ -z "$line" ]]; then
    echo ""
    return
  fi
  trim "${line#*=}"
}

set_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp="${file}.tmp"
  local found=0

  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "${key}="* ]]; then
        echo "${key}=${value}"
        found=1
      else
        echo "$line"
      fi
    done < "$file" > "$tmp"
    if [[ $found -eq 0 ]]; then
      echo "${key}=${value}" >> "$tmp"
    fi
    mv "$tmp" "$file"
  else
    mkdir -p "$(dirname "$file")"
    echo "${key}=${value}" > "$file"
  fi
}

if [[ ! -f "$NGROK_ENV" ]]; then
  cat <<'TEMPLATE' > "$NGROK_ENV"
# Single URL for both WebApp and API:
NGROK_URL=

# Optional overrides if you use separate tunnels:
# NGROK_WEBAPP_URL=
# NGROK_API_URL=
TEMPLATE
  echo "Created .env.ngrok. Set NGROK_URL (or the overrides) and re-run."
  exit 1
fi

ngrok_url=$(get_var "$NGROK_ENV" "NGROK_URL")
webapp_url=$(get_var "$NGROK_ENV" "NGROK_WEBAPP_URL")
api_url=$(get_var "$NGROK_ENV" "NGROK_API_URL")

if [[ -z "$webapp_url" ]]; then
  webapp_url="$ngrok_url"
fi
if [[ -z "$api_url" ]]; then
  api_url="$ngrok_url"
fi

webapp_url="${webapp_url%/}"
api_url="${api_url%/}"

if [[ -z "$webapp_url" || -z "$api_url" ]]; then
  echo "NGROK_URL is required (or set NGROK_WEBAPP_URL and NGROK_API_URL)."
  exit 1
fi

set_kv "$ROOT_ENV" "BASE_URL" "$webapp_url"
set_kv "$ROOT_ENV" "VITE_API_URL" "$api_url"
set_kv "$FRONT_ENV" "VITE_API_URL" "$api_url"

if [[ -f "$INFRA_ENV" ]]; then
  set_kv "$INFRA_ENV" "BASE_URL" "$webapp_url"
  set_kv "$INFRA_ENV" "VITE_API_URL" "$api_url"
fi

bot_token=$(get_var "$ROOT_ENV" "TELEGRAM_BOT_TOKEN")
if [[ -n "$bot_token" ]]; then
  webhook_url="${api_url}/telegram/webhook"
  curl -sS -X POST "https://api.telegram.org/bot${bot_token}/setWebhook" \
    -d "url=${webhook_url}" >/dev/null
  echo "Webhook set to ${webhook_url}"
else
  echo "TELEGRAM_BOT_TOKEN missing in .env; skipped webhook update."
fi

echo "Updated BASE_URL and VITE_API_URL in .env and frontend/.env"
