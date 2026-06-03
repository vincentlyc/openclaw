#!/usr/bin/env bash
set -euo pipefail

WAIT=0
OFFLINE_OK=${OFFLINE_OK:-0}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-900}
SLEEP_SECONDS=${SLEEP_SECONDS:-10}
CURL_TIMEOUT_SECONDS=${CURL_TIMEOUT_SECONDS:-5}
COMPOSE_OUTPUT=${COMPOSE_OUTPUT:-/tmp/openclaw-compose.yml}

while [ $# -gt 0 ]; do
  case "$1" in
    --wait)
      WAIT=1
      ;;
    --offline-ok)
      OFFLINE_OK=1
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

VLLM_URL="http://localhost:${VLLM_PORT:-8000}/v1/models"
GUARDRAILS_URL="http://localhost:${GUARDRAILS_PORT:-8001}/v1/rails/configs"

check_url() {
  local name=$1
  local url=$2
  local response

  printf 'Checking %s at %s\n' "$name" "$url"
  if ! response=$(curl -fsS --max-time "$CURL_TIMEOUT_SECONDS" "$url" 2>/dev/null); then
    printf '%s is not reachable at %s.\n' "$name" "$url" >&2
    return 1
  fi

  if ! printf '%s' "$response" | python3 -m json.tool >/dev/null; then
    printf '%s returned a non-JSON response.\n' "$name" >&2
    return 1
  fi

  printf '%s is reachable.\n' "$name"
}

run_offline_health() {
  printf 'Live services are unavailable; running offline configuration health checks instead.\n'
  OUTPUT="$COMPOSE_OUTPUT" ./scripts/compose-config.sh >/dev/null
  printf 'Rendered compose config: %s\n' "$COMPOSE_OUTPUT"
  ruby -e 'require "yaml"; Dir["configs/*/config.yml"].each { |path| YAML.load_file(path); puts "validated #{path}" }'
  printf 'Offline health checks passed. Run `make deploy` for live vLLM/Guardrails health.\n'
}

if [ "$WAIT" = "0" ]; then
  if check_url 'vLLM' "$VLLM_URL" && check_url 'NeMo Guardrails' "$GUARDRAILS_URL"; then
    exit 0
  fi

  if [ "$OFFLINE_OK" = "1" ]; then
    run_offline_health
    exit 0
  fi

  exit 1
fi

start=$(date +%s)
while true; do
  if check_url 'vLLM' "$VLLM_URL" && check_url 'NeMo Guardrails' "$GUARDRAILS_URL"; then
    exit 0
  fi

  now=$(date +%s)
  if [ $((now - start)) -ge "$TIMEOUT_SECONDS" ]; then
    printf 'Timed out after %s seconds waiting for local NemoClaw services.\n' "$TIMEOUT_SECONDS" >&2
    exit 1
  fi

  printf 'Services are not ready yet; retrying in %s seconds.\n' "$SLEEP_SECONDS"
  sleep "$SLEEP_SECONDS"
done
