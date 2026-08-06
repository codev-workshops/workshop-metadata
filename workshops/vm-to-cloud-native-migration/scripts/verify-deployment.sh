#!/usr/bin/env bash
# Acceptance gates for the timesheet VM -> cloud-native migration.
#
# Reproduces how terraform/infrastructure/user_data.sh actually runs the container on EC2:
#   - the data directory is created by root (`mkdir -p /opt/app/data`)
#   - `docker run -p 80:$APP_PORT -v /opt/app/data:/app/data -e NODE_ENV=production
#      -e PORT=$APP_PORT -e DATABASE_PATH=/app/data/timesheet.db`
# and then asserts the things unit tests cannot: the container starts, its schema matches the
# application code, data survives a restart, it does not run as root, and it shuts down cleanly.
#
# Exit code 0 means every gate passed. Run it before and after the migration.
#
# Usage: ./verify-deployment.sh [image_tag] [host_port]
set -uo pipefail

IMAGE="${1:-timesheet:local}"
PORT="${2:-8080}"
NAME="timesheet-acceptance"
DATA_DIR="${DATA_DIR:-/tmp/timesheet-acceptance-data}"
BASE="http://localhost:${PORT}"
USER_HEADER="x-user-email: acceptance@example.com"

pass=0; fail=0
gate() { # gate <name> <0|1 result> [detail]
  if [ "$2" -eq 0 ]; then printf 'PASS  %s\n' "$1"; pass=$((pass+1));
  else printf 'FAIL  %s%s\n' "$1" "${3:+ — $3}"; fail=$((fail+1)); fi
}

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

# Recreate the production data directory exactly as user_data.sh does: owned by root.
sudo rm -rf "$DATA_DIR"
sudo mkdir -p "$DATA_DIR"

# EXTRA_RUN_ARGS lets a migrated target join a managed datastore, e.g.
#   EXTRA_RUN_ARGS="--network timesheet_default -e DATABASE_URL=postgres://..." ./verify-deployment.sh
# shellcheck disable=SC2086
docker run -d --name "$NAME" \
  --restart unless-stopped \
  -p "${PORT}:3001" \
  -v "${DATA_DIR}:/app/data" \
  -e NODE_ENV=production \
  -e PORT=3001 \
  -e DATABASE_PATH=/app/data/timesheet.db \
  ${EXTRA_RUN_ARGS:-} \
  "$IMAGE" >/dev/null

# ---------------------------------------------------------------- G1 container stays up
# A crashing container is briefly "running", so require the healthcheck to report healthy
# (or, for an image without a healthcheck, 15 consecutive seconds of running).
up=1
running_for=0
for _ in $(seq 1 60); do
  state=$(docker inspect --format '{{.State.Status}}' "$NAME" 2>/dev/null || echo gone)
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$NAME" 2>/dev/null || echo none)
  [ "$health" = "healthy" ] && { up=0; break; }
  if [ "$state" = "running" ]; then
    running_for=$((running_for+1))
    [ "$health" = "none" ] && [ "$running_for" -ge 15 ] && { up=0; break; }
  else
    break
  fi
  sleep 1
done
gate "G1 container stays running on a root-owned data volume" "$up" \
  "$(docker logs "$NAME" 2>&1 | grep -m1 -i 'error' || echo 'container is not running')"

if [ "$up" -ne 0 ]; then
  echo; echo "SUMMARY: ${pass} passed, ${fail} failed (aborted early — container never started)"
  exit 1
fi

# ---------------------------------------------------------------- G2 health endpoint
for _ in $(seq 1 30); do curl -sf "${BASE}/health" >/dev/null 2>&1 && break; sleep 1; done
curl -sf "${BASE}/health" >/dev/null 2>&1
gate "G2 /health returns 200" "$?"

# ---------------------------------------------------------------- G3 schema matches app code
body='{"name":"Acceptance Client","description":"gate","department":"QA","email":"client@example.com"}'
post=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE}/api/clients" \
  -H "$USER_HEADER" -H 'content-type: application/json' -d "$body")
list=$(curl -s -w '\n%{http_code}' "${BASE}/api/clients" -H "$USER_HEADER")
list_code=$(printf '%s' "$list" | tail -n1)
list_body=$(printf '%s' "$list" | sed '$d')
if [ "$post" = "201" ] && [ "$list_code" = "200" ] && printf '%s' "$list_body" | grep -q 'Acceptance Client'; then
  gate "G3 client can be written and read back (runtime schema matches app code)" 0
else
  gate "G3 client can be written and read back (runtime schema matches app code)" 1 \
    "POST=${post} GET=${list_code} $(docker logs "$NAME" 2>&1 | grep -m1 'SQLITE' || true)"
fi

# ---------------------------------------------------------------- G4 data survives a restart
docker restart "$NAME" >/dev/null
for _ in $(seq 1 30); do curl -sf "${BASE}/health" >/dev/null 2>&1 && break; sleep 1; done
after=$(curl -s "${BASE}/api/clients" -H "$USER_HEADER")
printf '%s' "$after" | grep -q 'Acceptance Client'
gate "G4 data survives a container restart" "$?" "response: $(printf '%s' "$after" | head -c 120)"

# ---------------------------------------------------------------- G5 app process is not root
# Checks the user of the application process itself, not the image's default exec user, so that
# an entrypoint which starts as root and drops privileges still passes.
app_user=$(docker top "$NAME" 2>/dev/null \
  | awk '$NF ~ /server\.js$/ && $0 !~ /dumb-init|entry\.sh|\/bin\/sh/ {print $1; exit}')
app_user="${app_user:-unknown}"
[ "$app_user" != "root" ] && [ "$app_user" != "0" ] && [ "$app_user" != "unknown" ]
gate "G5 application process does not run as root (user=${app_user})" "$?"

# ---------------------------------------------------------------- G6 graceful shutdown
start=$(date +%s)
docker stop -t 15 "$NAME" >/dev/null 2>&1
elapsed=$(( $(date +%s) - start ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$NAME" 2>/dev/null || echo 1)
{ [ "$elapsed" -lt 12 ] && { [ "$code" = "0" ] || [ "$code" = "143" ]; }; }
gate "G6 handles SIGTERM and exits cleanly (${elapsed}s, exit ${code})" "$?"

echo
echo "SUMMARY: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
