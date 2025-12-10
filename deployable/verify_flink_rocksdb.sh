#!/usr/bin/env bash
set -eo pipefail

# Defaults (override via flags or env)
NS="${NS:-confluent-platform}"
DEPLOYMENT="${DEPLOYMENT:-basic-flink-deployment}"
CONTAINER="${CONTAINER:-flink-main-container}"
EXPECTED_JNI="${EXPECTED_JNI:-rocksdbjni-8.11.3-linux64.jar}"
DO_SAVEPOINT=false
JOB_ID=""

usage() {
  cat <<EOF
Usage: $0 [-n NAMESPACE] [-d DEPLOYMENT] [--container NAME] [--savepoint] [--job-id JOBID]
  -n, --namespace   Namespace (default: ${NS})
  -d, --deployment  FlinkDeployment name (default: ${DEPLOYMENT})
      --container   Container name to exec/log (default: ${CONTAINER}; falls back if missing)
      --savepoint   Stop a running job with a savepoint
      --job-id      Specific job ID to savepoint (implies --savepoint)
      -h, --help    Show this help
Env: NS, DEPLOYMENT, CONTAINER, EXPECTED_JNI can also be set.
EOF
}

# Parse args (no set -u, so it's safe)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NS="$2"; shift 2;;
    -d|--deployment) DEPLOYMENT="$2"; shift 2;;
    --container) CONTAINER="$2"; shift 2;;
    --savepoint) DO_SAVEPOINT=true; shift;;
    --job-id) JOB_ID="$2"; DO_SAVEPOINT=true; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 1;;
  esac
done

command -v oc >/dev/null || { echo "oc CLI not found"; exit 1; }

# Find pods:
find_jm() { oc -n "$NS" get pods -o name | sed 's#pod/##' | grep "^${DEPLOYMENT}-" | grep -v taskmanager | head -n1; }
find_tm() { oc -n "$NS" get pods -o name | sed 's#pod/##' | grep "^${DEPLOYMENT}-taskmanager" | head -n1; }

JM="$(find_jm || true)"
TM="$(find_tm || true)"

if [[ -z "$JM" || -z "$TM" ]]; then
  echo "Could not locate JM/TM pods for deployment '${DEPLOYMENT}' in ns '${NS}'. Pods:"
  oc -n "$NS" get pods -o wide
  exit 1
fi

echo "JM pod: $JM"
echo "TM pod: $TM"

# Helpers: try with -c <container>, fall back without it if not present
exec_in() {
  local pod="$1"; shift
  if oc -n "$NS" exec "$pod" -c "$CONTAINER" -- "$@" 2>/dev/null; then
    return 0
  else
    oc -n "$NS" exec "$pod" -- "$@"
  fi
}
logs_of() {
  local pod="$1"; shift || true
  if oc -n "$NS" logs "$pod" -c "$CONTAINER" 2>/dev/null; then
    return 0
  else
    oc -n "$NS" logs "$pod"
  fi
}

echo "== 1) JNI jar in /opt/flink/lib =="
JNI_LIST="$(exec_in "$TM" sh -lc 'ls -1 /opt/flink/lib | grep -E "^rocksdbjni.*\.jar$"' || true)"
if [[ -z "$JNI_LIST" ]]; then
  echo "✗ rocksdbjni jar NOT found in /opt/flink/lib"
  exit 1
fi
echo "$JNI_LIST"
if echo "$JNI_LIST" | grep -qx "$EXPECTED_JNI"; then
  echo "✓ Found expected: $EXPECTED_JNI"
else
  echo "⚠ Found JNI jar(s) but name differs from EXPECTED_JNI='$EXPECTED_JNI'"
fi

echo "== 2) JNI load in TaskManager logs =="
LOGS="$(logs_of "$TM" || true)"
if echo "$LOGS" | grep -qi 'Successfully loaded RocksDB native library'; then
  echo "✓ JNI load confirmed"
else
  echo "⚠ No success message yet; recent JNI/RocksDB lines:"
  echo "$LOGS" | egrep -i 'rocksdb|jni|native library|no suitable' | tail -n 80 || true
fi
if echo "$LOGS" | grep -qi 'no suitable native library'; then
  echo "✗ Found 'no suitable native library' — JNI not loading correctly"
  exit 1
fi

echo "== 3) Checkpoints on PVC (/flink/checkpoints) =="
if ! exec_in "$TM" sh -lc 'ls -R /flink/checkpoints | sed -n "1,80p"'; then
  echo "⚠ Unable to list /flink/checkpoints (may not exist yet)."
else
  echo "✓ Listed /flink/checkpoints (truncated)."
fi

if $DO_SAVEPOINT; then
  echo "== 4) Savepoint smoke test =="
  if [[ -z "$JOB_ID" ]]; then
    LIST_OUT="$(exec_in "$JM" /opt/flink/bin/flink list -r || true)"
    echo "$LIST_OUT"
    JOB_ID="$(echo "$LIST_OUT" | grep -Eo '[0-9a-f]{32}' | head -n1 || true)"
    [[ -n "$JOB_ID" ]] || { echo "No running job ID found. Start a job or pass --job-id <ID>."; exit 1; }
  fi
  echo "Using JOB_ID: $JOB_ID"
  SP_OUT="$(exec_in "$JM" /opt/flink/bin/flink stop -p /flink/savepoints "$JOB_ID" 2>&1 || true)"
  echo "$SP_OUT"
  SP_PATH="$(echo "$SP_OUT" | grep -Eo '/flink/savepoints[^ ]+' | head -n1 || true)"
  if [[ -n "$SP_PATH" ]]; then
    echo "✓ Savepoint at: $SP_PATH"
  else
    echo "⚠ Could not parse savepoint path (see output above)."
  fi
fi

echo "Done."

