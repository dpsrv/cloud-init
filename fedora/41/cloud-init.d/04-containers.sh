#!/bin/bash -ex

SWD=$(diranem $0)

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

K8S_NODE_NAME=$DPSRV_REGION-$DPSRV_NODE
K8S_NODES=$(host -t SRV k8s.$DPSRV_DOMAIN | sort -k6r)
K8S_NODE=$(echo "$K8S_NODES" | grep -n $K8S_NODE_NAME)
K8S_NODE_ID=$(echo "$K8S_NODE" | cut -d: -f1)
K8S_NODE_HOST=$(echo "$K8S_NODE" | awk '{ print $8 }'|sed 's/\.$//')
K8S_NODE_IP=$(getent hosts $K8S_NODE_HOST|awk '{ print $1 }')

[ -d /etc/rancher/k3s ] || mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml << _EOT_
mirrors:
  "registry.local:5000":
    endpoint:
      - "http://registry.registry.svc.cluster.local:5000"
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

chmod go+r /etc/rancher/k3s/k3s.yaml
[ -d ~/.kube ] || mkdir -p ~/.kube
cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
groupadd k3s || true
chgrp k3s /run/k3s/containerd/containerd.sock

if [ "$K8S_NODE_ID" = "1" ]; then
	$SWD/../k8s-init.sh
fi

