#!/bin/bash -ex

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

