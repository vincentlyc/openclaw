#!/usr/bin/env bash
set -euo pipefail

WAIT=0
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-900}
SLEEP_SECONDS=${SLEEP_SECONDS:-10}

if [ "${1:-}" = "--wait" ]; then
  WAIT=1
fi

VLLM_URL="http://localhost:${VLLM_PORT:-8000}/v1/models"
GUARDRAILS_URL="http://localhost:${GUARDRAILS_PORT:-8001}/v1/rails/configs"

check_url() {
  local name=$1
  local url=$2

  printf 'Checking %s at %s\n' "$name" "$url"
  curl -fsS "$url" | python3 -m json.tool >/dev/null
  printf '%s is reachable.\n' "$name"
}

if [ "$WAIT" = "0" ]; then
  check_url 'vLLM' "$VLLM_URL"
  check_url 'NeMo Guardrails' "$GUARDRAILS_URL"
  exit 0
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
