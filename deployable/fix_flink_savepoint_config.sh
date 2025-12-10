#!/bin/bash
set -euo pipefail

NAMESPACE="confluent-platform"

echo "🔍 Finding FlinkDeployments in namespace: $NAMESPACE ..."
DEPLOYMENTS=$(oc get flinkdeployments.flink.apache.org -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$DEPLOYMENTS" ]]; then
  echo "❌ No FlinkDeployments found"
  exit 1
fi

echo "📦 Found: $DEPLOYMENTS"
echo

for DEPLOY in $DEPLOYMENTS; do
  echo "🔧 Applying savepoint hotfix: $DEPLOY"

  # Patch savepoint operator settings (STRING VALUES!)
  oc patch flinkdeployment "$DEPLOY" \
    -n "$NAMESPACE" \
    --type=json \
    -p='[
      {"op":"add","path":"/spec/flinkConfiguration/kubernetes.operator.job.upgrade.ignore-pending-savepoint","value":"true"},
      {"op":"add","path":"/spec/flinkConfiguration/kubernetes.operator.periodic.savepoint.enabled","value":"false"},
      {"op":"add","path":"/spec/flinkConfiguration/kubernetes.operator.periodic.savepoint.interval","value":"0"},
      {"op":"add","path":"/spec/flinkConfiguration/kubernetes.operator.observer.savepoint.trigger.grace-period","value":"0"}
    ]' || true

  echo "✔ Patched"

  echo "🔄 Triggering reconciliation..."
  oc annotate flinkdeployment "$DEPLOY" \
    -n "$NAMESPACE" \
    reconciliationTimestamp="$(date +%s)" --overwrite || true
  echo "✔ Reconciliation triggered"

  echo "♻ Restarting JobManager for: $DEPLOY"

  # Try Flink Operator labels
  JM_POD=$(oc get pods -n $NAMESPACE \
    -l "flinkdeployment=$DEPLOY,role=jobmanager" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  # TRY CMF labels if not found
  if [[ -z "$JM_POD" ]]; then
    JM_POD=$(oc get pods -n $NAMESPACE \
      -l "app=$DEPLOY,component=jobmanager" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  fi

  if [[ -n "$JM_POD" ]]; then
    echo "🔁 Deleting JobManager pod: $JM_POD"
    oc delete pod "$JM_POD" -n $NAMESPACE --wait=false
    echo "✔ JobManager restart initiated"
  else
    echo "⚠ No JobManager found for $DEPLOY (this is normal for SQL or CMF-managed clusters)"
  fi

  echo
done

echo "⏳ Waiting 30 seconds for pods to restart..."
sleep 30

echo "🔍 Operator verification:"
oc logs deployment/flink-kubernetes-operator -n $NAMESPACE | grep savepoint | tail -20 || true

echo
echo "🔍 JobManager config check:"
for DEPLOY in $DEPLOYMENTS; do
  echo "📄 $DEPLOY"

  JM_POD=$(oc get pods -n $NAMESPACE \
    -l "app=$DEPLOY,component=jobmanager" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [[ -z "$JM_POD" ]]; then
    JM_POD=$(oc get pods -n $NAMESPACE \
      -l "flinkdeployment=$DEPLOY,role=jobmanager" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  fi

  if [[ -n "$JM_POD" ]]; then
    oc exec -it "$JM_POD" -n $NAMESPACE -- \
      cat /opt/flink/conf/flink-conf.yaml | grep savepoint || true
  else
    echo "⚠ No JobManager pod to inspect"
  fi

  echo
done

echo "✅ Hotfix completed."

