#!/bin/bash -ex

SWD=$(dirname $0)

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

#NERDCTL_VERSION=1.6.0
#curl -LO https://github.com/containerd/nerdctl/releases/download/v$NERDCTL_VERSION/nerdctl-$NERDCTL_VERSION-linux-amd64.tar.gz
#tar Cxzvf /usr/local/bin nerdctl-$NERDCTL_VERSION-linux-amd64.tar.gz

#cat > /etc/profile.d/nerdctl.sh  << _EOT_
#export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
#export XDG_RUNTIME_DIR=/run/user/\$(id -u)
#_EOT_

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

curl -L https://istio.io/downloadIstio | sh -
[ ! -d /opt/istio ] || rm -rf /opt/istio
mv istio-*/ /opt/istio
cat > /etc/profile.d/istio.sh  << _EOT_
export PATH=\$PATH:/opt/istio/bin
_EOT_

. /etc/profile.d/istio.sh

istioctl install --set profile=demo -y

kubectl label namespace default istio-injection=enabled

cat <<_EOT_ | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: default
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*"
    tls:
      mode: SIMPLE
      credentialName: domain-credential
_EOT_

cat <<_EOT_ | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: istio-system
spec:
  hosts:
  - "*"
  gateways:
  - default
  http:
  # Redirect all HTTP traffic to HTTPS
  - match:
    - port: 80
    redirect:
      scheme: https
      port: 443
  # Handle HTTPS traffic normally
  - match:
    - port: 443
    route:
    - destination:
        host: istiod.istio-system.svc.cluster.local
        port:
          number: 15014
_EOT_

metallb_ips=$(
	for ip in $ROUTABLE_IPS; do
		echo "  - $ip-$ip"
	done
)

cat <<_EOT_ | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
$metallb_ips
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: advert
  namespace: metallb-system
_EOT_

cat <<_EOT_ | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system # Or your Istio control plane namespace
spec:
  mtls:
    mode: STRICT
_EOT_


kubectl apply -f $SWD/k8s-registry.yaml

kubectl create namespace dpsrv
kubectl label namespace dpsrv istio-injection=enabled

cat <<_EOT_ | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: dpsrv
  name: dpsrv
data:
  DPSRV_REGION: $DPSRV_REGION
  DPSRV_NODE: '$DPSRV_NODE'
  DPSRV_DOMAIN: $DPSRV_DOMAIN
_EOT_

kubectl -n dpsrv create secret generic git-credentials --from-file=$DPSRV_CFG_SRC_D/.git-credentials --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dpsrv create secret generic git-openssl-salt --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-salt --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dpsrv create secret generic git-openssl-password --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-password --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dpsrv create secret docker-registry dockerhub-dpsrv \
    --docker-server=$(jq -r .ServerURL $DPSRV_CFG_SRC_D/.docker-credentials) \
    --docker-username=$(jq -r .Username $DPSRV_CFG_SRC_D/.docker-credentials) \
    --docker-password=$(jq -r .Secret $DPSRV_CFG_SRC_D/.docker-credentials) \
    --dry-run=client -o yaml | kubectl apply -f -


kubectl create namespace ezsso
kubectl label namespace ezsso istio-injection=enabled

cat <<_EOT_ | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ezsso
  name: dpsrv
data:
  DPSRV_REGION: $DPSRV_REGION
  DPSRV_NODE: '$DPSRV_NODE'
  DPSRV_DOMAIN: $DPSRV_DOMAIN
_EOT_

kubectl -n ezsso create secret generic git-credentials --from-file=$DPSRV_CFG_SRC_D/.git-credentials --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ezsso create secret generic git-openssl-salt --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-salt --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ezsso create secret generic git-openssl-password --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-password --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ezsso create secret docker-registry dockerhub-dpsrv \
    --docker-server=$(jq -r .ServerURL $DPSRV_CFG_SRC_D/.docker-credentials) \
    --docker-username=$(jq -r .Username $DPSRV_CFG_SRC_D/.docker-credentials) \
    --docker-password=$(jq -r .Secret $DPSRV_CFG_SRC_D/.docker-credentials) \
    --dry-run=client -o yaml | kubectl apply -f -


