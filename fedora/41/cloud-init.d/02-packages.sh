#!/bin/bash -ex

dnf install -y \
	dnf-plugins-core \
	net-tools \
	bind-utils \
	nfs-utils \
	nc \
	bzip2 \
	tcpdump \
	tmux \
	colorized-logs \
	openssl \
	jq \
	cronie \
	crudini \
	htop \
	nload \
	yq

systemctl enable --now crond
