#!/usr/bin/env bash

set -euo pipefail

if [[ -f "$HOME/.scripts/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$HOME/.scripts/.env"
  set +a
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv="$DIR/.venv"

if [[ ! -x "$venv/bin/python" ]]; then
  echo "Dictation environment is missing or incomplete."
  echo "Run $DIR/install.sh"
  exit 1
fi

CUDA_LIB_PATH="$("$venv/bin/python" -c 'import nvidia.cublas.lib, nvidia.cudnn.lib; print(next(iter(nvidia.cublas.lib.__path__)) + ":" + next(iter(nvidia.cudnn.lib.__path__)))')"

export LD_LIBRARY_PATH="$CUDA_LIB_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$venv/bin/python" "$DIR/main.py" "$@"