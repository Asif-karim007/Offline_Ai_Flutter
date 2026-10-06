#!/usr/bin/env bash
# One command on macOS / Linux: set up Python, then download, OCR, build and upload every pack.
# Safe to re-run: every stage continues where the last run stopped.
#
#   ./run.sh                                     everything, space-saving mode
#   ./run.sh --packs general_class-9-10_bn       just one pack (good first test)
#   ./run.sh --no-upload                         build only, upload later with: ./run.sh upload
set -euo pipefail
cd "$(dirname "$0")"

STAGE="all"
if [[ $# -gt 0 && "$1" != --* ]]; then STAGE="$1"; shift; fi

PY=""
for candidate in python3.12 python3.11 python3.13 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [[ -z "$PY" ]]; then
  echo "Python 3.11 or newer is required: https://www.python.org/downloads/"; exit 1
fi

if [[ ! -d .venv ]]; then
  echo "Creating Python environment (.venv) with $PY ..."
  "$PY" -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

if [[ ! -f .venv/.installed ]]; then
  python -m pip install --upgrade pip
  # Linux without an NVIDIA GPU: the default PyTorch wheel drags in ~3 GB of CUDA libraries
  # it can never use. The CPU build is ~200 MB.
  if [[ "$(uname)" == "Linux" ]] && ! command -v nvidia-smi >/dev/null 2>&1; then
    pip install torch --index-url https://download.pytorch.org/whl/cpu
  fi
  pip install -r requirements.txt
  touch .venv/.installed
fi

if ! command -v tesseract >/dev/null 2>&1; then
  echo
  echo "Tesseract OCR is not installed. Most NCTB books are images, so it is required:"
  echo "  macOS:          brew install tesseract tesseract-lang"
  echo "  Ubuntu/Debian:  sudo apt install tesseract-ocr tesseract-ocr-ben"
  exit 1
fi

if [[ "$STAGE" == "all" || "$STAGE" == "upload" ]] && [[ " $* " != *" --no-upload "* ]]; then
  if ! python -c "from huggingface_hub import HfApi; HfApi().whoami()" >/dev/null 2>&1; then
    echo "Log in to Hugging Face (paste your Write token when asked):"
    hf auth login
  fi
fi

python nctb_pipeline.py "$STAGE" --delete-pdfs "$@"
