#!/usr/bin/env bash
# Local-dev wrapper around docker compose for MiniTwit.
#
# Wraps the same subcommands as the original Session 1 helper (init / start /
# startprod / stop / inspectdb / flag) but runs everything through docker
# compose instead of a host-local Python + SQLite setup. The production stack
# uses docker stack deploy on the swarm; this script is the equivalent for a
# developer machine.
#
# Requirements:
#   - docker + docker compose plugin installed
#   - .env in the repo root with at least DATABASE_URL, SECRET_KEY,
#     SIMULATOR_BASIC_AUTH, GF_SECURITY_ADMIN_PASSWORD set
#
# Note: docker-compose.yml is written for Swarm (deploy: keys, configs:
# external, host_ip for ports). `docker compose up` ignores the swarm-only
# fields and starts a flat dev stack — good enough for local testing.

set -euo pipefail

cd "$(dirname "$0")"

IMAGE="michaelfant/minitwitimage:latest"
FLAG_IMAGE="michaelfant/flagtoolimage:latest"
COMPOSE="docker compose"

require_env() {
  if [[ ! -f .env ]]; then
    echo "ERROR: .env not found in $(pwd). Create it (see README §2)." >&2
    exit 1
  fi
}

case "${1:-}" in
  init)
    require_env
    echo "Initializing database schema via the app image..."
    docker run --rm --env-file .env "$IMAGE" \
      python -c "from db import init_db; init_db()"
    ;;

  start)
    require_env
    echo "Starting MiniTwit stack (foreground)..."
    $COMPOSE up
    ;;

  startprod)
    require_env
    echo "Starting MiniTwit stack (detached)..."
    $COMPOSE up -d
    ;;

  stop)
    echo "Stopping MiniTwit stack..."
    $COMPOSE down
    ;;

  inspectdb)
    echo "Listing flagged messages via flag_tool..."
    docker run --rm --env-file .env "$FLAG_IMAGE" ./flag_tool -i
    ;;

  flag)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Usage: $0 flag <message_id> [<message_id> ...]" >&2
      exit 1
    fi
    docker run --rm --env-file .env "$FLAG_IMAGE" ./flag_tool "$@"
    ;;

  *)
    echo "Usage: $0 {init|start|startprod|stop|inspectdb|flag <args>}"
    exit 1
    ;;
esac
