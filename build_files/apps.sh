#!/bin/bash

dnf -y copr enable avengemedia/dms
dnf -y install niri dms

dnf -y install \
  brightnessctl \
  cava \
  chezmoi \
  ddcutil \
  fastfetch \
  fcitx5-mozc \
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
  xwayland-satellite

rm -f /usr/share/applications/fcitx5-wayland-launcher.desktop
rm -f /usr/share/applications/org.fcitx.Fcitx5*.desktop

rm -rf /usr/share/doc/just

systemctl enable dms
