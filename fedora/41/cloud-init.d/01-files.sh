#!/bin/bash -ex

while read source; do
	target=${source#files}
	targetDir=${target%/*}
	[ -x $targetDir ] || mkdir -p $targetDir
	cp $source $target
done < <( find files -type f )
