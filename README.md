# Local NVIDIA NemoClaw

This repository contains a local, single-node NVIDIA GPU deployment for a
NemoClaw-style assistant: vLLM serves a Nemotron-family model through an
OpenAI-compatible API, and NVIDIA NeMo Guardrails proxies chat completions with
input and output safety rails.

## What runs locally

- **vLLM** on port `8000` for GPU inference.
- **NeMo Guardrails** on port `8001` for OpenAI-compatible guarded chat.
- A default `nemoclaw` guardrails configuration mounted from `configs/nemoclaw`.

## Prerequisites

1. Linux host with a CUDA-capable NVIDIA GPU and current NVIDIA driver.
2. Docker Engine with the NVIDIA Container Toolkit configured.
3. Docker Compose v2.
4. Enough VRAM/disk for the model selected in `.env`.
5. Optional `HF_TOKEN` if the selected Hugging Face model is gated.

Verify GPU container access before starting the stack:

```bash
docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu22.04 nvidia-smi
```


## 從 Terminal 安裝 Docker CLI 並建起服務（Ubuntu/Debian）

如果 `docker --version` 或 `docker compose version` 顯示 `command not found`，先在主機 terminal 執行下列步驟。這個專案也提供一支 Ubuntu/Debian 用的安裝腳本，會安裝 Docker Engine、Docker CLI、Docker Compose v2 plugin，並在偵測到 NVIDIA GPU 時安裝 NVIDIA Container Toolkit。

```bash
cd /workspace/openclaw
./scripts/install-docker-ubuntu.sh
# 或：make install-docker
```

安裝後若腳本提示已把使用者加入 `docker` group，請重新登入 terminal，或立即執行：

```bash
newgrp docker
```

接著確認 Docker CLI、Compose v2 與 GPU passthrough 都可用：

```bash
docker --version
docker compose version
docker run --rm hello-world
docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu22.04 nvidia-smi
```

最後從 repo root 建立 `.env` 並啟動 NemoClaw：

```bash
make init
# 如果要改模型、HF_TOKEN、port，先編輯 .env
make deploy
make health
```

若主機 shell 沒有 `nvidia-smi`，但你已確認 Docker GPU passthrough 可用，可以只略過 host GPU preflight：

```bash
SKIP_GPU_CHECK=1 make deploy
```

> 注意：`./scripts/install-docker-ubuntu.sh` 需要 `sudo` 權限，且只支援 Ubuntu/Debian。其他 Linux 發行版請依照 Docker 官方文件安裝 Docker Engine、Docker Compose v2 plugin，以及 NVIDIA Container Toolkit。

## Quick start

```bash
make init
# Edit .env if you need a different MODEL_ID, HF_TOKEN, or ports.
make deploy
```

The deploy target performs Docker/NVIDIA preflight checks, starts the stack, and waits for the guarded endpoint to become healthy. Open the NeMo Guardrails test UI at <http://localhost:8001/>.


## Deploy now

Run the full local deployment from the repository root:

```bash
make deploy
```

If you are deploying on a remote machine where `nvidia-smi` is not available on
the host shell but Docker GPU passthrough is already configured, bypass only the
host preflight with:

```bash
SKIP_GPU_CHECK=1 make deploy
```

If model download or warm-up takes longer than the default 15 minutes, increase
the wait timeout:

```bash
TIMEOUT_SECONDS=1800 make deploy
```


## Compose config validation without Docker CLI

`docker compose config` is still the canonical validation when Docker CLI is installed. In restricted development containers where `docker` is unavailable, run this repo-local fallback instead:

```bash
make compose-config
```

The fallback renders `.env`/`.env.example` variable defaults, parses `docker-compose.yml`, and checks that the required `vllm` and `guardrails` services exist. `make test` runs this validation automatically before checking Guardrails YAML syntax.



`make health` is developer-friendly by default: if live services are not running, it falls back to offline compose/Guardrails config checks and exits successfully. Use strict mode when you need a live endpoint failure to fail the command:

```bash
OFFLINE_OK=0 make health
```

`make chat` behaves the same way: it sends a live guarded chat request when Guardrails is reachable, and otherwise prints an offline OpenAI-compatible demo response so the command remains runnable in restricted sandboxes.

## Demo

Run a demo from the repository root:

```bash
make demo
```

When the Docker stack is already running, this sends a live guarded chat request to NeMo Guardrails. In restricted environments where Docker or the services are unavailable, the demo still validates the compose/Guardrails configuration and prints an offline example request plus the expected guardrails flow.

## Send a guarded chat request

```bash
curl -sS http://localhost:8001/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-nemotron",
    "messages": [{"role": "user", "content": "用繁體中文簡短介紹你自己。"}],
    "guardrails": {"config_id": "nemoclaw"}
  }' | python3 -m json.tool
```

You can also run:

```bash
make chat
```

## Configuration

Copy `.env.example` to `.env` and change these common settings:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MODEL_ID` | `nvidia/Llama-3.1-Nemotron-Nano-8B-v1` | Hugging Face model loaded by vLLM. |
| `SERVED_MODEL_NAME` | `local-nemotron` | Model name exposed by vLLM and referenced by NeMo Guardrails. |
| `HF_TOKEN` | empty | Token for gated models. |
| `VLLM_PORT` | `8000` | Host port for raw vLLM. |
| `GUARDRAILS_PORT` | `8001` | Host port for NeMo Guardrails. |
| `GPU_MEMORY_UTILIZATION` | `0.90` | Fraction of GPU memory vLLM may reserve. |
| `MAX_MODEL_LEN` | `8192` | Maximum context length requested from vLLM. |

If you change `SERVED_MODEL_NAME`, update `configs/nemoclaw/config.yml` so the
`models[0].model` value matches.

## Safety rails

The default `nemoclaw` configuration enables:

- `self check input` to block unsafe, secret-seeking, or jailbreak-style prompts
  before inference.
- `self check output` to block unsafe or secret-leaking assistant responses before
  returning them to the caller.

The prompts are intentionally conservative and live in
`configs/nemoclaw/config.yml`, so you can tune policy language without rebuilding
containers.

## Operations

```bash
make install-docker # install Docker CLI/Compose and NVIDIA Container Toolkit on Ubuntu/Debian
make deploy   # preflight, start, and wait for the local NemoClaw stack
make ps       # show containers
make logs     # follow logs
make health   # live health if available; otherwise offline config health
make chat     # live guarded chat if available; otherwise offline demo response
make demo     # run live guarded chat when available, otherwise offline demo
make compose-config # validate/render compose config even when Docker CLI is unavailable
make down     # stop the stack
make test     # validate compose and local YAML syntax
```

## Notes

- The raw vLLM endpoint remains available on `VLLM_PORT` for debugging. Route
  applications through `GUARDRAILS_PORT` when you want the NemoClaw guardrails.
- The first start can take several minutes while vLLM downloads model weights.
- For multi-GPU hosts, increase `TENSOR_PARALLEL_SIZE` to match the number of GPUs
  you want vLLM to shard across.
