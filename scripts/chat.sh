#!/usr/bin/env bash
set -euo pipefail

GUARDRAILS_PORT=${GUARDRAILS_PORT:-8001}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME:-local-nemotron}
GUARDRAILS_URL="http://localhost:${GUARDRAILS_PORT}/v1/rails/configs"
CHAT_URL="http://localhost:${GUARDRAILS_PORT}/v1/chat/completions"
PROMPT=${PROMPT:-用繁體中文簡短介紹你自己。}
CURL_TIMEOUT_SECONDS=${CURL_TIMEOUT_SECONDS:-5}

payload=$(SERVED_MODEL_NAME="$SERVED_MODEL_NAME" PROMPT="$PROMPT" python3 - <<PY
import json
import os

print(json.dumps({
    "model": os.environ.get("SERVED_MODEL_NAME", "local-nemotron"),
    "messages": [{"role": "user", "content": os.environ.get("PROMPT", "用繁體中文簡短介紹你自己。")}],
    "guardrails": {"config_id": "nemoclaw"},
}, ensure_ascii=False))
PY
)

if curl -fsS --max-time "$CURL_TIMEOUT_SECONDS" "$GUARDRAILS_URL" >/dev/null 2>&1; then
  curl -sS --max-time "$CURL_TIMEOUT_SECONDS" "$CHAT_URL" \
    -H 'Content-Type: application/json' \
    -d "$payload" | python3 -m json.tool
  exit 0
fi

REQUEST_PAYLOAD="$payload" GUARDRAILS_PORT="$GUARDRAILS_PORT" python3 - <<'PY'
import json
import os

request_payload = json.loads(os.environ["REQUEST_PAYLOAD"])
guardrails_port = os.environ.get("GUARDRAILS_PORT", "8001")
response = {
    "id": "offline-demo-chatcmpl",
    "object": "chat.completion",
    "created": 0,
    "model": request_payload["model"],
    "choices": [
        {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": f"這是 NemoClaw 離線 demo 回覆：目前本機 Guardrails 服務尚未在 localhost:{guardrails_port} 啟動；部署後同一個 make chat 會改送 live guarded chat request。",
            },
            "finish_reason": "stop",
        }
    ],
    "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    "offline_demo": True,
    "request_payload": request_payload,
    "next_step": "Run `make deploy && make chat` on a Docker/NVIDIA host for a live response.",
}
print(json.dumps(response, ensure_ascii=False, indent=2))
PY
