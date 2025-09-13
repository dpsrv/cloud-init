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

$SWD/../k3s-install.sh
if [ "$K8S_NODE_ID" = "1" ]; then
	$SWD/../k8s-init.sh
fi

