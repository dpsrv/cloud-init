#!/bin/bash -ex

CLOUD_INIT_D=$(dirname $0)/cloud-init.d

while read script; do
	scriptPath=$CLOUD_INIT_D/$script
	[ -x $scriptPath ] || continue
	$script
done < <(ls -1 $CLOUD_INIT_D/)
