#!/bin/bash
set -e

NAMESPACE="confluent-platform"
DEPLOYMENT_NAME="basic-flink-deployment"
CRD_LIST=(
  "flinkdeployments.flink.apache.org"
  "flinksessionjobs.flink.apache.org"
  "flinkstatesnapshots.flink.apache.org"
)

echo "🧹 Step 1: Uninstalling Flink Deployment..."
./undeploy_flink_prod.sh

echo "⏳ Waiting for FlinkDeployment resources to terminate..."
for i in {1..10}; do
  if ! oc get flinkdeployment $DEPLOYMENT_NAME -n $NAMESPACE &>/dev/null; then
    echo "✅ FlinkDeployment $DEPLOYMENT_NAME successfully deleted."
    break
  fi
  echo "⏳ Still deleting... retrying in 30s"
  sleep 30
  if [ $i -eq 10 ]; then
    echo "❌ Timeout waiting for FlinkDeployment to delete."
    exit 1
  fi
done

echo "🧼 Cleaning up leftover pods/services/configmaps for $DEPLOYMENT_NAME..."
oc delete pod,svc,cm,route -l app=$DEPLOYMENT_NAME -n $NAMESPACE --ignore-not-found
oc delete pvc -l app=$DEPLOYMENT_NAME -n $NAMESPACE --ignore-not-found

echo "🧹 Step 2: Uninstalling Flink Operator..."
./undeploy_flink_operator.sh

echo "⏳ Waiting for flink-kubernetes-operator pod to be removed..."
for i in {1..10}; do
  if ! oc get pods -n $NAMESPACE | grep -q flink-kubernetes-operator; then
    echo "✅ Flink Operator pod removed."
    break
  fi
  echo "⏳ Still deleting... retrying in 30s"
  sleep 30
  if [ $i -eq 10 ]; then
    echo "❌ Timeout waiting for Flink Operator pod to be deleted."
    exit 1
  fi
done


echo "🧽 Step 3: Removing Flink CRDs..."
for crd in "${CRD_LIST[@]}"; do
  if oc get crd "$crd" &>/dev/null; then
    echo "  → Deleting CRD: $crd"
    oc delete crd "$crd" || echo "⚠️ Failed to delete CRD $crd (might be in use)"
  else
    echo "  → CRD $crd not found, skipping."
  fi
done

echo "⏳ Waiting for CRDs to fully disappear..."
sleep 3
echo "📋 Checking CRDs still present:"
oc get crds | grep -E "flinkdeployments|flinksessionjobs|flinkstatesnapshots" || echo "✅ All Flink CRDs successfully removed."


echo "🧼 Final cleanup: Deleting namespace $NAMESPACE if empty..."
if [ "$(oc get all -n $NAMESPACE 2>/dev/null | wc -l)" -le 1 ]; then
  echo "🔁 Namespace $NAMESPACE appears empty. Deleting..."
  oc delete ns $NAMESPACE || echo "⚠️ Could not delete namespace"
else
  echo "⚠️ Namespace $NAMESPACE still contains resources:"
  oc get all -n $NAMESPACE
fi

echo "🎉 COMPLETE: Flink cluster, operator, and CRDs fully uninstalled!"

