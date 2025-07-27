#!/bin/bash

clusterName="eks-demo"
oidcPem="scripts/oidc.pem"

for arg in \"$@\"
  do
  case $1 in
    --cluster|-c)
      clusterName=$2
    ;;
    --*)
      echo "Unknown option: $1"
      exit 1
    ;;
  esac
  shift
done


oidcProviderUrl=$( aws eks describe-cluster \
  --name demo-eks \
  --query 'cluster.identity.oidc.issuer' \
  --output text )

echo "Below is the OIDC issuer's JWK public key:"

curl $oidcProviderUrl/keys | jq -r '.keys[0]'

echo "You can convert it to PEM encoding via https://8gwifi.org/jwkconvertfunctions.jsp"

read -p "Press ENTER once you've got your PEM encoded OIDC issuer public key..." _

nano $oidcPem

vault policy write $clusterName-policy scripts/vault-policy.hcl

vault auth enable -path=$clusterName-jwt jwt

vault write auth/$clusterName-jwt/role/external-secrets \
  role_type="jwt" \
  bound_audiences=vault \
  bound_issuer=$oidcProviderUrl \
  bound_subject="system:serviceaccount:external-secrets:vault-sa" \
  user_claim="sub" \
  token_policies="$clusterName-policy" \
  token_ttl="1h"

vault write auth/$clusterName-jwt/config \
  jwt_validation_pubkeys=@$oidcPem \
  bound_issuer=$oidcProviderUrl

rm $oidcPem