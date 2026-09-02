#!/bin/bash -ex

export PATH=$PATH:/usr/local/bin

SWD=$(dirname $0)

[ ! -x /usr/local/bin/k3s-uninstall.sh ] || /usr/local/bin/k3s-uninstall.sh
[ ! -x /usr/local/bin/k3s-agent-uninstall.sh ] || /usr/local/bin/k3s-agent-uninstall.sh
rm -rf /etc/rancher/k3s /etc/rancher/node /var/lib/rancher/k3s

# Get routable IPs from interface (works on Contabo where public IP is on interface)
export ROUTABLE_IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.)')

export K8S_NODE_NAME=$DPSRV_REGION-$DPSRV_NODE
export K8S_NODES=$(host -t SRV k8s.$DPSRV_DOMAIN | sort -k6r)
export K8S_NODE=$(echo "$K8S_NODES" | grep -n $K8S_NODE_NAME)
export K8S_NODE_ID=$(echo "$K8S_NODE" | cut -d: -f1)
export K8S_NODE_HOST=$(echo "$K8S_NODE" | awk '{ print $8 }'|sed 's/\.$//')
# Get public IP from DNS (works even behind NAT like Oracle Cloud)
export K8S_NODE_IP=$(host $K8S_NODE_HOST | grep -oP '(?<=has address )\d+(\.\d+){3}' | head -1)

# For NAT environments (Oracle Cloud), use DNS-resolved IP as routable
if [ -z "$ROUTABLE_IPS" ] && [ -n "$K8S_NODE_IP" ]; then
	export ROUTABLE_IPS=$K8S_NODE_IP
fi

groupadd k3s || true

if [ ! -f /usr/local/bin/k3s-install.sh ]; then
	curl --retry 3 --retry-delay 10 -sfL -o /usr/local/bin/k3s-install.sh https://get.k3s.io
	chmod u+x /usr/local/bin/k3s-install.sh
fi

if [ "$K8S_NODE_ID" = "1" ]; then
	echo "Primary node"
	# Copy server config for primary
	if [ ! -d /etc/rancher/k3s ]; then
		cp -r $SWD/../files/etc/rancher/k3s /etc/rancher/k3s
	fi
	/usr/local/bin/k3s-install.sh server --node-name $K8S_NODE_NAME \
		--node-external-ip $K8S_NODE_IP \
		--cluster-init
	while true; do
		token=$(cat /var/lib/rancher/k3s/server/node-token || true)
		[ -z "$token" ] || break
		echo "Waiting for token"
		sleep 5
	done
else
	echo "Secondary node"
	primary_host=$(echo "$K8S_NODES"|head -1|awk '{ print $8 }' | sed 's/\.$//')
	primary_name=${primary_host%.$DPSRV_DOMAIN*}

	# Detect NAT environment (public IP not on interface)
	if [ -z "$(ip -4 addr show | grep "$K8S_NODE_IP")" ]; then
		echo "NAT environment detected - joining as agent (worker)"
		K3S_MODE=agent
	else
		echo "Direct IP detected - joining as server"
		K3S_MODE=server
	fi

	token=
	while true; do
		token=$(ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host sudo cat /var/lib/rancher/k3s/server/node-token) || true
		[ -z "$token" ] || break
		echo "Waiting on $primary_host for token"
		sleep 5
	done

	# Get k3s version from primary to ensure compatibility
	export INSTALL_K3S_VERSION=$(ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host k3s --version | head -1 | awk '{print $3}')
	echo "Installing k3s version $INSTALL_K3S_VERSION to match primary"

	# Remove stale node entry from cluster (from previous instance)
	echo "Removing any stale node entry for $K8S_NODE_NAME"
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host "kubectl delete node $K8S_NODE_NAME 2>/dev/null" || true

	if [ "$K3S_MODE" = "server" ]; then
		# Remove any existing etcd member for this node before joining
		stale_members=$(ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host "docker run --rm \
			-v /var/lib/rancher/k3s/server/tls/etcd:/certs:ro \
			--network host \
			quay.io/coreos/etcd:v3.5.9 etcdctl \
			--endpoints=https://127.0.0.1:2379 \
			--cacert=/certs/server-ca.crt \
			--cert=/certs/client.crt \
			--key=/certs/client.key \
			member list 2>/dev/null" | grep -i "$K8S_NODE_NAME" || true)

		if [ -n "$stale_members" ]; then
			echo "$stale_members" | while read member; do
				member_id=$(echo "$member" | cut -d',' -f1 | tr -d ' ')
				echo "Removing existing etcd member $member_id for $K8S_NODE_NAME"
				ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host "docker run --rm \
					-v /var/lib/rancher/k3s/server/tls/etcd:/certs:ro \
					--network host \
					quay.io/coreos/etcd:v3.5.9 etcdctl \
					--endpoints=https://127.0.0.1:2379 \
					--cacert=/certs/server-ca.crt \
					--cert=/certs/client.crt \
					--key=/certs/client.key \
					member remove $member_id 2>/dev/null" || true
			done
		fi

		# Copy server config for secondary server
		if [ ! -d /etc/rancher/k3s ]; then
			cp -r $SWD/../files/etc/rancher/k3s /etc/rancher/k3s
		fi
		/usr/local/bin/k3s-install.sh server --node-name $DPSRV_REGION-$DPSRV_NODE \
			--node-ip $K8S_NODE_IP \
			--node-external-ip $K8S_NODE_IP \
			--advertise-address $K8S_NODE_IP \
			--server https://$primary_name:6443 \
			--token $token
	else
		/usr/local/bin/k3s-install.sh agent --node-name $DPSRV_REGION-$DPSRV_NODE \
			--node-external-ip $K8S_NODE_IP \
			--server https://$primary_name:6443 \
			--token $token
	fi
fi

# Server nodes have k3s.yaml, agents don't
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
	chmod g+r /etc/rancher/k3s/k3s.yaml
	[ -d ~/.kube ] || mkdir -p ~/.kube
	cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
	chgrp k3s /etc/rancher/k3s/k3s.yaml
fi

[ -S /run/k3s/containerd/containerd.sock ] && chgrp k3s /run/k3s/containerd/containerd.sock || true

# For agents, fetch kubeconfig from primary
if [ "$K3S_MODE" = "agent" ]; then
	[ -d ~/.kube ] || mkdir -p ~/.kube
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $primary_host sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
	sed -i "s/127.0.0.1/$primary_name/g" ~/.kube/config
	export KUBECONFIG=~/.kube/config
fi

until kubectl get node "$K8S_NODE_NAME" &>/dev/null; do
  echo "Waiting for $K8S_NODE_NAME to join"
  sleep 5
done
kubectl wait --for=condition=Ready node/$K8S_NODE_NAME --timeout=300s
kubectl label node $K8S_NODE_NAME DPSRV_REGION=$DPSRV_REGION --overwrite

# For NAT environments, fix flannel public-ip annotation to use external IP
if [ "$K3S_MODE" = "agent" ] && [ -n "$K8S_NODE_IP" ]; then
	current_flannel_ip=$(kubectl get node $K8S_NODE_NAME -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip}')
	if [ "$current_flannel_ip" != "$K8S_NODE_IP" ]; then
		echo "Fixing flannel public-ip annotation: $current_flannel_ip -> $K8S_NODE_IP"
		kubectl annotate node $K8S_NODE_NAME flannel.alpha.coreos.com/public-ip=$K8S_NODE_IP --overwrite
	fi
fi

if [ "$K8S_NODE_ID" = "1" ]; then
	$SWD/../k8s/init.sh
else
	$SWD/../k8s/join.sh
fi

