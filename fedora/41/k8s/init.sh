#!/bin/bash -ex

SWD=$(dirname $0)

kubectl label node $K8S_NODE_NAME local-registry=true --overwrite

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

#kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

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

kubectl apply -f $SWD/gw.yaml
kubectl apply -f $SWD/vs-istiod.yaml

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

kubectl apply -f $SWD/pa-istio-mtls.yaml
kubectl apply -f $SWD/storage.yaml
kubectl apply -f $SWD/registry.yaml

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


