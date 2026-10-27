#!/bin/sh
# Healthy while the server's heartbeat file (rewritten every second) is fresh.
f="${STRUCTURE_DATA_DIR:-/data}/runtime/status.json"
[ -f "$f" ] || exit 1
age=$(( $(date +%s) - $(stat -c %Y "$f") ))
[ "$age" -lt 10 ]
