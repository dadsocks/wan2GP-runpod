#!/usr/bin/env bash
set -euo pipefail

# If you want to auto-pull models, you can do it here using HF_TOKEN.
# For now we just launch Wan2GP; it will fetch what it needs at first run.
cd /opt/Wan2GP

# Respect $PORT set by the platform (RunPod)
exec python3 wgp.py --server.port "${PORT:-7860}" --server.name "0.0.0.0"
