# Windows WSL2 Docker Engine Deployment

## Overview

This guide explains how to run OpenClaw on Windows using WSL2 Ubuntu with Docker Engine installed directly inside WSL, without Docker Desktop.

## Target Architecture

```text
Windows 11
→ WSL2 Ubuntu
→ Docker Engine inside WSL
→ NVIDIA Container Toolkit
→ vLLM + NeMo Guardrails
```

## When to Use This

Use this setup when Docker Desktop is unavailable, unstable, or stuck at:

```text
Starting the Docker Engine
```

## Prerequisites

* Windows 11
* WSL2 Ubuntu 24.04
* NVIDIA Windows driver with WSL CUDA support
* NVIDIA GPU
* CPU virtualization enabled in BIOS / UEFI
* WSL2 working correctly

## Verify WSL2

From PowerShell:

```powershell
wsl -l -v
wsl -d Ubuntu-24.04
```

Inside Ubuntu:

```bash
uname -a
nvidia-smi
```

Expected WSL kernel should include:

```text
microsoft-standard-WSL2
```

## Install Docker Engine Inside WSL

Inside Ubuntu:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release git make ruby python3
```

Add Docker repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

```bash
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list
```

Install Docker:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Start Docker:

```bash
sudo service docker start
```

Allow current user to run Docker:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Test Docker:

```bash
docker run --rm hello-world
```

## Install NVIDIA Container Toolkit

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
```

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

```bash
sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo service docker restart
```

Test GPU container:

```bash
docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu22.04 nvidia-smi
```

## Configure OpenClaw

From the repo root:

```bash
make init
```

For RTX 3090 or similar consumer GPUs, use conservative settings first:

```bash
sed -i 's/GPU_MEMORY_UTILIZATION=.*/GPU_MEMORY_UTILIZATION=0.75/' .env
sed -i 's/MAX_MODEL_LEN=.*/MAX_MODEL_LEN=2048/' .env
```

Optional: set Hugging Face token in `.env`:

```env
HF_TOKEN=your_huggingface_token
```

## Run vLLM First

```bash
sudo service docker start
docker compose --env-file .env up -d vllm
docker logs -f nemoclaw-vllm
```

Exit log follow mode:

```text
Ctrl + C
```

Verify vLLM:

```bash
curl -sS http://localhost:8000/v1/models | python3 -m json.tool
```

Expected result: JSON response with available model information.

## Run Guardrails

```bash
docker compose --env-file .env up -d guardrails
docker compose --env-file .env ps
```

Verify Guardrails root endpoint:

```bash
curl -sS http://localhost:8001/
```

Expected result:

```json
{"status":"ok"}
```

## Test Guarded Chat

```bash
curl -sS http://localhost:8001/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-nemotron",
    "messages": [
      {
        "role": "user",
        "content": "用繁體中文簡短介紹你自己。"
      }
    ],
    "guardrails": {
      "config_id": "nemoclaw"
    }
  }' | python3 -m json.tool
```

## Daily Commands

Start:

```bash
cd ~/openclaw
sudo service docker start
docker compose --env-file .env up -d
docker compose --env-file .env ps
```

Stop:

```bash
cd ~/openclaw
docker compose --env-file .env down
```

Logs:

```bash
docker logs --tail=100 nemoclaw-vllm
docker logs --tail=100 nemoclaw-guardrails
```

Follow logs:

```bash
docker logs -f nemoclaw-vllm
```

## Notes

* Do not run Docker Desktop and WSL Docker Engine at the same time unless you know what you are doing.
* Keep the repo under the WSL Linux filesystem, such as `~/openclaw`, not under `/mnt/c`.
* `.env` should not be committed.
* Guardrails root returning `{"status":"ok"}` only means the server is alive. Use `/v1/chat/completions` to test chat behavior.
