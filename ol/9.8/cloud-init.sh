#!/bin/bash -ex

cd $(dirname $0)

# Wrapper for dnf with retry logic for transient failures (lock contention, etc.)
dnf() {
    local retries=5
    local output
    while true; do
        output=$(command dnf "$@" 2>&1) && { echo "$output"; return 0; }
        # Don't retry if package not found - that's not transient
        if echo "$output" | grep -q "No match for argument"; then
            echo "$output"
            return 1
        fi
        ((retries--)) || { echo "$output"; echo "dnf failed after retries"; return 1; }
        echo "dnf failed (transient), retrying in 10s... ($retries left)"
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
