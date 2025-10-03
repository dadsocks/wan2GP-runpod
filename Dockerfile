# Base: CUDA 12.4 to match widely available drivers & wheels
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
SHELL ["/bin/bash","-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# OS deps
RUN set -eux; \
  apt-get update || apt-get update --allow-releaseinfo-change; \
  apt-get install -y --no-install-recommends \
    git git-lfs curl tini ffmpeg build-essential \
    python3 python3-pip \
    libgl1 libglib2.0-0; \
  apt-get clean; rm -rf /var/lib/apt/lists/*

# Torch first (cu124 wheels) + xformers matching Torch
RUN python3 -m pip install --upgrade pip && \
    pip3 install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
      torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 && \
    pip3 install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 \
      xformers==0.0.28.post1

# Clone Wan2GP
WORKDIR /opt
RUN git clone https://github.com/deepbeepmeep/Wan2GP.git
WORKDIR /opt/Wan2GP

# Optional: remove flash-attn from requirements (commonly causes build failures)
RUN sed -i '/flash-attn/d' requirements.txt || true

# Extra runtime deps a few nodes use (safe even if already in reqs)
RUN pip3 install --no-cache-dir \
      onnx onnxruntime opencv-python-headless matplotlib

# Project deps (after Torch/xformers are in place)
RUN PIP_PROGRESS_BAR=off pip3 install --no-cache-dir -r requirements.txt

# App port
ENV PORT=7860
EXPOSE 7860

# Start script (adds optional HF model pulls later if you want)
COPY start_wan2gp.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

ENTRYPOINT ["/usr/bin/tini","--","-s"]
CMD ["/usr/local/bin/start.sh"]
