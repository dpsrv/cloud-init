#!/bin/bash -ex

dnf install -y oracle-epel-release-el9
dnf config-manager --enable ol9_developer_EPEL

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
	yq \
	unzip \
	swaks \
	testssl \
	httpd-tools

systemctl enable --now crond
