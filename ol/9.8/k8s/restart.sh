#!/bin/bash -ex

systemctl restart k3s

kubectl -n istio-system rollout restart deploy istiod

