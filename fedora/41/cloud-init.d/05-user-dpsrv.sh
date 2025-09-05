#!/bin/bash -ex

user=dpsrv
user_home=/mnt/data/$user
DPSRV_CFG_SRC_D=${DPSRV_CFG_SRC_D:-/root}

useradd -G docker -d $user_home $user
usermod -aG k3s $user

mkdir -p $user_home/.ssh

cp $DPSRV_CFG_SRC_D/.ssh/authorized_keys $user_home/.ssh/
chmod -R og-rwx $user_home/.ssh/

cp -r $DPSRV_CFG_SRC_D/{.config,.gitconfig,.git-credentials} $user_home/

chown -R $user:$user $user_home/

docker network create $user

kubectl create namespace $user
kubectl label namespace $user istio-injection=enabled

cat <<_EOT_ | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: $user
  name: dpsrv
data:
  DPSRV_REGION: $DPSRV_REGION
  DPSRV_NODE: '$DPSRV_NODE'
  DPSRV_DOMAIN: $DPSRV_DOMAIN
_EOT_

kubectl -n $user create secret generic git-credentials --from-file=$DPSRV_CFG_SRC_D/.git-credentials
kubectl -n $user create secret generic git-openssl-salt --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-salt
kubectl -n $user create secret generic git-openssl-password --from-file=$DPSRV_CFG_SRC_D/.config/git/openssl-password
kubectl -n $user create secret docker-registry dockerhub-dpsrv \
  --docker-server=$(jq -r .ServerURL $DPSRV_CFG_SRC_D/.docker-credentials) \
  --docker-username=$(jq -r .Username $DPSRV_CFG_SRC_D/.docker-credentials) \
  --docker-password=$(jq -r .Secret $DPSRV_CFG_SRC_D/.docker-credentials)

sudo -u $user ./init-user-projects.sh

chmod a+rx $user_home/
chmod -R a+r $user_home/rc/

find $user_home/rc/ -type d -exec chmod a+x {} \;
