#!/bin/bash

set -ouex pipefail

### SELinux policy store: force it into the container's writable layer
#
# On the CI runner /etc/selinux comes from a lower overlayfs layer, and
# rename() between layers returns EXDEV. libsemanage falls back to a
# non-atomic copy, leaves tmp/ and previous/ behind, and then EVERY later
# `semodule` fails with "Error while renaming tmp to active (Directory not
# empty)". That silently drops policy modules installed by %post scriptlets --
# greetd-selinux and swtpm-selinux both hit this -- because dnf only warns
# about failing scriptlets. It is invisible unless you read the build log.
#
# Copying the tree in place puts it entirely in the upper layer so all
# subsequent renames are same-device. Cheap, and a no-op on a local build
# where /etc/selinux is already writable.
if [ -d /etc/selinux ]; then
    rm -rf /etc/selinux/targeted/tmp /etc/selinux/targeted/previous
    cp -a /etc/selinux /etc/selinux.copyup
    rm -rf /etc/selinux
    mv /etc/selinux.copyup /etc/selinux
fi

### Install packages

systemctl enable systemd-timesyncd
systemctl enable systemd-resolved.service

dnf -y install 'dnf5-command(config-manager)'

dnf -y remove \
  console-login-helper-messages \
  chrony \
  sssd* \
  qemu-user-static* \
  toolbox

dnf -y install \
  -x PackageKit* \
  NetworkManager \
  NetworkManager-adsl \
  NetworkManager-bluetooth \
  NetworkManager-config-connectivity-fedora \
  NetworkManager-libnm \
  NetworkManager-openconnect \
  NetworkManager-openvpn \
  NetworkManager-strongswan \
  NetworkManager-ssh \
  NetworkManager-ssh-selinux \
  NetworkManager-vpnc \
  NetworkManager-wifi \
  NetworkManager-wwan \
  alsa-firmware \
  alsa-sof-firmware \
  alsa-tools-firmware \
  atheros-firmware \
  audispd-plugins \
  audit \
  brcmfmac-firmware \
  cifs-utils \
  cups \
  cups-pk-helper \
  dymo-cups-drivers \
  firewalld \
  fprintd \
  fprintd-pam \
  wget \
  fuse \
  fuse-common \
  fwupd \
  gum \
  gvfs-archive \
  gvfs-mtp \
  gvfs-nfs \
  gvfs-smb \
  hplip \
  hyperv-daemons \
  ibus \
  ifuse \
  intel-audio-firmware \
  iwlegacy-firmware \
  iwlwifi-dvm-firmware \
  iwlwifi-mvm-firmware \
  jmtpfs \
  libcamera{,-{v4l2,gstreamer,tools}} \
  libimobiledevice \
  libimobiledevice-utils \
  libratbag-ratbagd \
  man-db \
  man-pages \
  mobile-broadband-provider-info \
  mt7xxx-firmware \
  nxpwireless-firmware \
  openconnect \
  pam_yubico \
  pcsc-lite \
  plymouth \
  plymouth-system-theme \
  printer-driver-brlaser \
  ptouch-driver \
  realtek-firmware \
  rsync \
  spice-vdagent \
  steam-devices \
  switcheroo-control \
  system-config-printer-libs \
  system-config-printer-udev \
  systemd-container \
  systemd-oomd-defaults \
  tiwilink-firmware \
  tuned \
  tuned-ppd \
  unzip \
  usb_modeswitch \
  uxplay \
  vpnc \
  whois \
  wireguard-tools \
  zram-generator-defaults

# Pin to the kernel already in the base image. Unpinned, this can drag in a
# second kernel, and the nvidia akmod would then be built against the wrong one.
KERNEL_NEVRA="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' kernel-core)"
dnf -y install "kernel-modules-extra-${KERNEL_NEVRA}"

sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/bootc update --quiet|' /usr/lib/systemd/system/bootc-fetch-apply-updates.service
sed -i 's|^OnUnitInactiveSec=.*|OnUnitInactiveSec=7d\nPersistent=true|' /usr/lib/systemd/system/bootc-fetch-apply-updates.timer
sed -i 's|#AutomaticUpdatePolicy.*|AutomaticUpdatePolicy=stage|' /etc/rpm-ostreed.conf
# dnf -y config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
# dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# The .timer, not the .service. bootc-fetch-apply-updates.service is static
# (no [Install] section), so `systemctl enable bootc-fetch-apply-updates`
# printed "unit files have no installation config", exited 0, and enabled
# nothing -- unattended updates were never actually scheduled.
systemctl enable bootc-fetch-apply-updates.timer
# systemctl enable docker
systemctl enable auditd
systemctl enable firewalld
systemctl enable podman.socket
