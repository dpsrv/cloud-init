#!/bin/bash -ex

SWD=$(dirname $0)

[ ! -x /usr/local/bin/k3s-uninstall.sh ] || /usr/local/bin/k3s-uninstall.sh

if [ ! -d /etc/rancher/k3s ]; then
	cp -r $SWD/../files/etc/rancher/k3s /etc/rancher/k3s
fi

export K8S_NODE_NAME=$DPSRV_REGION-$DPSRV_NODE
export K8S_NODES=$(host -t SRV k8s.$DPSRV_DOMAIN | sort -k6r)
export K8S_NODE=$(echo "$K8S_NODES" | grep -n $K8S_NODE_NAME)
export K8S_NODE_ID=$(echo "$K8S_NODE" | cut -d: -f1)
export K8S_NODE_HOST=$(echo "$K8S_NODE" | awk '{ print $8 }'|sed 's/\.$//')
export K8S_NODE_IP=$(getent hosts $K8S_NODE_HOST|awk '{ print $1 }')

if [ "$K8S_NODE_ID" = "1" ]; then
	echo "Primary node"
	curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
		--cluster-cidr=10.244.0.0/16 \
		--node-name $K8S_NODE_NAME \
		--disable traefik,servicelb \
		--disable-cloud-controller
	while true; do
		token=$(cat /var/lib/rancher/k3s/server/node-token || true)
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
		--cluster-cidr=10.244.0.0/16 \
		--token $token \
		--node-name $DPSRV_REGION-$DPSRV_NODE 
fi

chmod g+r /etc/rancher/k3s/k3s.yaml
[ -d ~/.kube ] || mkdir -p ~/.kube
cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
groupadd k3s || true
chgrp k3s /run/k3s/containerd/containerd.sock /etc/rancher/k3s/k3s.yaml

until kubectl get node "$K8S_NODE_NAME" &>/dev/null; do
  echo "Waiting for $K8S_NODE_NAME to join"
  sleep 5
done
kubectl wait --for=condition=Ready node/$K8S_NODE_NAME --timeout=300s
kubectl label node $K8S_NODE_NAME DPSRV_REGION=$DPSRV_REGION --overwrite

if [ "$K8S_NODE_ID" = "1" ]; then
	$SWD/../k8s/init.sh
else
	$SWD/../k8s/join.sh
fi

