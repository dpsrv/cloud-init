#!/bin/bash -ex
user=$USER

user_home=/mnt/data/$user
cd $user_home

git config --global credential.helper store

git clone https://github.com/maxfortun/git-openssl-secrets.git

cd git-openssl-secrets
ln -s git-setenv-openssl-secrets-fs.sh git-setenv-openssl-secrets.sh
cd ..

git clone https://github.com/$user/rc.git
cd rc
../git-openssl-secrets/git-init-openssl-secrets.sh
cd ..

mkdir $user_home/.bashrc.d

if [ "$user" != "dpsrv" ]; then
	echo ". /mnt/data/dpsrv/rc/bin/dpsrv.sh" > $user_home/.bashrc.d/00-dpsrv.sh
	. /mnt/data/dpsrv/rc/bin/dpsrv.sh
fi

echo ". $user_home/rc/bin/$user.sh" > $user_home/.bashrc.d/01-$user.sh
. rc/bin/$user.sh

$user-git-clone
$user-git-init-secrets

while ! systemctl is-active docker; do
	echo "Waiting for docker service to become active ($?)."
	sleep 2
done

$user-up

