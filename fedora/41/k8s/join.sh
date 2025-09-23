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

metallb_ips=( $ROUTABLE_IPS )
metallb_ips_count=${#metallb_ips[*]}
for (( i=0; i < $metallb_ips_count; i++ )) ; do
	metallb_ip=${ROUTABLE_IPS[$i]}
	svcId=$K8S_NODE_NAME
	[ "$metallb_ips_count" = "1" ] || svcId="$svcId-$i"

	cat <<_EOT_ | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: istio-ingressgateway-$svcId
  namespace: istio-system
spec:
  type: LoadBalancer
  loadBalancerIP: $metallb_ip
  selector:
    app: istio-ingressgateway
    istio: ingressgateway
  ports:
    - port: 80
      targetPort: 80
    - port: 443
      targetPort: 443
_EOT_

done
