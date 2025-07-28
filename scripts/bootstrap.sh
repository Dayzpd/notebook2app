#!/bin/bash

set -e

function installESOBase() {

  argocdBase="components/external-secrets/base"

  kubectl apply --server-side -k $argocdBase

  kubectl wait --timeout=120s -n external-secrets --for=condition=Available=True Deployment/external-secrets
  kubectl wait --timeout=120s -n external-secrets --for=condition=Available=True Deployment/external-secrets-cert-controller
  kubectl wait --timeout=120s -n external-secrets --for=condition=Available=True Deployment/external-secrets-webhook
  kubectl wait --timeout=120s -n external-secrets --for=condition=Ready pod -l app.kubernetes.io/name=external-secrets

}

function installArgoCDBase() {

  argocdBase="components/argocd/base"

  kubectl apply --server-side -k $argocdBase

  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-applicationset-controller
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-dex-server
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-notifications-controller
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-redis
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-repo-server
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-server
  kubectl wait --timeout=120s -n argocd --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller

}


function installBootstrapApplication() {

  kubectl apply --server-side -f apps/bootstrap.yaml

}

function main() {

  echo "Bootstrapping cluster..."

  echo "Installing ESO..."
  installESOBase

  echo "Installing ArgoCD..."
  installArgoCDBase

  echo "Install bootstrap app..."
  installBootstrapApplication

}

main