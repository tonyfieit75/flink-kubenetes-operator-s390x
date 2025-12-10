#!/bin/bash

set -euo pipefail

DEPLOYABLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_FILE_PATH="${YAML_FILE_PATH:-${DEPLOYABLE_DIR}/yaml}"
NAMESPACE="confluent-platform"

echo "🧹 Deleting FlinkDeployment..."
oc delete -f "${YAML_FILE_PATH}/prod-flink-deployment.yaml" -n "$NAMESPACE" || echo "⚠️  FlinkDeployment not found or already deleted."

echo "🧹 Deleting OpenShift Route..."
oc delete -f "${YAML_FILE_PATH}/flink-dashboard-route.yaml" -n "$NAMESPACE" || echo "⚠️  Route not found or already deleted."

echo "🧹 Deleting ConfigMap for flink-conf.yaml..."
if [ -f "${YAML_FILE_PATH}/flink-conf-configmap.yaml" ]; then
  oc delete -f "${YAML_FILE_PATH}/flink-conf-configmap.yaml" -n "$NAMESPACE" || echo "⚠️  ConfigMap not found or already deleted."
else
  echo "⚠️  flink-conf-configmap.yaml not found. Skipping."
fi

echo "🧹 Deleting PVCs..."
oc delete -f "${YAML_FILE_PATH}/flink-data-pvc.yaml" -n "$NAMESPACE" || echo "⚠️  Data PVC not found or already deleted."
oc delete -f "${YAML_FILE_PATH}/flink-logs-pvc.yaml" -n "$NAMESPACE" || echo "⚠️  Logs PVC not found or already deleted."
if [ -f "${YAML_FILE_PATH}/flink-ha-pvc.yaml" ]; then
  oc delete -f "${YAML_FILE_PATH}/flink-ha-pvc.yaml" -n "$NAMESPACE" || echo "⚠️  HA PVC not found or already deleted."
else
  echo "⚠️  flink-ha-pvc.yaml not found. Skipping."
fi

echo "🧹 Deleting RBAC resources..."
oc delete -f "${YAML_FILE_PATH}/flink-rolebinding.yaml" -n "$NAMESPACE" || echo "⚠️  RoleBinding not found or already deleted."
oc delete -f "${YAML_FILE_PATH}/flink-role.yaml" -n "$NAMESPACE" || echo "⚠️  Role not found or already deleted."
oc delete -f "${YAML_FILE_PATH}/flink-serviceaccount.yaml" -n "$NAMESPACE" || echo "⚠️  ServiceAccount not found or already deleted."

echo "✅ Cleanup completed for namespace '$NAMESPACE'."

