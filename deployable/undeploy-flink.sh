#!/bin/bash

set -euo pipefail

NAMESPACE="confluent-platform"

echo "❌ Deleting Flink Dashboard Route..."
oc delete -f flink-dashboard-route.yaml -n $NAMESPACE --ignore-not-found

echo "❌ Deleting Flink Deployment..."
oc delete -f updated-flink-deployment.yaml -n $NAMESPACE --ignore-not-found

echo "🧹 Deleting PersistentVolumeClaims..."
oc delete -f flink-logs-pvc.yaml -n $NAMESPACE --ignore-not-found
oc delete -f flink-data-pvc.yaml -n $NAMESPACE --ignore-not-found

echo "❌ Deleting RoleBinding..."
oc delete -f flink-rolebinding.yaml -n $NAMESPACE --ignore-not-found

echo "❌ Deleting Role..."
oc delete -f flink-role.yaml -n $NAMESPACE --ignore-not-found

echo "❌ Deleting ServiceAccount..."
oc delete -f flink-serviceaccount.yaml -n $NAMESPACE --ignore-not-found

# Optional: delete namespace if you want to remove everything
read -p "Do you want to delete the entire namespace '$NAMESPACE'? [y/N]: " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  echo "⚠️ Deleting namespace $NAMESPACE..."
  oc delete namespace $NAMESPACE --ignore-not-found
else
  echo "✅ Resources deleted, but namespace '$NAMESPACE' was preserved."
fi

