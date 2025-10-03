# ---- Base: CUDA 12.4 runtime ----
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
SHELL ["/bin/bash","-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/opt/hf-cache

# ---- OS deps + Python ----
RUN set -euxo pipefail; \
    echo 'APT::Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries; \
    apt-get update || apt-get update --allow-releaseinfo-change; \
    apt-get install -y --no-install-recommends \
      git git-lfs curl ca-certificates tini ffmpeg \
      python3 python3-pip \
      libgl1 libglib2.0-0 build-essential; \
    ln -sf /usr/bin/python3 /usr/bin/python; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# ---- Torch/cu124 first (then optional xFormers) ----
RUN python3 -m pip install -U pip setuptools wheel && \
    PIP_PROGRESS_BAR=off pip3 install --no-cache-dir \
      torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
      --index-url https://download.pytorch.org/whl/test/cu124 && \
    (pip3 install --no-cache-dir xformers==0.0.28.post2 || true)

# ---- App code ----
WORKDIR /opt
RUN git clone --depth=1 https://github.com/deepbeepmeep/Wan2GP.git
WORKDIR /opt/Wan2GP

# ---- Prune heavy/conflicting deps from requirements.txt ----
RUN set -eux; \
    if [ -f requirements.txt ]; then \
      sed -i -E '/^(torch|torchvision|torchaudio|xformers|triton|flash-attn|deepspeed|bitsandbytes|auto-gptq)/Id' requirements.txt; \
    fi; \
    python3 - <<'PY'
from pathlib import Path
p = Path("requirements.txt")
p.write_text((p.read_text() if p.exists() else "") + """
huggingface_hub>=0.23
safetensors
einops
opencv-python-headless
matplotlib
numpy<2.1
gradio>=4.44
tqdm
requests
""")
PY

# ---- Install remaining Python deps ----
RUN PIP_PROGRESS_BAR=off pip3 install --no-cache-dir -v -r requirements.txt --no-build-isolation

# ---- Start script ----
RUN tee /usr/local/bin/start-wan2gp.sh >/dev/null <<'BASH' && chmod +x /usr/local/bin/start-wan2gp.sh
#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-7860}"
FLAGS="${W2GP_FLAGS:-}"
echo "====================================================="
echo " Wan2GP starting on :$PORT"
echo " Extra args: $FLAGS"
echo "====================================================="
exec python3 wgp.py --server-name 0.0.0.0 --server-port "$PORT" $FLAGS
BASH

# ---- Healthcheck & runtime ----
EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=5 \
  CMD curl -fsSL "http://127.0.0.1:${PORT:-7860}/" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini","-s","--"]
CMD ["/usr/local/bin/start-wan2gp.sh"]
