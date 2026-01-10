#!/bin/bash

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

install -Dpm0644 -t /usr/lib/pam.d/ /usr/share/quickshell/dms/assets/pam/*

dnf install -y \
  default-fonts-core-emoji \
  google-noto-color-emoji-fonts \
  google-noto-emoji-fonts \
  glibc-all-langpacks \
  default-fonts

cp -avf "/ctx/files"/. /

systemctl enable greetd
systemctl enable firewalld

tee /usr/lib/sysusers.d/greeter.conf <<'EOF'
g greeter 767
u greeter 767 "Greetd greeter"
EOF
