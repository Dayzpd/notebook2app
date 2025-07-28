#!/bin/bash

clusterName="spotlab"
proxyPort="8001"
newVault="n"
oidcProviderUrl="https://kubernetes.default.svc.cluster.local"
oidcPem="scripts/oidc.pem"

for arg in \"$@\"
  do
  case $1 in
    --cluster|-c)
      clusterName=$2
    ;;
    --proxy-port|-p)
      proxyPort=$2
    ;;
    --new-vault|-n)
      newVault="y"
    ;;
    --*)
      echo "Unknown option: $1"
      exit 1
    ;;
  esac
  shift
done

kubectl proxy --port=$proxyPort &

sleep 1

echo "Below is the OIDC issuer's JWK public key:"

curl -s -k http://localhost:$proxyPort/openid/v1/jwks | jq -r '.keys[0]'

echo "You can convert it to PEM encoding via https://8gwifi.org/jwkconvertfunctions.jsp"

read -p "Press ENTER once you've got your PEM encoded OIDC issuer public key..." _

fuser -k $proxyPort/tcp

nano $oidcPem

if [ $newVault = "y" ]; then

  vault secrets enable -path=$clusterName-kv -version=2 kv

  vault policy write $clusterName-policy scripts/$clusterName-vault-policy.hcl

  vault auth enable -path=$clusterName-jwt jwt

fi

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