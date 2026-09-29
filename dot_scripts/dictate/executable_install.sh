#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON_BIN:-python3}"

cd "$DIR"

if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "$PYTHON not found"
  echo "Use PYTHON_BIN to use a specific version"
  exit 1
fi

if [[ ! -x ".venv/bin/python" ]]; then
  "$PYTHON" -m venv .venv
fi

.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt

echo "Done"