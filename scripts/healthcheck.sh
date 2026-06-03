#!/usr/bin/env bash
set -euo pipefail

VLLM_URL="http://localhost:${VLLM_PORT:-8000}/v1/models"
GUARDRAILS_URL="http://localhost:${GUARDRAILS_PORT:-8001}/v1/rails/configs"

printf 'Checking vLLM at %s\n' "$VLLM_URL"
curl -fsS "$VLLM_URL" | python3 -m json.tool >/dev/null
printf 'vLLM is reachable.\n'

printf 'Checking NeMo Guardrails at %s\n' "$GUARDRAILS_URL"
curl -fsS "$GUARDRAILS_URL" | python3 -m json.tool >/dev/null
printf 'NeMo Guardrails is reachable.\n'
