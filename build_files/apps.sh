#!/bin/bash

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
dnf -y copr disable avengemedia/dms-gi
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
  neovim \
  distrobox

dnf install -y adobe-source-han-sans-cn-fonts adobe-source-han-sans-tw-fonts

rm -f /usr/share/applications/fcitx5-wayland-launcher.desktop
rm -f /usr/share/applications/org.fcitx.Fcitx5*.desktop

rm -rf /usr/share/doc/just

install -Dpm0644 -t /usr/lib/pam.d/ /usr/share/quickshell/dms/assets/pam/*
sed --sandbox -i -e '/gnome_keyring.so/ s/-auth/auth/ ; /gnome_keyring.so/ s/-session/session/' /etc/pam.d/greetd

dnf install -y \
  default-fonts-core-emoji \
  google-noto-color-emoji-fonts \
  google-noto-emoji-fonts \
  glibc-all-langpacks \
  default-fonts

fc-cache --force --really-force --system-only --verbose # recreate font-cache to pick up the added fonts

systemctl enable greetd
systemctl enable firewalld

cp -avf "/ctx/files"/. /

systemctl enable --global dms.service
systemctl enable --global fcitx5.service
systemctl enable --global gnome-keyring-daemon.service
systemctl enable --global gnome-keyring-daemon.socket
