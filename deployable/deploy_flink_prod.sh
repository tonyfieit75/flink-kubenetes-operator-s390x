#!/bin/bash

set -euo pipefail

DEPLOYABLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_FILE_PATH="${YAML_FILE_PATH:-${DEPLOYABLE_DIR}/yaml}"
CRD_PATH="${DEPLOYABLE_DIR}/flink-kubernetes-operator/crds"

NAMESPACE="confluent-platform"

echo "🔧 Creating namespace (if not exists)..."
oc get ns "$NAMESPACE" >/dev/null 2>&1 || oc create namespace "$NAMESPACE"

echo "📦 Installing Flink CRDs..."
if [ -d "$CRD_PATH" ]; then
  for crd in "$CRD_PATH"/*.yml "$CRD_PATH"/*.yaml; do
    if [ -f "$crd" ]; then
      echo "  → Applying CRD: $(basename "$crd")"
      oc apply -f "$crd"
    fi
  done
else
  echo "❌ CRD directory not found at: $CRD_PATH"
  exit 1
fi

echo "⏳ Waiting for CRDs to register with the API server..."
sleep 4

echo "🔍 Validating CRDs..."

# EXPECTED CRDs (v1)
CRDS=(
  "flinkdeployments.flink.apache.org"
  "flinksessionjobs.flink.apache.org"
  "flinkstatesnapshots.flink.apache.org"
)

missing=0

for crd in "${CRDS[@]}"; do
  if ! oc get crd "$crd" >/dev/null 2>&1; then
    echo "❌ ERROR: CRD missing: $crd"
    missing=1
  else
    echo "✅ CRD found: $crd"
  fi
done

if [ "$missing" -eq 1 ]; then
  echo "❌ One or more Flink CRDs are missing. Aborting."
  exit 1
fi

echo "🔎 Detecting installed FlinkDeployment API version..."
API_VERSION=$(oc explain flinkdeployment 2>/dev/null | grep VERSION | awk '{print $2}' || echo "")

if [ -z "$API_VERSION" ]; then
  echo "❌ ERROR: Could not determine API version for flinkdeployment."
  exit 1
fi

echo "📢 Installed API Version: $API_VERSION"

if [[ "$API_VERSION" != "v1" ]]; then
  echo "⚠️ WARNING: Expected v1 CRDs. Installed version = $API_VERSION"
  echo "    Make sure prod-flink-deployment.yaml uses:"
  echo "      apiVersion: flink.apache.org/v1"
fi

echo "🔐 Applying ServiceAccount..."
oc apply -f "${YAML_FILE_PATH}/flink-serviceaccount.yaml" -n "$NAMESPACE"

echo "🔐 Applying Role..."
oc apply -f "${YAML_FILE_PATH}/flink-role.yaml" -n "$NAMESPACE"

echo "🔐 Applying RoleBinding..."
oc apply -f "${YAML_FILE_PATH}/flink-rolebinding.yaml" -n "$NAMESPACE"

echo "💾 Creating PersistentVolumeClaim for logs..."
oc apply -f "${YAML_FILE_PATH}/flink-logs-pvc.yaml" -n "$NAMESPACE"

echo "💾 Creating PersistentVolumeClaim for data..."
oc apply -f "${YAML_FILE_PATH}/flink-data-pvc.yaml" -n "$NAMESPACE"

echo "💾 Creating PersistentVolumeClaim for HA metadata (optional)..."
if [ -f "${YAML_FILE_PATH}/flink-ha-pvc.yaml" ]; then
  oc apply -f "${YAML_FILE_PATH}/flink-ha-pvc.yaml" -n "$NAMESPACE"
else
  echo "⚠️  Skipping flink-ha-pvc.yaml — file not found."
fi

echo "⚙️ Applying ConfigMap for flink-conf.yaml..."
if [ -f "${YAML_FILE_PATH}/flink-conf-configmap.yaml" ]; then
  oc apply -f "${YAML_FILE_PATH}/flink-conf-configmap.yaml" -n "$NAMESPACE"
else
  echo "⚠️  Skipping flink-conf-configmap.yaml — file not found."
fi

echo "🚀 Deploying production-grade FlinkDeployment..."
oc apply -f "${YAML_FILE_PATH}/prod-flink-deployment.yaml" -n "$NAMESPACE"

echo "🌐 Creating OpenShift Route for Flink Dashboard..."
oc apply -f "${YAML_FILE_PATH}/flink-dashboard-route.yaml" -n "$NAMESPACE"

echo "✅ All production resources deployed successfully in namespace '$NAMESPACE'."

