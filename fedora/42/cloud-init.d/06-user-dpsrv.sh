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

sudo -u $user ./init-user-projects.sh

chmod a+rx $user_home/
chmod -R a+r $user_home/rc/

find $user_home/rc/ -type d -exec chmod a+x {} \;
