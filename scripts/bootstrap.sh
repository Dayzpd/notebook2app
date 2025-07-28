#!/bin/bash

for arg in \"$@\"
  do
  case $1 in
    --context|-c)
      kubeconfigContext=$2
    ;;
    --apps|-a)
      appsFolder=$2
    ;;
    --*)
      echo "Unknown option: $1"
      exit 1
    ;;
  esac
  shift
done

set -e

function installESOBase() {

  esoBase="components/external-secrets/base"

  kustomize build --enable-helm $esoBase | kubectl apply --server-side -f - 

  kubectl wait --timeout=120s -n external-secrets --for=condition=Available=True Deployment/external-secrets
  kubectl wait --timeout=120s -n external-secrets --for=condition=Available=True Deployment/external-secrets-cert-controller
  kubectl wait --timeout=120s -n external-secrets --for=condition=Available=True Deployment/external-secrets-webhook
  kubectl wait --timeout=120s -n external-secrets --for=condition=Ready pod -l app.kubernetes.io/name=external-secrets

}

function installArgoCDBase() {

  argocdBase="components/argocd/base"

  kubectl apply --force-conflicts --server-side -k $argocdBase

  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-applicationset-controller
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-dex-server
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-notifications-controller
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-redis
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-repo-server
  kubectl wait --timeout=120s -n argocd --for=condition=Available=True Deployment/argocd-server
  kubectl wait --timeout=120s -n argocd --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller

}


function installBootstrapApplication() {

  kubectl apply --server-side -f apps/$appsFolder/bootstrap.yaml

}

function main() {

  kubectl config use-context $kubeconfigContext

  echo "Bootstrapping cluster..."

  echo "Installing ESO..."
  installESOBase

  echo "Installing ArgoCD..."
  installArgoCDBase

  echo "Install bootstrap app..."
  installBootstrapApplication

}

main