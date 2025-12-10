#!/bin/bash

set -euo pipefail

NAMESPACE="flink-operator"
CHART_DIR="/root/flink-kubernetes-operator-1.11.0-helm/flink-kubernetes-operator"
CERT_MANAGER_NS="cert-manager"
CERT_MANAGER_VERSION="v1.13.1"
DISABLE_WEBHOOK="${1:-false}"

echo "🧹 Cleaning up existing deployments..."

# Uninstall existing Helm releases
helm uninstall flink-operator -n "${NAMESPACE}" || echo "Flink operator not found"
helm uninstall cert-manager -n "${CERT_MANAGER_NS}" || echo "Cert-manager not found"

# Delete namespaces (optional, uncomment if needed)
kubectl delete ns "${NAMESPACE}" --ignore-not-found
kubectl delete ns "${CERT_MANAGER_NS}" --ignore-not-found

# Delete CRDs
echo "🧨 Deleting CRDs..."
kubectl delete -f "${CHART_DIR}/crds/" --ignore-not-found
kubectl delete crd certificaterequests.cert-manager.io \
  certificates.cert-manager.io \
  challenges.acme.cert-manager.io \
  clusterissuers.cert-manager.io \
  issuers.cert-manager.io \
  orders.acme.cert-manager.io --ignore-not-found

# Wait a bit for cleanup to propagate
sleep 10

echo "📦 Reinstalling cert-manager CRDs and chart..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io || true
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace "${CERT_MANAGER_NS}" --create-namespace \
  --version "${CERT_MANAGER_VERSION}"

echo "⏳ Waiting for cert-manager pods..."
kubectl rollout status deployment cert-manager -n "${CERT_MANAGER_NS}"
kubectl rollout status deployment cert-manager-webhook -n "${CERT_MANAGER_NS}"

echo "📥 Reinstalling Flink Operator CRDs..."
kubectl apply -f "${CHART_DIR}/crds/"

echo "✍️ Updating values.yaml with custom image and webhook settings..."
sed -i 's|^\( *repository: \).*|\1 quay.io/tonyfieit75/flink-kubernetes-operator|' "${CHART_DIR}/values.yaml"
sed -i 's|^\( *tag: \).*|\1 "s390x-1.13"|' "${CHART_DIR}/values.yaml"

if [[ "${DISABLE_WEBHOOK}" == "true" ]]; then
  echo "🚫 Disabling webhook..."
  sed -i '/^webhook:/,/^[^ ]/ s/^\( *enabled: \).*/\1false/' "${CHART_DIR}/values.yaml"
else
  echo "✅ Enabling webhook..."
  sed -i '/^webhook:/,/^[^ ]/ s/^\( *enabled: \).*/\1true/' "${CHART_DIR}/values.yaml"
fi

echo "🚀 Installing Flink Operator..."
helm upgrade --install flink-operator "${CHART_DIR}" \
  --namespace "${NAMESPACE}" --create-namespace

echo "✅ Deployment complete."

