#!/bin/bash

set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART_PATH="${HELM_CHART_PATH:-${SCRIPT_DIR}/flink-kubernetes-operator}"

# Configuration
HELM_RELEASE_NAME="flink-operator"
NAMESPACE="flink-operator"
CERT_MANAGER_RELEASE="cert-manager"
CERT_MANAGER_NAMESPACE="cert-manager"
CUSTOM_IMAGE_REPO="quay.io/tonyfieit75/flink-kubernetes-operator"
CUSTOM_IMAGE_TAG="s390x-1.13"
WEBHOOK_ENABLED="${1:-false}"  # Usage: ./deploy_flink_operator_prod.sh [true|false]

# Colors
green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

echo -e "${green}📦 Installing cert-manager...${reset}"

helm repo add jetstack https://charts.jetstack.io || true
helm repo update

kubectl create namespace "${CERT_MANAGER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo -e "${green}🔧 Patching cert-manager CRDs (if they exist)...${reset}"

CERT_MANAGER_CRDS=(
  certificaterequests.cert-manager.io
  certificates.cert-manager.io
  challenges.acme.cert-manager.io
  clusterissuers.cert-manager.io
  issuers.cert-manager.io
  orders.acme.cert-manager.io
)

for crd in "${CERT_MANAGER_CRDS[@]}"; do
  kubectl label crd "$crd" app.kubernetes.io/managed-by=Helm --overwrite || true
  kubectl annotate crd "$crd" meta.helm.sh/release-name=${CERT_MANAGER_RELEASE} --overwrite || true
  kubectl annotate crd "$crd" meta.helm.sh/release-namespace=${CERT_MANAGER_NAMESPACE} --overwrite || true
done

helm upgrade --install ${CERT_MANAGER_RELEASE} jetstack/cert-manager \
  --namespace ${CERT_MANAGER_NAMESPACE} \
  --set installCRDs=true

echo -e "${green}📥 Preparing Flink Operator Helm chart values...${reset}"

if [[ ! -f "${HELM_CHART_PATH}/values.yaml" ]]; then
  echo -e "${red}❌ ERROR: values.yaml not found in ${HELM_CHART_PATH}${reset}"
  exit 1
fi

cp "${HELM_CHART_PATH}/values.yaml" "${HELM_CHART_PATH}/values.yaml.bak"

cat > "${HELM_CHART_PATH}/custom-values.yaml" <<EOF
image:
  repository: ${CUSTOM_IMAGE_REPO}
  pullPolicy: IfNotPresent
  tag: "${CUSTOM_IMAGE_TAG}"

replicas: 1

strategy:
  type: Recreate

rbac:
  create: true
  operatorRole:
    create: true
    name: "flink-operator"
  operatorRoleBinding:
    create: true
    name: "flink-operator-role-binding"
  jobRole:
    create: true
    name: "flink"
  jobRoleBinding:
    create: true
    name: "flink-role-binding"

operatorPod:
  podSecurityContext:
    runAsUser: 1000790001
    runAsGroup: 1000790001
    fsGroup: 1000790001

  securityContext:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    seccompProfile:
      type: RuntimeDefault

  resources:
    limits:
      cpu: "500m"
      memory: "1Gi"
    requests:
      cpu: "250m"
      memory: "512Mi"

webhook:
  enabled: ${WEBHOOK_ENABLED}
  securityContext:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    seccompProfile:
      type: RuntimeDefault
  resources:
    limits:
      cpu: "250m"
      memory: "512Mi"
    requests:
      cpu: "100m"
      memory: "256Mi"

defaultConfiguration:
  create: true
  flink-conf.yaml: |
    kubernetes.operator.periodic.savepoint.interval: 10m
  log4j-operator.properties: |
    rootLogger.level = INFO
  log4j-console.properties: |
    rootLogger.level = INFO
EOF

echo -e "${green}🚀 Installing Flink Kubernetes Operator in '${NAMESPACE}' namespace...${reset}"

helm upgrade --install ${HELM_RELEASE_NAME} "${HELM_CHART_PATH}" \
  -n ${NAMESPACE} --create-namespace \
  --values "${HELM_CHART_PATH}/custom-values.yaml"

echo -e "${green}✅ Done. Flink Operator deployed with webhook.enabled=${WEBHOOK_ENABLED}.${reset}"

