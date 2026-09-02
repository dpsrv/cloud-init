#!/bin/bash -ex

# Ensure /usr/local/bin is in PATH for all users
if ! grep -q '/usr/local/bin' /etc/profile.d/local-path.sh 2>/dev/null; then
	echo 'export PATH=$PATH:/usr/local/bin' > /etc/profile.d/local-path.sh
fi

while read source; do
	target=${source#files}
	targetDir=${target%/*}
	[ -x $targetDir ] || mkdir -p $targetDir
	cp $source $target
done < <( find files -type f )

# Copy to root
while read file; do
	dest=~root/${file#$HOME/}
	[ ! -e $dest ] || continue
	destDir=$(dirname $dest)
	[ -d $destDir ] || sudo mkdir -p $destDir
	sudo cp -p $file $dest
done < <(ls \
	~/.config/git/openssl-* \
	~/.docker-credentials \
	~/.gitconfig \
	~/.git-credentials \
	~/.ssh/id_ed25519*
)
