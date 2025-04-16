#!/bin/bash -ex

resolved=$(host "$(hostname -s).dpsrv.me")
if floating_ip=$(echo "$resolved"|awk '{ print $4 }'); then

    if ! ip a s | grep -q $floating_ip; then
        ip addr add $floating_ip dev eth0
    fi

fi

