#!/bin/bash -ex

SWD=$(dirname $0)

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

