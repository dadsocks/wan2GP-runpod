# Wan2GP minimal runtime (CUDA 12.4, CUDNN runtime)
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

SHELL ["/bin/bash","-lc"]
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Base OS deps
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      git curl ca-certificates tini ffmpeg \
      python3 python3-pip python3-venv python3-dev \
      libgl1 libglib2.0-0; \
    ln -sf /usr/bin/python3 /usr/bin/python; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# PyTorch for CUDA 12.4
RUN python -m pip install --upgrade pip && \
    pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
      torch torchvision torchaudio

# App
WORKDIR /opt/app
RUN git clone --depth=1 https://github.com/deepbeepmeep/Wan2GP.git .  # main repo
# Install Python deps if present
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

# Default web port (Gradio-style). RunPod will map this.
ENV PORT=7860
EXPOSE 7860

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["bash","-lc","python3 wgp.py --listen --server-port ${PORT}"]
