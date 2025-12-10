#!/bin/bash

set -euo pipefail

NAMESPACE="confluent-platform"
DEPLOYMENT_NAME="basic-flink-deployment"
ROUTE_NAME="flink-dashboard"
YAML_DIR="./yaml"

echo "📦 Step 1: Deploying Flink Operator..."
./deploy_flink_operator_prod.sh

echo "⏳ Waiting for Flink Operator pod to be Ready..."
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=flink-kubernetes-operator -n $NAMESPACE --timeout=180s
echo "✅ Flink Operator is running!"

echo "📦 Step 1.5: Creating ConfigMap for podTemplate (if needed)..."
if [ -f "$YAML_DIR/pod-template.yaml" ]; then
  oc create configmap pod-template-basic-flink-deployment \
    --from-file=pod-template.yaml="$YAML_DIR/pod-template.yaml" \
    -n $NAMESPACE --dry-run=client -o yaml | oc apply -f -
  echo "✅ ConfigMap for pod-template created/updated."
else
  echo "⚠️  pod-template.yaml not found in $YAML_DIR. Skipping ConfigMap creation."
fi

echo "🚀 Step 2: Deploying Flink Application Cluster ($DEPLOYMENT_NAME)..."
./deploy_flink_prod.sh

echo "⏳ Waiting for Flink JobManager pod to be Ready..."

MAX_ATTEMPTS=10
SLEEP_INTERVAL=30
attempt=1

echo "🎉 Flink cluster setup completed successfully!"

while [ $attempt -le $MAX_ATTEMPTS ]; do
  JM_POD=$(oc get pod -n $NAMESPACE -l app=$DEPLOYMENT_NAME,component=jobmanager -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)

  if [ -n "$JM_POD" ]; then
    echo "🔍 Found JobManager pod: $JM_POD (attempt $attempt)"
    if oc wait --for=condition=Ready pod/$JM_POD -n $NAMESPACE --timeout=30s; then
      echo "✅ JobManager pod is Ready!"
      break
    else
      echo "⏳ Pod not ready, retrying in $SLEEP_INTERVAL seconds..."
    fi
  else
    echo "⏳ No JobManager pod yet, waiting $SLEEP_INTERVAL seconds..."
  fi

  attempt=$((attempt + 1))
  sleep $SLEEP_INTERVAL
done

if [ $attempt -gt $MAX_ATTEMPTS ]; then
  echo "❌ Timed out waiting for Flink JobManager pod to become Ready."
  oc get pods -n $NAMESPACE
  exit 1
fi

echo "⏳ Waiting for Flink TaskManager pods to be Ready..."
oc wait --for=condition=Ready pod -l app=$DEPLOYMENT_NAME,component=taskmanager -n $NAMESPACE --timeout=180s

echo "🌐 Verifying Flink REST API via OpenShift Route..."
ROUTE_HOST=$(oc get route $ROUTE_NAME -n $NAMESPACE -o jsonpath='{.spec.host}' || true)
if [ -z "$ROUTE_HOST" ]; then
  echo "❌ Flink dashboard route not found!"
  exit 1
fi

echo "🌍 REST API URL: http://$ROUTE_HOST/jobs/overview"
if curl -k -v "https://$ROUTE_HOST/jobs/overview" | grep -q '"jobs"'; then
  echo "✅ Flink REST API is responding!"
else
  echo "❌ REST API not responding. Please check route/pod logs."
  exit 1
fi

echo "🎉 Flink cluster setup completed successfully!"

