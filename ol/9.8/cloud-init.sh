#!/bin/bash -ex

cd $(dirname $0)

# Wrapper for dnf with retry logic for transient failures (lock contention, etc.)
dnf() {
    local retries=5
    while ! command dnf "$@"; do
        ((retries--)) || { echo "dnf failed after retries"; return 1; }
        echo "dnf failed, retrying in 10s... ($retries left)"
        sleep 10
    done
}
export -f dnf

CLOUD_INIT_D=cloud-init.d

while read script; do
	scriptPath=$CLOUD_INIT_D/$script
	[ -x $scriptPath ] || continue
	$scriptPath
done < <(ls -1 $CLOUD_INIT_D/)
