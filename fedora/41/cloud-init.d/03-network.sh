#!/bin/bash -ex

if [ -n "$FLOATING_IP_IF" ]; then
	resolved=$(host "$(hostname -s).dpsrv.me")
	if floating_ip=$(echo "$resolved"|awk '{ print $4 }'); then
	
    	if ! ip a s | grep -q $floating_ip; then
        	ip addr add $floating_ip dev $FLOATING_IP_IF
    	fi
	
	fi
fi

