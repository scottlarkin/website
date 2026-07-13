#!/usr/bin/env bash
# Run the Phoenix server and auto-restart on crash.
# OTP supervisors restart workers inside the BEAM, but if the whole
# mix phx.server process exits, something external must restart it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$(dirname "$0")/.."

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if ! command -v mix >/dev/null 2>&1; then
  echo "mix not found in PATH. Add Elixir to PATH and retry." >&2
  exit 1
fi

restart_delay=3

echo "[$(date -Iseconds)] Building assets..."
mix assets.deploy

while true; do
  echo "[$(date -Iseconds)] Starting mix phx.server (cwd=$(pwd))"
  mix phx.server
  code=$?
  echo "[$(date -Iseconds)] Server exited with code ${code}. Restarting in ${restart_delay}s..."
  sleep "$restart_delay"
done