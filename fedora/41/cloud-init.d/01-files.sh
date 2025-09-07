#!/bin/bash -ex

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
	sudo cp $file $dest
done < <(ls \
	~/.config/git/openssl-* \
	~/.docker-credentials \
	~/.gitconfig \
	~/.git-credentials \
	~/.ssh/id_ed25519*
)
