#!/bin/bash

set -euo pipefail

NAMESPACE="confluent-platform"

echo "🔧 Creating namespace (if not exists)..."
oc get ns $NAMESPACE >/dev/null 2>&1 || oc create namespace $NAMESPACE

echo "🔐 Applying ServiceAccount..."
oc apply -f flink-serviceaccount.yaml -n $NAMESPACE

echo "🔐 Applying Role..."
oc apply -f flink-role.yaml -n $NAMESPACE

echo "🔐 Applying RoleBinding..."
oc apply -f flink-rolebinding.yaml -n $NAMESPACE

echo "💾 Creating PersistentVolumeClaim for logs..."
oc apply -f flink-logs-pvc.yaml -n $NAMESPACE

echo "💾 Creating PersistentVolumeClaim for data..."
oc apply -f flink-data-pvc.yaml -n $NAMESPACE

echo "🚀 Deploying FlinkDeployment..."
oc apply -f updated-flink-deployment.yaml -n $NAMESPACE

echo "🌐 Creating OpenShift Route for Flink Dashboard..."
oc apply -f flink-dashboard-route.yaml -n $NAMESPACE

echo "✅ All resources deployed successfully in namespace '$NAMESPACE'."

