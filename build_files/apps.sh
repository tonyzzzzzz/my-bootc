#!/bin/bash

set -xeuo pipefail

# NIRI install
dnf -y copr enable yalter/niri-git
dnf -y copr disable yalter/niri-git
echo "priority=1" | tee -a /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:yalter:niri-git.repo
dnf -y --enablerepo copr:copr.fedorainfracloud.org:yalter:niri-git \
  install --setopt=install_weak_deps=False \
  niri
rm -rf /usr/share/doc/niri

# Quickshell install
dnf -y copr enable avengemedia/danklinux
dnf -y copr disable avengemedia/danklinux
dnf -y --enablerepo copr:copr.fedorainfracloud.org:avengemedia:danklinux install quickshell-git

# DMS Install
dnf -y copr enable avengemedia/dms-git
dnf -y copr disable avengemedia/dms-git
dnf -y \
  --enablerepo copr:copr.fedorainfracloud.org:avengemedia:dms-git \
  --enablerepo copr:copr.fedorainfracloud.org:avengemedia:danklinux \
  install --setopt=install_weak_deps=False \
  dms \
  dms-cli \
  dms-greeter \
  dgop \
  dsearch

dnf -y install \
  brightnessctl \
  cava \
  chezmoi \
  ddcutil \
  fastfetch \
  fcitx5-chinese-addons \
  flatpak \
  fpaste \
  fzf \
  git-core \
  glycin-thumbnailer \
  gnome-disk-utility \
  gnome-keyring \
  gnome-keyring-pam \
  greetd \
  greetd-selinux \
  hyfetch \
  input-remapper \
  just \
  nautilus \
  openssh-askpass \
  orca \
  pipewire \
  playerctl \
  steam-devices \
  udiskie \
  webp-pixbuf-loader \
  wireplumber \
  wl-clipboard \
  xdg-desktop-portal-gnome \
  xdg-desktop-portal-gtk \
  xdg-user-dirs \
  xwayland-satellite \
  zsh \
  alacritty \
  neovim

dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf config-manager setopt tailscale-stable.enabled=0
dnf -y install --enablerepo='tailscale-stable' tailscale

systemctl enable tailscaled

### Virtualisation (libvirt/QEMU)
# qemu-system-x86_64 was already present as a systemd-container dependency, but
# without qemu-img, libvirt or any management tooling it could only boot a
# pre-made disk image via systemd-vmspawn.
#
# edk2-ovmf gives guests UEFI firmware, swtpm gives them an emulated TPM (both
# required for a Windows 11 guest), and virtiofsd allows sharing host
# directories into a guest.
dnf -y install \
  qemu-kvm \
  qemu-img \
  libvirt-daemon-kvm \
  libvirt-daemon-config-network \
  libvirt-client \
  virt-install \
  virt-manager \
  virt-viewer \
  edk2-ovmf \
  swtpm \
  swtpm-tools \
  virtiofsd

# Fedora's presets already enable these, but enable them explicitly so the
# image does not silently lose virtualisation if a preset changes -- and so
# tests/verify-image.sh has something concrete to assert.
systemctl enable virtqemud.socket
systemctl enable virtnetworkd.socket
systemctl enable virtstoraged.socket
systemctl enable virtnodedevd.socket
systemctl enable virtlogd.socket

# Upstream installer rather than the Fedora package, which lags behind (see e60d421).
# -f so an HTTP error page is not piped into sh, --retry for transient GitHub failures.
# Already running as root here, so no sudo.
curl --retry 3 -fsSL https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh
command -v distrobox >/dev/null || { echo "distrobox install failed"; exit 1; }

dnf install -y adobe-source-han-sans-cn-fonts adobe-source-han-sans-tw-fonts

rm -f /usr/share/applications/fcitx5-wayland-launcher.desktop
rm -f /usr/share/applications/org.fcitx.Fcitx5*.desktop

rm -rf /usr/share/doc/just

# DMS used to ship PAM drop-ins at /usr/share/quickshell/dms/assets/pam/ and this
# line installed them. Upstream no longer ships any pam.d files in dms, dms-cli,
# dms-greeter or quickshell, so the glob stopped matching and this had been failing
# silently on every build (invisible until apps.sh gained `set -e`).
# PAM for the login path comes from system_files/usr/lib/pam.d/greetd-spawn, which
# includes the stock greetd stack patched for gnome-keyring just below.

sed --sandbox -i -e '/gnome_keyring.so/ s/-auth/auth/ ; /gnome_keyring.so/ s/-session/session/' /etc/pam.d/greetd

dnf install -y \
  default-fonts-core-emoji \
  google-noto-fonts-all \
  glibc-all-langpacks \
  default-fonts

dnf install -y --setopt=install_weak_deps=False \
  kf6-kirigami \
  qt6ct \
  plasma-breeze \
  kf6-qqc2-desktop-style

fc-cache --force --really-force --system-only --verbose # recreate font-cache to pick up the added fonts

systemctl enable greetd
systemctl enable firewalld

cp -avf "/ctx/files"/. /

systemctl enable --global dms.service
systemctl enable --global fcitx5.service
systemctl enable --global gnome-keyring-daemon.service
systemctl enable --global gnome-keyring-daemon.socket
