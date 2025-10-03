# ========= WanGP (GPU) – Drop-in Dockerfile =========
# Base: CUDA 12.4 + cuDNN on Ubuntu 22.04 (broad driver compatibility)
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # Helps many gradio apps bind correctly; entrypoint also handles flags.
    GRADIO_SERVER_NAME=0.0.0.0 \
    # Default UI port; change with -e WANGP_PORT=xxxx
    WANGP_PORT=7860 \
    # Good defaults for torch on NVIDIA
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# ---- System deps (with retries) ----
RUN set -euxo pipefail; \
    echo 'APT::Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries; \
    apt-get update || apt-get update --allow-releaseinfo-change; \
    apt-get install -y --no-install-recommends \
      python3 python3-pip python3-dev \
      git git-lfs curl ca-certificates tini ffmpeg \
      build-essential pkg-config cmake ninja-build \
      libgl1; \
    git lfs install; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# ---- Python / Torch (CUDA 12.4 wheels) ----
# If you need newer torch later, adjust versions & index below.
RUN python3 -m pip install --upgrade pip wheel setuptools && \
    PIP_PROGRESS_BAR=off pip3 install --no-cache-dir \
      torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
      --index-url https://download.pytorch.org/whl/cu124

# Helpful common runtime deps (avoid missing-module errors at runtime)
RUN PIP_PROGRESS_BAR=off pip3 install --no-cache-dir \
      onnx opencv-python-headless matplotlib \
      huggingface_hub==0.25.* hf_transfer

# ---- Fetch WanGP source ----
ARG WANGP_REF=main
ENV APP_DIR=/opt/Wan2GP
RUN set -euxo pipefail; \
    mkdir -p "${APP_DIR}"; \
    echo "[clone] Trying git clone (${WANGP_REF})…"; \
    if git clone --depth=1 --branch "${WANGP_REF}" https://github.com/deepbeepmeep/Wan2GP.git "${APP_DIR}" 2>/tmp/git.err; then \
      echo "[clone] git clone OK"; \
    else \
      echo "[clone] git clone failed. Falling back to codeload tarball:"; \
      cat /tmp/git.err || true; \
      rm -rf "${APP_DIR:?}/"*; \
      curl -fL --retry 5 --retry-delay 2 \
        "https://codeload.github.com/deepbeepmeep/Wan2GP/tar.gz/${WANGP_REF}" \
        | tar -xz --strip-components=1 -C "${APP_DIR}"; \
      echo "[clone] tarball fallback OK"; \
    fi

WORKDIR ${APP_DIR}

# ---- Python requirements (use preinstalled torch; avoid re-resolving) ----
# --no-build-isolation lets packages find the already-installed torch/cuda.
RUN set -euxo pipefail; \
    if [ -f requirements.txt ]; then \
      PIP_PROGRESS_BAR=off pip3 install --no-cache-dir -r requirements.txt --no-build-isolation; \
    fi

# ---- Create a robust entrypoint inline ----
RUN cat > /usr/local/bin/entrypoint.sh << 'EOF' && chmod +x /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

cd /opt/Wan2GP

# Optional self-update if env is set (safe on ephemeral pods)
if [[ "${WANGP_SELF_UPDATE:-}" != "" ]]; then
  echo "[self-update] Updating WanGP…"
  git pull --rebase --autostash || true
  if [[ -f requirements.txt ]]; then
    PIP_PROGRESS_BAR=off pip3 install --no-cache-dir -r requirements.txt --no-build-isolation || true
  fi
fi

PORT="${WANGP_PORT:-7860}"
export GRADIO_SERVER_NAME="${GRADIO_SERVER_NAME:-0.0.0.0}"
export GRADIO_SERVER_PORT="${PORT}"

# Prefer explicit flags if supported, else rely on GRADIO_* env
if python3 wgp.py --help 2>/dev/null | grep -E -- '--port|--listen|--host' >/dev/null; then
  echo "[run] Using explicit CLI flags: 0.0.0.0:${PORT}"
  exec python3 wgp.py --listen 0.0.0.0 --port "${PORT}"
else
  echo "[run] Flags not supported; using GRADIO_* env on :${PORT}"
  exec python3 wgp.py
fi
EOF

# ---- Healthcheck (adjust if you change WANGP_PORT) ----
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${WANGP_PORT}/" >/dev/null || exit 1

# Expose the UI port used by the app
EXPOSE 7860

# ---- Tini + entrypoint ----
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/entrypoint.sh"]
