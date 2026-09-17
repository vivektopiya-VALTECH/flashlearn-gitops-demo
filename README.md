# FlashLearn GitOps Demo

A progressive knowledge-sharing demo of GitOps with Argo CD on a single-node
kind cluster. Every Kubernetes resource created by this repository uses the
`fl-` prefix.

Repository: <https://github.com/vivektopiya-VALTECH/flashlearn-gitops-demo.git>

## What this demonstrates

1. A plain nginx Pod managed by an Argo CD `Application` in the `default` project.
2. A directory of raw Deployment, Service, and Ingress manifests.
3. A local nginx Helm chart configured with both `valueFiles` and `valuesObject`.
4. An app-of-apps root that creates nginx and echo child applications in `dev`
   and `prod` namespaces using Kustomize overlays.

All applications use automated sync, pruning, and self-healing so a Git change
is reconciled and manual cluster drift is reverted.

## Prerequisites

- Docker Desktop or another running Docker engine
- `kind` v0.33.0 or newer
- `kubectl`
- `git`
- Optional: `argocd` and `helm` CLIs
- Optional: standalone `kustomize` for offline overlay validation

On macOS:

```bash
brew install kind kubectl argocd helm kustomize
```

## 1. Create the cluster and install Argo CD

From the repository root:

```bash
./scripts/bootstrap.sh
```

The script creates one control-plane node named `fl-gitops`, installs Argo CD
v3.5.3 in `argocd`, and installs ingress-nginx v1.15.1. Host ports are mapped as
`localhost:8081` to HTTP and `localhost:8443` to HTTPS.

Confirm the platform:

```bash
kubectl get nodes
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
```

## 2. Open Argo CD

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open <https://localhost:8080>, accept the local certificate warning, and sign in
as `admin`. Get the initial password in another terminal:

```bash
argocd admin initial-password -n argocd
```

For CLI access through the same port-forward:

```bash
argocd login localhost:8080 --username admin --insecure
```

## Private repository setup

The configured GitHub URL must be reachable by Argo CD. No credentials are
needed while it is public. For a private repository, add credentials without
committing a token:

```bash
argocd repo add https://github.com/vivektopiya-VALTECH/flashlearn-gitops-demo.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN
```

## 3. Run the examples

Push these files to the `main` branch before creating Applications because
Argo CD reads Git, not the local working tree.

### Simple Pod

```bash
kubectl apply -f bootstrap/fl-simple-pod.yaml
kubectl get application -n argocd fl-simple-pod
kubectl get pod fl-nginx-pod
```

### Directory of manifests

```bash
kubectl apply -f bootstrap/fl-directory-app.yaml
kubectl get deployment,service,ingress -l app.kubernetes.io/instance=fl-directory-nginx
curl -H 'Host: directory.fl.local' http://localhost:8081
```

### Helm chart

```bash
kubectl apply -f bootstrap/fl-helm-app.yaml
kubectl get application -n argocd fl-helm-nginx
curl -H 'Host: helm.fl.local' http://localhost:8081
```

`values-demo.yaml` sets two replicas. The Application's `valuesObject` then
overrides the Service port to `8080` and enables ingress. Argo CD value
precedence is `valuesObject` over `valueFiles` over the chart's `values.yaml`.
Argo CD renders Helm templates but owns the release lifecycle, so this app is
not listed by `helm list`.

### App of apps

```bash
kubectl apply -f bootstrap/fl-root-app.yaml
kubectl get applications -n argocd -l app.kubernetes.io/part-of=fl-app-of-apps
kubectl get all -n fl-dev
kubectl get all -n fl-prod
curl -H 'Host: dev-nginx.fl.local' http://localhost:8081
curl -H 'Host: prod-echo.fl.local' http://localhost:8081
```

The root Application reads child `Application` manifests from
`app-of-apps/children`. Each child points at an environment-specific Kustomize
overlay. The root is an admin-level pattern because changing a child app can
grant broad deployment access; protect changes to that directory with reviews.

## Demonstrate GitOps reconciliation

Change a replica count or image tag, commit, and push. Watch Argo CD reconcile:

```bash
argocd app list
argocd app watch fl-directory-app
```

Then introduce live drift and observe self-healing:

```bash
kubectl scale deployment fl-directory-nginx --replicas=4
kubectl get deployment fl-directory-nginx -w
```

## Validation and troubleshooting

Render everything locally:

```bash
./scripts/validate.sh
```

Useful diagnostics:

```bash
kubectl get applications -n argocd
kubectl describe application -n argocd fl-directory-app
kubectl logs -n argocd deployment/argocd-repo-server
```

An `Unknown` or `ComparisonError` application usually means the repository is
private, the `main` branch has not been pushed, or a source path is wrong. An
Ingress returning `404` usually means its `Host` header does not match.

## Cleanup

Delete individual demos with `kubectl delete -f bootstrap/<file>.yaml`. The
Application finalizers cascade deletion to their managed resources. Delete the
whole lab with:

```bash
kind delete cluster --name fl-gitops
```