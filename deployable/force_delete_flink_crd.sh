#!/bin/bash
set -euo pipefail

CRD_NAME="flinkstatesnapshots.flink.apache.org"

echo "🔍 Checking if CRD '$CRD_NAME' exists..."
if ! oc get crd "$CRD_NAME" &>/dev/null; then
  echo "✅ CRD '$CRD_NAME' does not exist. Nothing to delete."
  exit 0
fi

echo "⚠️ CRD found. Attempting to remove finalizers..."

# Remove finalizers (json patch)
oc patch crd "$CRD_NAME" \
  --type=json \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]' \
  || {
    echo "⚠️ JSON patch failed — trying merge patch instead..."
    oc patch crd "$CRD_NAME" \
      --type=merge \
      -p '{"metadata":{"finalizers":[]}}' \
      || echo "⚠️ Could not remove finalizers with merge patch either."
  }

echo "🗑️ Deleting CRD '$CRD_NAME'..."
oc delete crd "$CRD_NAME" --force --grace-period=0 || true

echo "⏳ Waiting 2 seconds..."
sleep 2

echo "🔍 Verifying deletion..."
if oc get crd "$CRD_NAME" &>/dev/null; then
  echo "❌ ERROR: CRD '$CRD_NAME' is still present!"
  exit 1
fi

echo "✅ CRD '$CRD_NAME' successfully force-deleted."

