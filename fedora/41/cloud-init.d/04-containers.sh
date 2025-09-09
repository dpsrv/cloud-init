#!/bin/bash -ex

export ROUTABLE_IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.)')

dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo || true
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin etcd

ln -s /mnt/data/dpsrv/rc/secrets/letsencrypt /etc/letsencrypt

[ -d /mnt/docker-data ] || mkdir /mnt/docker-data

cat >> /etc/docker/daemon.json << _EOT_
{
	"data-root": "/mnt/docker-data",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
_EOT_

systemctl --now enable docker

(
	while ! systemctl is-active docker; do
    	echo "Waiting for docker service to become active ($?)."
    	sleep 2
	done
) &

# /usr/local/bin/k3s-uninstall.sh
(set -x

K8S_NODE_NAME=$DPSRV_REGION-$DPSRV_NODE
K8S_NODES=$(host -t SRV k8s.$DPSRV_DOMAIN | sort -k6r)
K8S_NODE=$(echo "$K8S_NODES" | grep -n $K8S_NODE_NAME)
K8S_NODE_ID=$(echo "$K8S_NODE" | cut -d: -f1)
K8S_NODE_HOST=$(echo "$K8S_NODE" | awk '{ print $8 }'|sed 's/\.$//')
K8S_NODE_IP=$(getent hosts $K8S_NODE_HOST|awk '{ print $1 }')

tls_sans=$(
	for ip in $ROUTABLE_IPS; do
		echo "--tls-san $ip"
	done
	[[ "$ROUTABLE_IPS" =~ $K8S_NODE_IP ]] || echo "--tls-san $K8S_NODE_IP"
	echo "--tls-san $K8S_NODE_HOST"
	echo "--tls-san 127.0.0.1"
	echo "--tls-san $K8S_NODE_NAME"
)

if [ "$K8S_NODE_ID" = "1" ]; then
	echo "Primary node"
	curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
		--node-name $K8S_NODE_NAME \
		--node-ip $K8S_NODE_IP \
		--advertise-address $K8S_NODE_IP \
		$tls_sans \
		--disable traefik,servicelb,local-storage,metrics-server 
else
	echo "Secondary node"
	primary_host=$(echo "$K8S_NODES"|head -1|awk '{ print $8 }')
	primary_name=${primary_host%.$DPSRV_DOMAIN*}
	token=
	while true; do
		token=$(ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host sudo cat /var/lib/rancher/k3s/server/node-token)
		[ -z "$token" ] || break
		echo "Waiting on $primary_host for token"
		sleep 5
	done
	curl -sfL https://get.k3s.io | sh -s - server \
		--server https://$primary_name:6443 \
		--token $token \
		--node-name $DPSRV_REGION-$DPSRV_NODE \
		--node-ip $K8S_NODE_IP \
		--advertise-address $DPSRV_REGION-$DPSRV_NODE \
		$tls_sans \
		--debug
fi
)

chmod go+r /etc/rancher/k3s/k3s.yaml
[ -d ~/.kube ] || mkdir -p ~/.kube
cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
groupadd k3s || true
chgrp k3s /run/k3s/containerd/containerd.sock

#NERDCTL_VERSION=1.6.0
#curl -LO https://github.com/containerd/nerdctl/releases/download/v$NERDCTL_VERSION/nerdctl-$NERDCTL_VERSION-linux-amd64.tar.gz
#tar Cxzvf /usr/local/bin nerdctl-$NERDCTL_VERSION-linux-amd64.tar.gz

#cat > /etc/profile.d/nerdctl.sh  << _EOT_
#export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
#export XDG_RUNTIME_DIR=/run/user/\$(id -u)
#_EOT_

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

curl -L https://istio.io/downloadIstio | sh -
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

