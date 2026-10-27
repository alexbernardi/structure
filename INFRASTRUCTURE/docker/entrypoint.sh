#!/bin/sh
# PID 1 of the server container. Translates `docker stop` (SIGTERM/SIGINT) into the server's graceful
# shutdown request (control file), so the world is saved and the shutdown is logged before exit.
set -eu

RUNTIME_DIR="${STRUCTURE_DATA_DIR}/runtime"
mkdir -p "${RUNTIME_DIR}"

log() {
  printf '{"ts":"%s","lvl":"info","role":"entrypoint","env":"%s","evt":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "${STRUCTURE_ENV_ID}" "$1"
}

/opt/godot/godot --headless --path /app/project -- --server "$@" &
child=$!

request_stop() {
  log "entrypoint.stop_signal"
  touch "${RUNTIME_DIR}/shutdown.request"
}
trap request_stop TERM INT

# `wait` returns early when a trapped signal arrives; keep waiting until the server really exits.
status=0
while :; do
  if wait "$child"; then status=0; else status=$?; fi
  kill -0 "$child" 2>/dev/null || break
done
log "entrypoint.exit"
exit "$status"
