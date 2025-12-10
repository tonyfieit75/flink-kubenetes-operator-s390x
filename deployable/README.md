

# 🚀 Flink on OpenShift (s390x)

This project provides a production-ready deployment of **Apache Flink on OpenShift (s390x architecture)** using the **Flink Kubernetes Operator**, persistent storage, and REST dashboard exposure.

It deploys:
- ✅ 1 **JobManager** pod  
- ✅ 3 **TaskManager** pods  
- ✅ Flink Dashboard via OpenShift Route  
- ✅ Full RBAC, PVCs, and Helm chart-based operator deployment


## 📁 Repository Structure

```

flink-on-openshift-s390x/
└── deployable/
├── setup\_flink\_cluster.sh            # Main script to deploy everything
├── cleanup\_flink\_cluster.sh          # Full cleanup script
├── deploy\_flink\_operator\_prod.sh     # Operator deployment script (uses Helm)
├── deploy\_flink\_prod.sh              # FlinkDeployment + resources
├── undeploy\_flink\_operator.sh        # Uninstall operator only
├── undeploy-flink.sh                 # Uninstall FlinkDeployment only
├── flink-kubernetes-operator/        # Helm chart for the Flink operator
│   ├── Chart.yaml
│   ├── values.yaml / prod-values.yaml / custom-values.yaml
│   ├── conf/                         # log and flink-conf.yaml
│   ├── crds/                         # FlinkDeployment CRDs
│   └── templates/                    # Operator manifests
├── yaml/
│   ├── prod-flink-deployment.yaml    # Main FlinkDeployment manifest
│   ├── flink-serviceaccount.yaml     # RBAC resources
│   ├── flink-role.yaml
│   ├── flink-rolebinding.yaml
│   ├── flink-conf-configmap.yaml     # Custom flink-conf.yaml as ConfigMap
│   ├── flink-logs-pvc.yaml
│   ├── flink-data-pvc.yaml
│   ├── flink-ha-pvc.yaml             # (optional) HA support
│   ├── flink-dashboard-route.yaml    # OpenShift route for REST UI
│   ├── session-cluster.yaml          # Optional session mode example
│   └── values.s390x.prod.yaml        # Helm values for s390x tuning

````

---

## 🧠 Architecture Overview

| Component       | Description |
|----------------|-------------|
| **JobManager** | Master node: schedules jobs, checkpoints, failover |
| **TaskManagers** | Workers that execute job operators in parallel |
| **Flink Operator** | Manages the lifecycle of Flink jobs via CRDs |
| **PVCs**       | Persistent volumes for logs, HA metadata, and data |
| **Route**      | OpenShift Route exposes the Flink Dashboard on port `8081` |

---

## 🛠 Prerequisites

- OpenShift 4.x (s390x supported cluster)
- `oc` CLI and authenticated
- `helm` (v3)
- Cluster with RWX or RWO PVC support

---

## 🚀 Deploy in One Command

From the `deployable/` directory:

```bash
./setup_flink_cluster.sh
````

This performs:

* Helm install of `cert-manager` and Flink Operator
* Waits for operator pod readiness
* Applies all RBAC, PVCs, ConfigMap, FlinkDeployment
* Verifies JobManager & TaskManagers are up
* Exposes dashboard via OpenShift route
* Validates Flink REST API is active

---

## 🔍 Validate Deployment

### 1. Verify Pods

```bash
oc get pods -n flink-operator
```

Expected:

* 1x `flink-kubernetes-operator`
* 1x `JobManager`
* 3x `TaskManager`

### 2. Dashboard Access

```bash
oc get route flink-dashboard -n flink-operator
```

Visit `http://<ROUTE-HOST>:8081` to access Flink Dashboard.

### 3. REST API Health Check

```bash
curl http://<ROUTE-HOST>/jobs/overview
```

You should see JSON with `"jobs"` key.

---

## 🧼 Cleanup

To remove all resources:

```bash
./cleanup_flink_cluster.sh
```

This deletes:

* FlinkDeployment
* Operator (Helm uninstall)
* PVCs, ConfigMaps, Roles, and Route

---

## 🧪 Optional: Session Cluster

A `yaml/session-cluster.yaml` is provided for advanced use cases using session mode.

```bash
oc apply -f yaml/session-cluster.yaml -n flink-operator
```

---

## 📦 Helm Chart: Flink Operator

Located in `flink-kubernetes-operator/`, you may customize the chart and deploy it standalone:

```bash
helm upgrade --install flink-operator ./flink-kubernetes-operator \
  --namespace flink-operator --create-namespace \
  --values ./flink-kubernetes-operator/prod-values.yaml
```

---

## 🧠 Future Enhancements

* Enable webhook (currently disabled for simplicity)
* CI pipeline for automatic rollout
* Example Flink job (WordCount) on startup

---

## 👤 Author

**Antoine Fievre**
IBM LinuxONE & OpenShift Solution Architect

---

## 🪪 License

Apache License 2.0

```

---

