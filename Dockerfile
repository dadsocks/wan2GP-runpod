# WanGP on CUDA 12.4 runtime (Ubuntu 22.04)
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# System deps
RUN set -eux; \
    echo 'APT::Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries; \
    apt-get update || apt-get update --allow-releaseinfo-change; \
    apt-get install -y --no-install-recommends \
      git curl ca-certificates tini ffmpeg \
      python3 python3-pip python3-venv \
      build-essential pkg-config \
      libglib2.0-0 libsm6 libxrender1 libxext6 libgl1 \
    ; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# Python: torch 2.6.0 + cu124 (matches the project's Debian/CUDA flow)
# (They document both 2.6.0 cu124 and 2.7.0 cu128; cu124 is safer on RunPod.) :contentReference[oaicite:2]{index=2}
RUN python3 -m pip install --upgrade pip && \
    PIP_PROGRESS_BAR=off pip3 install --no-cache-dir \
      torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
      --index-url https://download.pytorch.org/whl/cu124

# Optional: common runtime libs some tools want
RUN PIP_PROGRESS_BAR=off pip3 install --no-cache-dir \
      onnxruntime-gpu==1.19.2 \
      opencv-python-headless \
      matplotlib

# App
WORKDIR /opt
RUN git clone --depth=1 https://github.com/deepbeepmeep/Wan2GP.git
WORKDIR /opt/Wan2GP

# App deps
# If a package fails to build, --no-build-isolation keeps builds predictable.
RUN PIP_PROGRESS_BAR=off pip3 install --no-cache-dir -r requirements.txt --no-build-isolation

# (If the repo ships extra optional requirements in docs later, add them here.)

# Networking
ENV WANGP_PORT=7860
EXPOSE 7860

# Run under tini (clean signal handling)
ENTRYPOINT ["/usr/bin/tini","--"]

# Start WanGP (bind to all interfaces so RunPod can proxy it)
CMD ["bash","-lc","python3 wgp.py --server.port ${WANGP_PORT} --server.host 0.0.0.0 || python3 wgp.py"]
