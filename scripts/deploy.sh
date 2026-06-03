#!/usr/bin/env bash
set -euo pipefail

COMPOSE_BIN=${COMPOSE:-docker compose}
ENV_FILE=${ENV_FILE:-.env}
SKIP_GPU_CHECK=${SKIP_GPU_CHECK:-0}
SKIP_HEALTH=${SKIP_HEALTH:-0}

log() {
  printf '[nemoclaw] %s\n' "$*"
}

fail() {
  printf '[nemoclaw] ERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_compose() {
  # shellcheck disable=SC2086 # COMPOSE_BIN intentionally supports "docker compose".
  $COMPOSE_BIN --env-file "$ENV_FILE" "$@"
}

if ! command_exists docker; then
  fail 'Docker CLI is required. Install Docker Engine and Docker Compose v2 first.'
fi

if ! docker compose version >/dev/null 2>&1; then
  fail 'Docker Compose v2 is required. Verify `docker compose version` works.'
fi

if [ ! -f "$ENV_FILE" ]; then
  log "Creating $ENV_FILE from .env.example"
  cp .env.example "$ENV_FILE"
fi

if [ "$SKIP_GPU_CHECK" != "1" ]; then
  if ! command_exists nvidia-smi; then
    fail 'nvidia-smi is required for the default GPU preflight. Set SKIP_GPU_CHECK=1 to bypass.'
  fi

  log 'Checking host NVIDIA GPU visibility'
  nvidia-smi >/dev/null

  log 'Checking NVIDIA Container Toolkit GPU passthrough'
  docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu22.04 nvidia-smi >/dev/null
fi

log 'Validating compose configuration'
run_compose config >/dev/null

log 'Building and starting local NemoClaw services'
run_compose up -d --build

if [ "$SKIP_HEALTH" != "1" ]; then
  log 'Waiting for vLLM and NeMo Guardrails health checks'
  ./scripts/healthcheck.sh --wait
fi

log 'Deployment complete'
log "Guarded chat endpoint: http://localhost:${GUARDRAILS_PORT:-8001}/v1/chat/completions"
log "Guardrails UI: http://localhost:${GUARDRAILS_PORT:-8001}/"
