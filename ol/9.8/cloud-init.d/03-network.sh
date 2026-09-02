#!/bin/bash -ex

# Open k3s required ports in firewalld
if systemctl is-active --quiet firewalld; then
	firewall-cmd --permanent --add-port=6443/tcp      # Kubernetes API
	firewall-cmd --permanent --add-port=2379-2380/tcp # etcd
	firewall-cmd --permanent --add-port=10250/tcp     # Kubelet API
	firewall-cmd --permanent --add-port=8472/udp      # Flannel VXLAN
	firewall-cmd --permanent --add-port=51820/udp     # Flannel Wireguard
	firewall-cmd --permanent --add-port=51821/udp     # Flannel Wireguard IPv6
	firewall-cmd --reload
fi

if [ -n "$FLOATING_IP_IF" ]; then
	resolved=$(host "$(hostname -s).dpsrv.me")
	if floating_ip=$(echo "$resolved"|awk '{ print $4 }'); then

    	if ! ip a s | grep -q $floating_ip; then
        	ip addr add $floating_ip dev $FLOATING_IP_IF
    	fi

	fi
fi

# Oracle Linux 9 uses NetworkManager instead of systemd-resolved
# Set search domain via NetworkManager
primary_conn=$(nmcli -t -f NAME,DEVICE c show --active | head -1 | cut -d: -f1)
if [ -n "$primary_conn" ]; then
	nmcli c mod "$primary_conn" ipv4.dns-search "$DPSRV_DOMAIN"
	nmcli c up "$primary_conn"
fi

