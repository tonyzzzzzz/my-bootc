#!/usr/bin/env bash

set -xeuo pipefail

# See https://github.com/CentOS/centos-bootc/issues/191
mkdir -p /var/roothome

# Add Flathub to the image for eventual application
mkdir -p /etc/flatpak/remotes.d/
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo

# GO AWAY fedora flatpaks.
rm -rf /usr/lib/systemd/system/flatpak-add-fedora-repos.service
systemctl enable flatpak-add-flathub-repos.service

# Saves a ton of space 6767 :steamhappy:
rm -rf /usr/share/doc

systemctl enable rechunker-group-fix.service

# REQUIRED for dms-greeter to work
tee /usr/lib/sysusers.d/greeter.conf <<'EOF'
g greeter 767
u greeter 767 "Greetd greeter"
EOF

KERNEL_VERSION="$(find "/usr/lib/modules" -maxdepth 1 -type d ! -path "/usr/lib/modules" -exec basename '{}' ';' | sort | tail -n 1)"
export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible --zstd -v --add ostree -f "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
