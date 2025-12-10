#!/bin/bash

set -euo pipefail

echo "🔁 Uninstalling Flink Kubernetes Operator and cert-manager..."

helm uninstall flink-operator -n confluent-platform || true
helm uninstall cert-manager -n cert-manager || true

#kubectl delete ns flink-operator --ignore-not-found
kubectl delete ns cert-manager --ignore-not-found

kubectl delete crd flinkdeployments.flink.apache.org || true
kubectl delete crd flinksessionjobs.flink.apache.org || true
kubectl delete crd flinkstatesnapshots.flink.apache.org || true

echo "✅ Uninstallation complete."

