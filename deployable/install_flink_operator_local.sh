#!/bin/bash

set -euo pipefail

# === CONFIGURATION ===
NAMESPACE="flink-operator"
CHART_DIR="/root/flink-kubernetes-operator-1.11.0-helm/flink-kubernetes-operator"
CERT_MANAGER_VERSION="v1.13.1"
DISABLE_WEBHOOK="${1:-false}"

echo "📦 Installing cert-manager CRDs and chart..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "${CERT_MANAGER_VERSION}"

echo "⏳ Waiting for cert-manager to become ready..."
kubectl rollout status deployment cert-manager -n cert-manager
kubectl rollout status deployment cert-manager-webhook -n cert-manager

echo "📥 Installing Flink Operator CRDs..."
kubectl apply -f "${CHART_DIR}/crds/"

echo "✍️ Patching values.yaml..."
# Use sed or inline script to update image repo, tag, and optionally disable webhook
sed -i 's|^\( *repository: \).*|\1 quay.io/tonyfieit75/flink-kubernetes-operator|' "${CHART_DIR}/values.yaml"
sed -i 's|^\( *tag: \).*|\1 "s390x-1.13"|' "${CHART_DIR}/values.yaml"

if [[ "${DISABLE_WEBHOOK}" == "true" ]]; then
  echo "📛 Disabling webhook in values.yaml"
  sed -i '/^webhook:/,/^[^ ]/ s/^\( *enabled: \).*/\1false/' "${CHART_DIR}/values.yaml"
else
  echo "✅ Webhook will be enabled"
  sed -i '/^webhook:/,/^[^ ]/ s/^\( *enabled: \).*/\1true/' "${CHART_DIR}/values.yaml"
fi

echo "🚀 Installing Flink Kubernetes Operator with Helm..."
helm upgrade --install flink-operator "${CHART_DIR}" \
  --namespace "${NAMESPACE}" --create-namespace

echo "✅ Flink Kubernetes Operator is installed in namespace '${NAMESPACE}'."

