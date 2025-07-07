#!/bin/bash -ex
user=$USER

user_home=/mnt/data/$user
cd $user_home

gpgconf -K keyboxd
gpg --pinentry-mode=loopback --quick-gen-key --batch --passphrase '' $(git config user.email)
git config --global user.signingkey $(gpg --list-keys --with-colons|grep -A 1 ^pub|grep ^fpr|cut -d: -f10)

git config --global credential.helper store

if [ ! -d git-openssl-secrets ]; then
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
	fi

	echo ". $user_home/rc/bin/$user.sh" > $user_home/.bashrc.d/01-$user.sh
fi

if [ "$user" != "dpsrv" ]; then
	. /mnt/data/dpsrv/rc/bin/dpsrv.sh
fi
. rc/bin/$user.sh

$user-git-clone
$user-git-init-secrets

while ! systemctl is-active docker; do
	echo "Waiting for docker service to become active ($?)."
	sleep 2
done

$user-up

