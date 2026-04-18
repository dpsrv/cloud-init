#!/bin/bash -ex

SWD=$(dirname $0)

[ ! -x /usr/local/bin/k3s-uninstall.sh ] || /usr/local/bin/k3s-uninstall.sh

if [ ! -d /etc/rancher/k3s ]; then
	cp -r $SWD/../files/etc/rancher/k3s /etc/rancher/k3s
fi

export ROUTABLE_IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.)')

export K8S_NODE_NAME=$DPSRV_REGION-$DPSRV_NODE
export K8S_NODES=$(host -t SRV k8s.$DPSRV_DOMAIN | sort -k6r)
export K8S_NODE=$(echo "$K8S_NODES" | grep -n $K8S_NODE_NAME)
export K8S_NODE_ID=$(echo "$K8S_NODE" | cut -d: -f1)
export K8S_NODE_HOST=$(echo "$K8S_NODE" | awk '{ print $8 }'|sed 's/\.$//')
export K8S_NODE_IP=$(getent hosts $K8S_NODE_HOST|awk '{ print $1 }')

groupadd k3s || true

if [ ! -f /usr/local/bin/k3s-install.sh ]; then
	curl --retry 3 --retry-delay 10 -sfL -o /usr/local/bin/k3s-install.sh https://get.k3s.io
	chmod u+x /usr/local/bin/k3s-install.sh
fi

if [ "$K8S_NODE_ID" = "1" ]; then
	echo "Primary node"
	/usr/local/bin/k3s-install.sh server --node-name $K8S_NODE_NAME \
		--cluster-init
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
	/usr/local/bin/k3s-install.sh server --node-name $DPSRV_REGION-$DPSRV_NODE \
		--server https://$primary_name:6443 \
		--token $token 
fi

chmod g+r /etc/rancher/k3s/k3s.yaml
[ -d ~/.kube ] || mkdir -p ~/.kube
cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
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

