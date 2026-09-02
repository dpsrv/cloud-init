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
	openssl \
	jq \
	cronie \
	crudini \
	htop \
	nload \
	unzip \
	swaks \
	httpd-tools

systemctl enable --now crond

# yq - not in EPEL, install from GitHub
if [ ! -x /usr/local/bin/yq ]; then
	curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_arm64 -o /usr/local/bin/yq
	chmod +x /usr/local/bin/yq
fi

# testssl - not in EPEL, install from GitHub
if [ ! -d /opt/testssl ]; then
	git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl
	ln -s /opt/testssl/testssl.sh /usr/local/bin/testssl
fi
