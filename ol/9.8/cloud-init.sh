#!/bin/bash -ex

cd $(dirname $0)

CLOUD_INIT_D=cloud-init.d

while read script; do
	scriptPath=$CLOUD_INIT_D/$script
	[ -x $scriptPath ] || continue
	$scriptPath
done < <(ls -1 $CLOUD_INIT_D/)
