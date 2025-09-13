#!/bin/bash -ex

SWD=$(dirname $0)

[ ! -x /usr/local/bin/k3s-uninstall.sh ] || /usr/local/bin/k3s-uninstall.sh

K8S_NODE_NAME=$DPSRV_REGION-$DPSRV_NODE
K8S_NODES=$(host -t SRV k8s.$DPSRV_DOMAIN | sort -k6r)
K8S_NODE=$(echo "$K8S_NODES" | grep -n $K8S_NODE_NAME)
K8S_NODE_ID=$(echo "$K8S_NODE" | cut -d: -f1)
K8S_NODE_HOST=$(echo "$K8S_NODE" | awk '{ print $8 }'|sed 's/\.$//')
K8S_NODE_IP=$(getent hosts $K8S_NODE_HOST|awk '{ print $1 }')

[ -d /etc/rancher/k3s ] || mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml << _EOT_
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"

configs:
  "localhost:5000":
    tls:
      insecure_skip_verify: true
_EOT_


if [ "$K8S_NODE_ID" = "1" ]; then
	echo "Primary node"
	curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
		--node-name $K8S_NODE_NAME \
		--disable traefik,servicelb,local-storage,metrics-server 
	while true; do
		token=$(cat /var/lib/rancher/k3s/server/node-token)
		[ -z "$token" ] || break
		echo "Waiting for token"
		sleep 5
	done
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
		--node-name $DPSRV_REGION-$DPSRV_NODE 
fi

chmod g+r /etc/rancher/k3s/k3s.yaml
#[ -d ~/.kube ] || mkdir -p ~/.kube
#cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
groupadd k3s || true
chgrp k3s /run/k3s/containerd/containerd.sock /etc/rancher/k3s/k3s.yaml

if [ "$K8S_NODE_ID" = "1" ]; then
	$SWD/../k8s-init.sh
fi

