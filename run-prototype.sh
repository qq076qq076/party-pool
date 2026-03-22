#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PATH="$ROOT_DIR/prototype/server.py"

if [[ ! -f "$SERVER_PATH" ]]; then
  echo "Cannot find prototype/server.py" >&2
  exit 1
fi

echo "Starting Party Pool prototype server..."
echo "Host page:       http://localhost:8000/host.html"
echo "Controller page: http://localhost:8000/controller.html"

python3 "$SERVER_PATH"
