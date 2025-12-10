#!/bin/bash

set -euo pipefail

################################################################################
# Configuration
################################################################################
DEPLOYABLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART_PATH="${HELM_CHART_PATH:-${DEPLOYABLE_DIR}/flink-kubernetes-operator}"
HELM_RELEASE_NAME="flink-operator"
NAMESPACE="confluent-platform"

CUSTOM_IMAGE_REPO="quay.io/tonyfieit75/flink-kubernetes-operator"
CUSTOM_IMAGE_TAG="s390x-1.13"

WEBHOOK_ENABLED="false"   # Always disabled for OpenShift s390x stability

CERT_MANAGER_RELEASE="cert-manager"
CERT_MANAGER_NAMESPACE="cert-manager"

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

################################################################################
# Step 1 — Install Cert-Manager
################################################################################
echo -e "${GREEN}📦 Installing cert-manager...${RESET}"
helm repo add jetstack https://charts.jetstack.io || true
helm repo update

kubectl create namespace "${CERT_MANAGER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

CERT_MANAGER_CRDS=(
  certificaterequests.cert-manager.io
  certificates.cert-manager.io
  challenges.acme.cert-manager.io
  clusterissuers.cert-manager.io
  issuers.cert-manager.io
  orders.acme.cert-manager.io
)

echo -e "${GREEN}🔧 Label cert-manager CRDs for Helm ownership...${RESET}"
for crd in "${CERT_MANAGER_CRDS[@]}"; do
  kubectl label crd "$crd" app.kubernetes.io/managed-by=Helm --overwrite || true
  kubectl annotate crd "$crd" meta.helm.sh/release-name=${CERT_MANAGER_RELEASE} --overwrite || true
  kubectl annotate crd "$crd" meta.helm.sh/release-namespace=${CERT_MANAGER_NAMESPACE} --overwrite || true
done

helm upgrade --install ${CERT_MANAGER_RELEASE} jetstack/cert-manager \
  --namespace ${CERT_MANAGER_NAMESPACE} \
  --set installCRDs=true \
  --wait


################################################################################
# Step 2 — Patch Default ConfigMap Template (Permanent Savepoint Disable)
################################################################################
TEMPLATE_FILE="${HELM_CHART_PATH}/templates/default-configmap.yaml"

echo -e "${GREEN}🩹 Applying permanent savepoint-disable patch to ${TEMPLATE_FILE}${RESET}"

cat > "${TEMPLATE_FILE}" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: flink-operator-config
  labels:
    app.kubernetes.io/name: flink-kubernetes-operator
data:
  flink-conf.yaml: |
    taskmanager.numberOfTaskSlots: 1
    parallelism.default: 1

    # ─── PERMANENTLY DISABLE SAVEPOINTS ───────────────────────────────
    kubernetes.operator.periodic.savepoint.enabled: "false"
    kubernetes.operator.periodic.savepoint.interval: "0"
    kubernetes.operator.observer.savepoint.trigger.grace-period: "0"
    kubernetes.operator.job.upgrade.ignore-pending-savepoint: "true"
    kubernetes.operator.savepoint.history.max-age: "0"

    # Predefined Java opts for operator-based deployments
    kubernetes.operator.default-configuration.flink-version.v1_18.env.java.opts.all: --add-exports=java.base/sun.net.util=ALL-UNNAMED --add-exports=java.rmi/sun.rmi.registry=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED --add-exports=java.security.jgss/sun.security.krb5=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.time=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.locks=ALL-UNNAMED

    kubernetes.operator.default-configuration.flink-version.v1_19+.env.java.default-opts.all: --add-exports=java.base/sun.net.util=ALL-UNNAMED --add-exports=java.rmi/sun.rmi.registry=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED --add-exports=java.security.jgss/sun.security.krb5=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.base/java.time=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.locks=ALL-UNNAMED

  log4j-console.properties: |
    rootLogger.level = INFO

  log4j-operator.properties: |
    rootLogger.level = INFO
EOF

echo -e "${GREEN}✔ Template patched.${RESET}"


################################################################################
# Step 3 — Generate custom-values.yaml
################################################################################
echo -e "${GREEN}📄 Generating custom-values.yaml...${RESET}"

cat > "${HELM_CHART_PATH}/custom-values.yaml" <<EOF
image:
  repository: ${CUSTOM_IMAGE_REPO}
  tag: "${CUSTOM_IMAGE_TAG}"
  pullPolicy: IfNotPresent

replicas: 1

strategy:
  type: Recreate

webhook:
  enabled: ${WEBHOOK_ENABLED}
  create: ${WEBHOOK_ENABLED}

rbac:
  create: true

operatorPod:
  podSecurityContext:
    runAsUser: 1000790001
    runAsGroup: 1000790001
    fsGroup: 1000790001
  securityContext:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
    seccompProfile:
      type: RuntimeDefault
EOF


################################################################################
# Step 4 — Install The Operator
################################################################################
echo -e "${GREEN}🚀 Installing Flink Kubernetes Operator...${RESET}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "${HELM_RELEASE_NAME}" "${HELM_CHART_PATH}" \
  -n "${NAMESPACE}" \
  --values "${HELM_CHART_PATH}/custom-values.yaml" \
  --wait

echo -e "${GREEN}🎉 Deployment complete — Savepoints are PERMANENTLY disabled.${RESET}"

