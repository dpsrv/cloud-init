#!/bin/bash -e

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

metallb_ips=( $ROUTABLE_IPS )
metallb_ips_count=${#metallb_ips[*]}
for (( i=0; i < $metallb_ips_count; i++ )) ; do
	metallb_ip=${ROUTABLE_IPS[$i]}
	svcId=$K8S_NODE_NAME
	[ "$metallb_ips_count" = "1" ] || svcId="$svcId-$i"

	kubectl -n istio-system get svc istio-ingressgateway -o json \
		| jq ".metadata.name = \"istio-ingressgateway-$svcId\" | .spec.loadBalancerIP = \"$metallb_ip\" | del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields, .spec.clusterIP, .spec.clusterIPs, .status) | del(.spec.ports[].nodePort) | del(.spec.healthCheckNodePort)" \
		| kubectl apply -f -

	# Add mail ports if not present
	kubectl -n istio-system get svc istio-ingressgateway-$svcId -o jsonpath='{.spec.ports[*].name}' | grep -q smtp || \
		kubectl -n istio-system patch svc istio-ingressgateway-$svcId --type='json' -p='[
			{"op":"add","path":"/spec/ports/-","value":{"name":"smtp","port":25,"targetPort":8025,"protocol":"TCP"}},
			{"op":"add","path":"/spec/ports/-","value":{"name":"smtps","port":465,"targetPort":8465,"protocol":"TCP"}},
			{"op":"add","path":"/spec/ports/-","value":{"name":"submission","port":587,"targetPort":8587,"protocol":"TCP"}},
			{"op":"add","path":"/spec/ports/-","value":{"name":"imap","port":143,"targetPort":8143,"protocol":"TCP"}},
			{"op":"add","path":"/spec/ports/-","value":{"name":"imaps","port":993,"targetPort":8993,"protocol":"TCP"}}
		]'

done
