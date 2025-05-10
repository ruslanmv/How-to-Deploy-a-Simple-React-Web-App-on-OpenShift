✅ **1. Confirm You Have the CLI Tool**
Check in your terminal:

```bash
oc version           # For OpenShift CLI
kubectl version --client   # For Kubernetes CLI
```

If neither is installed, follow the steps in your distro’s package manager or the official docs:

* **`oc`**: [https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/)
* **`kubectl`**: [https://kubernetes.io/docs/tasks/tools/](https://kubernetes.io/docs/tasks/tools/)

---

✅ **2. Login to the Cluster**
You need your API server URL and a token (from the OpenShift console) or a kubeconfig.

**Option A: `oc login` with token**

```bash
oc login https://api.<your-cluster-domain>:6443 --token=<your-token>
```

*(Copy this from “Copy Login Command” in the console.)*

**Option B: Use kubeconfig (for either CLI)**

```bash
export KUBECONFIG=~/path/to/your/kubeconfig
kubectl config use-context <your-context>
```

---

✅ **3. Switch to Your Namespace**

```bash
oc project ibmid-667000nwl8-hktijvj4       # OpenShift
# OR
kubectl config set-context --current --namespace=ibmid-667000nwl8-hktijvj4
```

---

✅ **4. Verify Access**

```bash
# Should list any existing pods (likely none yet)
oc get pods       # or
kubectl get pods
```

---

## Part 2: Deploying Your Docker Image with `oc`

### ✅ 5. Push Your Image to a Registry

OpenShift needs your container image in a registry it can pull from. For Docker Hub:

```bash
# Tag your local image
docker tag my-app:latest docker.io/<your-dockerhub-username>/my-app:1.0.0

# Push
docker push docker.io/<your-dockerhub-username>/my-app:1.0.0
```

> If you have an internal registry (e.g. `cp.icr.io` or OpenShift’s internal), use its hostname instead of `docker.io`.

---

### ✅ 6. Deploy with `oc`

1. **Create the app**

   ```bash
   oc new-app docker.io/<your-username>/my-app:1.0.0 \
     --name=my-app
   ```

   This does two things:

   * Creates a **DeploymentConfig** (or Deployment) + ReplicaSet + Pod
   * Creates a **Service** named `my-app`

2. **Wait for the pod to come up**

   ```bash
   oc rollout status dc/my-app   # or deployment/my-app
   oc get pods -l app=my-app
   ```

3. **Expose a Route** (OpenShift’s external HTTP endpoint)

   ```bash
   oc expose svc/my-app          # Creates a Route
   ```

4. **Fetch your public URL**

   ```bash
   oc get route my-app -o jsonpath='{.spec.host}'
   ```

   Then open `http://<that-host>` in your browser.

---

## Part 3: Deploying with `kubectl` & Standard Kubernetes Resources

### ✅ 7. Prepare Kubernetes YAMLs

In your project folder, create these three files (update the image path):

**`deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: docker.io/<your-username>/my-app:1.0.0
          ports:
            - containerPort: 8081
```

**`service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8081
```

**`ingress.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - http:                     # ← no `host:` field
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

---

### ✅ 8. Apply the Manifests

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

✅ **Check rollout & endpoints**

```bash
kubectl rollout status deployment/my-app
kubectl get pods,svc,ingress -l app=my-app
```

Visit `http://my-app.<your-domain>` once DNS/Ingress is set up.

---

## Part 4: Key Differences

| Feature                 | `oc` CLI / OpenShift                                                       | `kubectl` / Kubernetes                           |
| ----------------------- | -------------------------------------------------------------------------- | ------------------------------------------------ |
| **App creation**        | `oc new-app <image>` auto-generates DeploymentConfig, BuildConfig, Service | You write pure YAML (`Deployment`, `Service`)    |
| **Routing**             | `oc expose svc/<name>` → Route resource                                    | `kubectl apply` Ingress + DNS setup              |
| **Build Integration**   | Built-in **BuildConfig** (S2I, Docker builds)                              | Separate CI/CD (Tekton, Jenkins, GitHub Actions) |
| **Image registry**      | Supports internal OpenShift registry out of the box                        | You must configure `ImagePullSecrets`            |
| **Templates & Catalog** | Leverages Templates/Catalog for quick scaffolding                          | Helm charts / Kustomize for templating           |
| **Security & SCCs**     | Pod Security Context Constraints (SCCs)                                    | PodSecurity admission & PSP (deprecated)         |

---

🎉 **You’re all set!**

* **With `oc`**, you get fast on-ramps (new-app, expose) and built-in build pipelines.
* **With `kubectl`**, you stay on standard Kubernetes API objects and tooling.

Let me know if you need help configuring advanced features like build pipelines, image pull secrets, or auto-scaling!
