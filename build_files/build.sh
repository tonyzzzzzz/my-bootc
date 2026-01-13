#!/bin/bash

set -ouex pipefail

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
  kernel-modules-extra \
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

sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/bootc update --quiet|' /usr/lib/systemd/system/bootc-fetch-apply-updates.service
sed -i 's|^OnUnitInactiveSec=.*|OnUnitInactiveSec=7d\nPersistent=true|' /usr/lib/systemd/system/bootc-fetch-apply-updates.timer
sed -i 's|#AutomaticUpdatePolicy.*|AutomaticUpdatePolicy=stage|' /etc/rpm-ostreed.conf
# dnf -y config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
# dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable bootc-fetch-apply-updates
# systemctl enable docker
systemctl enable auditd
systemctl enable firewalld
systemctl enable podman.socket
