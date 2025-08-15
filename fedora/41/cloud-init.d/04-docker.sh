#!/bin/bash -ex

dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo || true
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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

	docker network create dpsrv
) &

curl -sfL https://get.k3s.io | sh -

curl -L https://istio.io/downloadIstio | sh -
mv istio-*/ /opt/istio
cat > /etc/profile.d/istio.sh  << _EOT_
export PATH=\$PATH:/opt/istio/bin
_EOT_

