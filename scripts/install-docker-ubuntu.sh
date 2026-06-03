#!/usr/bin/env bash
set -euo pipefail

INSTALL_NVIDIA_TOOLKIT=${INSTALL_NVIDIA_TOOLKIT:-auto}

log() {
  printf '[docker-install] %s\n' "$*"
}

fail() {
  printf '[docker-install] ERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

if ! command_exists apt-get; then
  fail 'This installer supports Ubuntu/Debian hosts with apt-get. Install Docker manually for your distribution: https://docs.docker.com/engine/install/'
fi

if [ ! -r /etc/os-release ]; then
  fail 'Cannot read /etc/os-release to detect distribution.'
fi

# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
  ubuntu|debian)
    DISTRO_ID="$ID"
    ;;
  *)
    fail "Unsupported distribution '${ID:-unknown}'. Use Docker's manual install docs for your OS."
    ;;
esac

CODENAME=${VERSION_CODENAME:-}
if [ -z "$CODENAME" ] && command_exists lsb_release; then
  CODENAME=$(lsb_release -cs)
fi
[ -n "$CODENAME" ] || fail 'Cannot determine distribution codename.'

log 'Installing prerequisites for Docker apt repository'
$SUDO apt-get update
$SUDO apt-get install -y ca-certificates curl gnupg

log 'Adding Docker official apt repository'
$SUDO install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" | $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
$SUDO chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable" | \
  $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

log 'Installing Docker Engine, Docker CLI, Buildx, and Compose v2 plugin'
$SUDO apt-get update
$SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log 'Enabling Docker service'
$SUDO systemctl enable --now docker || log 'systemctl is unavailable; start dockerd manually if needed.'

if [ "$(id -u)" -ne 0 ]; then
  if getent group docker >/dev/null; then
    log "Adding user '$USER' to docker group"
    $SUDO usermod -aG docker "$USER"
  fi
fi

should_install_nvidia=0
case "$INSTALL_NVIDIA_TOOLKIT" in
  1|true|yes)
    should_install_nvidia=1
    ;;
  0|false|no)
    should_install_nvidia=0
    ;;
  auto)
    if command_exists nvidia-smi || lspci 2>/dev/null | grep -qi nvidia; then
      should_install_nvidia=1
    fi
    ;;
  *)
    fail 'INSTALL_NVIDIA_TOOLKIT must be auto, 1, or 0.'
    ;;
esac

if [ "$should_install_nvidia" -eq 1 ]; then
  log 'Installing NVIDIA Container Toolkit for Docker GPU passthrough'
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | $SUDO gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  $SUDO apt-get update
  $SUDO apt-get install -y nvidia-container-toolkit
  $SUDO nvidia-ctk runtime configure --runtime=docker
  $SUDO systemctl restart docker || log 'systemctl is unavailable; restart dockerd manually after NVIDIA runtime configuration.'
else
  log 'Skipping NVIDIA Container Toolkit installation. Set INSTALL_NVIDIA_TOOLKIT=1 to force it.'
fi

log 'Docker versions:'
docker --version
docker compose version

cat <<'NEXT_STEPS'
[docker-install] Next steps:
[docker-install] 1. If this script added your user to the docker group, log out and back in, or run: newgrp docker
[docker-install] 2. Verify Docker: docker run --rm hello-world
[docker-install] 3. Verify GPU passthrough: docker run --rm --gpus all nvidia/cuda:12.5.1-base-ubuntu22.04 nvidia-smi
[docker-install] 4. Start NemoClaw from this repo: make init && make deploy
NEXT_STEPS
