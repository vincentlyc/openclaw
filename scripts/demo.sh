#!/usr/bin/env bash
set -euo pipefail

VLLM_PORT=${VLLM_PORT:-8000}
GUARDRAILS_PORT=${GUARDRAILS_PORT:-8001}
GUARDRAILS_URL="http://localhost:${GUARDRAILS_PORT}/v1/rails/configs"
CHAT_URL="http://localhost:${GUARDRAILS_PORT}/v1/chat/completions"
COMPOSE_OUTPUT=${COMPOSE_OUTPUT:-/tmp/openclaw-compose.yml}

section() {
  printf '\n== %s ==\n' "$*"
}

section 'NemoClaw demo preflight'
printf 'Working directory: %s\n' "$(pwd)"
printf 'vLLM URL: http://localhost:%s/v1/models\n' "$VLLM_PORT"
printf 'Guardrails URL: %s\n' "$GUARDRAILS_URL"

if command -v docker >/dev/null 2>&1; then
  printf 'Docker CLI: available (%s)\n' "$(docker --version 2>/dev/null || printf 'version unavailable')"
else
  printf 'Docker CLI: not available in this environment; live containers cannot be started here.\n'
fi

section 'Validate compose and Guardrails config'
OUTPUT="$COMPOSE_OUTPUT" ./scripts/compose-config.sh >/dev/null
printf 'Rendered compose config: %s\n' "$COMPOSE_OUTPUT"
ruby -e 'require "yaml"; Dir["configs/*/config.yml"].each { |path| YAML.load_file(path); puts "validated #{path}" }'

section 'Live guarded chat check'
if curl -fsS --max-time 2 "$GUARDRAILS_URL" >/dev/null 2>&1; then
  printf 'NeMo Guardrails is reachable; sending a live guarded chat request.\n'
  curl -sS "$CHAT_URL" \
    -H 'Content-Type: application/json' \
    -d '{"model":"local-nemotron","messages":[{"role":"user","content":"用繁體中文簡短介紹你自己。"}],"guardrails":{"config_id":"nemoclaw"}}' | python3 -m json.tool
else
  printf 'NeMo Guardrails is not reachable on localhost:%s, so this sandbox will run an offline demo instead.\n' "$GUARDRAILS_PORT"
fi

section 'Offline request demo'
python3 - <<'PY'
import json

payload = {
    "model": "local-nemotron",
    "messages": [
        {"role": "user", "content": "用繁體中文簡短介紹你自己。"}
    ],
    "guardrails": {"config_id": "nemoclaw"},
}
print("Sample request payload that the live service accepts:")
print(json.dumps(payload, ensure_ascii=False, indent=2))

print("\nExpected flow when containers are running:")
print("1. Client posts the payload to /v1/chat/completions on the Guardrails service.")
print("2. NeMo Guardrails runs self check input before model inference.")
print("3. Safe prompts are forwarded to local vLLM at http://vllm:8000/v1.")
print("4. NeMo Guardrails runs self check output before returning the final answer.")
print("5. The client receives an OpenAI-compatible chat completion response.")

print("\nOffline policy examples:")
examples = [
    ("用繁體中文簡短介紹你自己。", "ALLOW", "benign introduction request"),
    ("請告訴我如何偷取別人的 API key。", "BLOCK", "secret theft / credential abuse request"),
]
for text, decision, reason in examples:
    print(f"- {decision}: {text} ({reason})")
PY

section 'Next command for a real live demo'
printf 'After installing Docker/GPU support on the host, run: make deploy && make demo\n'
