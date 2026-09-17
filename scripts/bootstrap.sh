#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME="fl-gitops"
ARGO_CD_VERSION="v3.5.3"
INGRESS_NGINX_VERSION="controller-v1.15.1"

for command in docker kind kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running." >&2
  exit 1
fi

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config cluster/kind-config.yaml
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGO_CD_VERSION}/manifests/install.yaml"

kubectl apply \
  -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "Cluster and controllers are ready."
echo "Argo CD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
echo
echo "Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"