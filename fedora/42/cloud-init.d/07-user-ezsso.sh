#!/bin/bash -ex

user=ezsso
user_home=/mnt/data/$user
DPSRV_CFG_SRC_D=${DPSRV_CFG_SRC_D:-/root}

useradd -G docker -d $user_home $user
usermod -aG k3s $user

cp -r $DPSRV_CFG_SRC_D/{.config,.gitconfig,.git-credentials,.docker,.ssh} $user_home/

chown -R $user:$user $user_home/
chmod -R og-rwx $user_home/.ssh/

sudo -u $user ./init-user-projects.sh
