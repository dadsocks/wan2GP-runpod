# ---- Base: CUDA 12.4 runtime (works on a wide range of RunPod drivers) ----
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

SHELL ["/bin/bash", "-lc"]
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # Optional: place HF cache in a predictable spot
    HF_HOME=/opt/hf-cache

# ---- OS deps: git, ffmpeg, curl, tini, and OpenCV runtime libs ----
RUN set -euxo pipefail; \
    echo 'APT::Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries; \
    apt-get update || apt-get update --allow-releaseinfo-change; \
    apt-get install -y --no-install-recommends \
      git curl ca-certificates tini ffmpeg \
      libgl1 libglib2.0-0; \
    rm -rf /var/lib/apt/lists/*

# ---- Working dir and clone Wan2GP ----
WORKDIR /opt
RUN git clone --depth=1 https://github.com/deepbeepmeep/Wan2GP.git
WORKDIR /opt/Wan2GP

# ---- Python & CUDA wheels (pin to CUDA 12.4) ----
# Notes:
# - Use the PyTorch cu124 test index for 2.6.0 wheels on Ubuntu 22.04
# - xFormers is optional in Wan2GP; try to install a compatible wheel but don’t fail the build if unavailable
RUN python3 -m pip install --upgrade pip && \
    PIP_PROGRESS_BAR=off pip3 install --no-cache-dir \
      torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
      --index-url https://download.pytorch.org/whl/test/cu124 && \
    (pip3 install --no-cache-dir xformers==0.0.28.post2 || true)

# ---- Make requirements.txt safe (avoid conflicting heavy wheels) ----
# Strip out lines that would try to build/install their own torch/xformers/triton/etc.
RUN set -eux; \
    sed -i -E '/^(torch|torchvision|torchaudio|xformers|triton|flash-attn|deepspeed|bitsandbytes|auto-gptq)/Id' requirements.txt; \
    # Add a few runtime deps commonly needed across environments
    python3 - <<'PY'
from pathlib import Path
req = Path("requirements.txt")
extra = """
huggingface_hub>=0.23
safetensors
einops
opencv-python-headless
matplotlib
numpy<2.1
gradio>=4.44
tqdm
requests
"""
req.write_text(req.read_text() + "\n" + extra.strip() + "\n")
PY

# ---- Install the rest of the Python deps ----
RUN PIP_PROGRESS_BAR=off pip3 install --no-cache-dir -r requirements.txt --no-build-isolation

# ---- (Optional) small helper: expose a cleaner start script ----
# You can pass extra flags via W2GP_FLAGS (e.g. "--i2v" or "--t2v")
RUN tee /usr/local/bin/start-wan2gp.sh >/dev/null <<'BASH' && chmod +x /usr/local/bin/start-wan2gp.sh
#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-7860}"
FLAGS="${W2GP_FLAGS:-}"

echo "====================================================="
echo " Wan2GP starting"
echo "  - Port:       ${PORT}"
echo "  - Extra args: ${FLAGS}"
echo "  - HF cache:   ${HF_HOME:-~/.cache/huggingface}"
echo "====================================================="

# If you have a token, Wan2GP/transformers will pick it up
# export HF_TOKEN="${HF_TOKEN:-}"

# Common examples:
#   FLAGS="--i2v"   (image-to-video)
#   FLAGS="--t2v"   (text-to-video)
#   FLAGS="--lowvram" etc. (as supported by the repo)
exec python3 wgp.py --server-name 0.0.0.0 --server-port "${PORT}" ${FLAGS}
BASH

# ---- Healthcheck & runtime ----
EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=5 \
  CMD curl -fsSL "http://127.0.0.1:${PORT:-7860}/" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini","-s","--"]
CMD ["/usr/local/bin/start-wan2gp.sh"]
