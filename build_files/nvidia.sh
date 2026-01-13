#!/bin/bash
dnf -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf -y update
dnf -y install kernel-devel akmod-nvidia xorg-x11-drv-nvidia-cuda

tee /usr/lib/modprobe.d/00-nouveau-blacklist.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOF'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

dnf -y copr enable lukenukem/asus-linux
dnf -y copr disable lukenukem/asus-linux
dnf -y --enablerepo copr:copr.fedorainfracloud.org:lukenukem:asus-linux install asusctl supergfxctl

dnf config-manager addrepo --from-repofile=https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
dnf config-manager setopt nvidia-container-toolkit.enabled=0
dnf config-manager setopt nvidia-container-toolkit.gpgcheck=1

dnf -y install --enablerepo=nvidia-container-toolkit \
  nvidia-container-toolkit

curl --retry 3 -L https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp -o nvidia-container.pp
semodule -i nvidia-container.pp
rm -f nvidia-container.pp

tee /usr/lib/systemd/system/nvctk-cdi.service <<'EOF'
[Unit]
Description=nvidia container toolkit CDI auto-generation
ConditionFileIsExecutable=/usr/bin/nvidia-ctk
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

[Install]
WantedBy=multi-user.target
EOF

systemctl enable supergfxd.service
systemctl enable nvctk-cdi.service
systemctl enable nvidia-hibernate.service nvidia-suspend.service nvidia-resume.service nvidia-powerd.service
