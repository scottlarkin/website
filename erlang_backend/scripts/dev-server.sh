#!/usr/bin/env bash
# Dev/test server on a separate port so prod on 3000 stays untouched.
# Usage: ./scripts/dev-server.sh
#        DEV_PORT=3002 ./scripts/dev-server.sh  # other ports need firewall rules on NixOS
#        ./scripts/dev-server.sh --build   # rebuild assets before start
set -euo pipefail

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

export MIX_ENV=dev
export PORT="${DEV_PORT:-3001}"
# Prod .env sets PHX_HOST for the public tunnel; keep dev on localhost.
unset PHX_HOST

if [[ "${1:-}" == "--build" ]]; then
  echo "[$(date -Iseconds)] Building assets..."
  mix assets.build
  shift
fi

echo "[$(date -Iseconds)] Dev server on http://localhost:${PORT} (prod remains on 3000)"
lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -n "$lan_ip" ]] && echo "LAN access: http://${lan_ip}:${PORT}"
exec mix phx.server "$@"