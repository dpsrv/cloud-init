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
chmod go+r /etc/rancher/k3s/k3s.yaml
cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
groupadd k3s
chgrp k3s /run/k3s/containerd/containerd.sock

#NERDCTL_VERSION=1.6.0
#curl -LO https://github.com/containerd/nerdctl/releases/download/v$NERDCTL_VERSION/nerdctl-$NERDCTL_VERSION-linux-amd64.tar.gz
#tar Cxzvf /usr/local/bin nerdctl-$NERDCTL_VERSION-linux-amd64.tar.gz

cat > /etc/profile.d/nerdctl.sh  << _EOT_
export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
_EOT_

curl -L https://istio.io/downloadIstio | sh -
mv istio-*/ /opt/istio
cat > /etc/profile.d/istio.sh  << _EOT_
export PATH=\$PATH:/opt/istio/bin
_EOT_
istioctl install --set profile=demo -y

kubectl create namespace dpsrv

kubectl label namespace default istio-injection=enabled
kubectl label namespace dpsrv istio-injection=enabled

kubectl -n dpsrv create secret generic git-credentials --from-file=$DPSRV_CFG_SRC_D/.git-credentials
kubectl -n dpsrv create secret generic git-openssl-salt --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-salt
kubectl -n dpsrv create secret generic git-openssl-password --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-password

