#!/bin/bash -ex

SWD=$(dirname $0)

kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=60s

# Wait until IPAddressPool 'default' exists
while ! kubectl get ipaddresspool default -n metallb-system >/dev/null 2>&1; do
    echo "Waiting for IPAddressPool 'default'..."
    sleep 2
done
echo "IPAddressPool 'default' is now present"

metallb_ips=$( echo $ROUTABLE_IPS| tr ' ' '\n' | sed 's/^/\"/;s/$/\/32\",/' | tr -d '\n' | sed 's/,$//')

kubectl -n metallb-system get ipaddresspool default -o json \
	| jq ".spec.addresses += [$metallb_ips] | .spec.addresses |= unique" \
	| kubectl apply -f -
