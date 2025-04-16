#!/bin/bash -ex

user=ezsso
user_home=/mnt/data/$user

useradd -G docker -d $user_home $user

mkdir -p $user_home/.ssh

cp /root/.ssh/authorized_keys $user_home/.ssh/
chmod -R og-rwx $user_home/.ssh/

cp -r ~root/{.config,.gitconfig,.git-credentials} $user_home/

chown -R $user:$user $user_home/

sudo -u $user init-user-projects.sh
