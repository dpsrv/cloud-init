#!/bin/bash -ex

SWD=$(dirname $0)

kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=60s

# Wait until IPAddressPool 'default' exists
while ! kubectl get ipaddresspool default -n metallb-system >/dev/null 2>&1; do
    echo "⏳ Waiting for IPAddressPool 'default'..."
    sleep 2
done
echo "IPAddressPool 'default' is now present"


