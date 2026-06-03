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

## Quick start

```bash
make init
# Edit .env if you need a different MODEL_ID, HF_TOKEN, or ports.
make up
make health
```

Open the NeMo Guardrails test UI at <http://localhost:8001/>.

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
make ps       # show containers
make logs     # follow logs
make down     # stop the stack
make test     # validate local YAML syntax
```

## Notes

- The raw vLLM endpoint remains available on `VLLM_PORT` for debugging. Route
  applications through `GUARDRAILS_PORT` when you want the NemoClaw guardrails.
- The first start can take several minutes while vLLM downloads model weights.
- For multi-GPU hosts, increase `TENSOR_PARALLEL_SIZE` to match the number of GPUs
  you want vLLM to shard across.
