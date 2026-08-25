#!/usr/bin/env bash

set -xeuo pipefail

# NVIDIA driver + CUDA from NVIDIA's OFFICIAL repo (developer.download.nvidia.com),
# not a third-party rebuild.
#
# Differences from the negativo17 setup this replaces:
#   - Kernel modules come from kmod-nvidia-open-dkms (DKMS), because NVIDIA
#     publishes no akmod for Fedora. We drive dkms build/install explicitly
#     against the image's kernel rather than relying on install-time triggers,
#     which would target the build host's running kernel.
#   - The open kernel modules are used (nvidia-open). Requires Turing or newer;
#     this image targets an Ada RTX 4090.
#   - Modules are signed with a persistent MOK so Secure Boot can be enabled.
#     See `just mok-keygen` and docs/secureboot.md.

FEDORA_MAJOR="$(rpm -E %fedora)"
NV_REPO="cuda-fedora${FEDORA_MAJOR}-x86_64"

# sort -V, not sort: a lexical sort puts 6.18.9 after 6.18.10.
KERNEL_VERSION="$(find "/usr/lib/modules" -maxdepth 1 -type d ! -path "/usr/lib/modules" -exec basename '{}' ';' | sort -V | tail -n 1)"

# The module must be built against the kernel that will actually boot. If
# something pulled in a second kernel, the version picked above is a coin flip.
KERNEL_COUNT="$(find "/usr/lib/modules" -maxdepth 1 -type d ! -path "/usr/lib/modules" | wc -l)"
if [[ "${KERNEL_COUNT}" -ne 1 ]]; then
    echo "ERROR: expected exactly 1 kernel in /usr/lib/modules, found ${KERNEL_COUNT}:"
    find "/usr/lib/modules" -maxdepth 1 -type d ! -path "/usr/lib/modules"
    exit 1
fi
echo "Building NVIDIA modules against kernel ${KERNEL_VERSION}"

### Official NVIDIA repo
dnf config-manager addrepo \
    --from-repofile="https://developer.download.nvidia.com/compute/cuda/repos/fedora${FEDORA_MAJOR}/x86_64/cuda-fedora${FEDORA_MAJOR}.repo"
# Leave it off in the shipped image; enable per-transaction below.
dnf config-manager setopt "${NV_REPO}.enabled=0"
dnf config-manager setopt "${NV_REPO}.gpgcheck=1"

### Secure Boot module signing
#
# DKMS signs modules with mok_signing_key/mok_certificate. If we let it
# generate its own, the key would differ on every build and would need
# re-enrolling after every update, so the private key is supplied as a build
# secret and the public certificate is committed to the repo.
#
# The private key is only ever read from the tmpfs secret mount; it is never
# copied into the image.
MOK_KEY="/run/secrets/mok.key"
MOK_CERT_SRC="/ctx/secureboot/mok.der"
MOK_CERT="/usr/share/secureboot/mok.der"

if [[ -s "${MOK_CERT_SRC}" ]]; then
    install -Dpm0644 "${MOK_CERT_SRC}" "${MOK_CERT}"
fi

MODULES_SIGNED=no
if [[ -s "${MOK_KEY}" && -s "${MOK_CERT}" ]]; then
    # A drop-in, not /etc/dkms/framework.conf itself -- that file is owned by
    # the dkms package, and overwriting then deleting it would leave the
    # package's own config missing.
    mkdir -p /etc/dkms/framework.conf.d
    cat >/etc/dkms/framework.conf.d/00-mok-signing.conf <<EOF
mok_signing_key="${MOK_KEY}"
mok_certificate="${MOK_CERT}"
EOF
    MODULES_SIGNED=yes
    echo "MOK signing enabled"
else
    # Not fatal: unsigned modules simply mean Secure Boot must stay off, which
    # is the behaviour this image had before. CI supplies the secret.
    echo "WARNING: no MOK key at ${MOK_KEY}; modules will be UNSIGNED and"
    echo "WARNING: Secure Boot will not work with this image."
fi

### Build dependencies for DKMS
dnf -y install \
    "kernel-devel-${KERNEL_VERSION%.x86_64}" \
    dkms \
    gcc \
    gcc-c++ \
    make

### Driver + open kernel modules
dnf -y install --enablerepo="${NV_REPO}" \
    nvidia-open \
    nvidia-driver-cuda \
    nvidia-modprobe \
    nvidia-persistenced \
    nvidia-settings \
    nvidia-kmod-common

# libva-nvidia-driver is a Fedora package (VA-API bridge), not an NVIDIA one.
dnf -y install libva-nvidia-driver

### Build the modules for THIS kernel
#
# Installing kmod-nvidia-open-dkms registers the module but its autoinstall
# targets the running kernel, which in a container is the build host's. Build
# and install explicitly for the image kernel instead.
DKMS_VERSION="$(dkms status 2>/dev/null | sed -nE 's|^nvidia/([^,: ]+).*|\1|p' | sort -V | tail -n 1)"
if [[ -z "${DKMS_VERSION}" ]]; then
    echo "ERROR: no nvidia module registered with dkms"
    dkms status || true
    exit 1
fi
echo "Building nvidia DKMS module ${DKMS_VERSION} for ${KERNEL_VERSION}"

if ! dkms build -m nvidia -v "${DKMS_VERSION}" -k "${KERNEL_VERSION}"; then
    echo "ERROR: dkms build failed for nvidia/${DKMS_VERSION} on ${KERNEL_VERSION}"
    cat "/var/lib/dkms/nvidia/${DKMS_VERSION}/build/make.log" 2>/dev/null || true
    exit 1
fi
dkms install -m nvidia -v "${DKMS_VERSION}" -k "${KERNEL_VERSION}"

# A failed kmod build must fail the image build. Shipping an image whose
# nvidia.ko is missing means booting to a black screen after an update.
if ! modinfo -k "${KERNEL_VERSION}" nvidia >/dev/null 2>&1; then
    echo "ERROR: nvidia module not present for kernel ${KERNEL_VERSION} after dkms"
    exit 1
fi
echo "nvidia kmod OK: $(modinfo -k "${KERNEL_VERSION}" -F version nvidia)"

# Confirm the signature actually got applied rather than silently skipped.
#
# Capture modinfo once into a variable instead of piping it. Piping into
# `grep -q` or `head` makes the reader exit early, modinfo takes SIGPIPE, and
# under `set -o pipefail` that surfaces as exit 141 -- which aborts this script
# with a confusing status instead of the intended error message.
if [[ "${MODULES_SIGNED}" == "yes" ]]; then
    NV_MODINFO="$(modinfo -k "${KERNEL_VERSION}" nvidia)"
    if ! grep -q '^sig_id:' <<<"${NV_MODINFO}"; then
        echo "ERROR: MOK key was supplied but the installed nvidia module is unsigned."
        echo "ERROR: DKMS reported signing the build-tree copy, so the signature was"
        echo "ERROR: lost between 'dkms build' and the installed module."
        sed -n '1,25p' <<<"${NV_MODINFO}"
        exit 1
    fi
    echo "nvidia kmod signed by: $(sed -n 's/^signer: *//p' <<<"${NV_MODINFO}" | head -1)"
fi

### CUDA toolkit
# Full toolkit: nvcc, all math libraries, headers, and the Nsight Compute /
# Nsight Systems profilers. ~4 GiB download, ~8 GiB installed -- this is the
# bulk of the image, and it is carried on every update pull.
#
# For a smaller image, `cuda-minimal-build-<ver>` (nvcc + cudart, ~750 MiB) plus
# `cuda-libraries-<ver>` (~2 GiB total) covers building and running CUDA code
# without the GUI profilers.
#
# NOTE: cuDNN is NOT published in NVIDIA's Fedora repo. Get it per-project via
# pip/conda or a container if a DL framework needs it.
dnf -y install --enablerepo="${NV_REPO}" cuda-toolkit

# NVIDIA's packages use the upstream layout (/usr/local/cuda-<ver>) rather than
# Fedora's /usr/bin, and /usr/local/cuda is an alternatives-managed symlink.
# (/usr/local is a real directory on fedora-bootc, not a /var/usrlocal symlink,
# so this is genuinely part of the image.)
CUDA_HOME=/usr/local/cuda
test -x "${CUDA_HOME}/bin/nvcc" || {
    echo "ERROR: nvcc missing after CUDA install; expected ${CUDA_HOME}/bin/nvcc"
    ls -l /usr/local/ || true
    exit 1
}
echo "CUDA OK: $("${CUDA_HOME}/bin/nvcc" --version | tail -1)"

# NVIDIA ships ld.so.conf.d entries but no PATH setup, so nvcc is not usable
# out of the box. Fedora's /etc/profile sources these for login shells, which
# is the same mechanism the fcitx5 and qt-override snippets already rely on.
tee /etc/profile.d/cuda.sh <<'EOF'
# Added by the image build: NVIDIA's CUDA packages install to /usr/local/cuda
# and do not put nvcc on PATH themselves.
if [ -d /usr/local/cuda/bin ]; then
    export CUDA_HOME=/usr/local/cuda
    case ":${PATH}:" in
        *:/usr/local/cuda/bin:*) ;;
        *) export PATH="${PATH}:/usr/local/cuda/bin" ;;
    esac
fi
EOF
chmod 0644 /etc/profile.d/cuda.sh

### Container toolkit (also an official NVIDIA repo)
dnf config-manager addrepo --from-repofile=https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
dnf config-manager setopt nvidia-container-toolkit.enabled=0
dnf config-manager setopt nvidia-container-toolkit.gpgcheck=1

dnf -y install --enablerepo=nvidia-container-toolkit \
    nvidia-container-toolkit

curl --retry 3 -fsSL https://raw.githubusercontent.com/NVIDIA/dgx-selinux/master/bin/RHEL9/nvidia-container.pp -o /tmp/nvidia-container.pp
semodule -i /tmp/nvidia-container.pp
rm -f /tmp/nvidia-container.pp

### Boot configuration
# The official nvidia.conf already blacklists nouveau and nova-core; this adds
# the modeset=0 belt-and-braces and keeps the setting if packaging changes.
tee /usr/lib/modprobe.d/00-nouveau-blacklist.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOF'
kargs = ["i915.enable_dpcd_backlight=1", "nvidia.NVreg_EnableBacklightHandler=0", "nvidia.NVreg_RegistryDwords=EnableBrightnessControl=0", "rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "nvidia.modeset=1", "nvidia.fbdev=1"]
EOF

DRACUT_NVIDIA=/usr/lib/dracut/dracut.conf.d/99-nvidia.conf
if [[ ! -f "${DRACUT_NVIDIA}" ]]; then
    echo "ERROR: ${DRACUT_NVIDIA} missing; nvidia-kmod-common layout changed"
    exit 1
fi

# We must force driver load to fix black screen on boot for nvidia desktops.
# As we need forced load, also must pre-load intel/amd iGPU else chromium web
# browsers fail to use hardware acceleration.
sed -i -e 's/omit_drivers/force_drivers/g' \
       -e 's/ nvidia / i915 amdgpu nvidia /g' "${DRACUT_NVIDIA}"

# These seds silently becoming no-ops is how you end up booting to a black
# screen, so assert the result rather than trusting the substitution.
grep -q 'force_drivers' "${DRACUT_NVIDIA}" || {
    echo "ERROR: force_drivers not set in ${DRACUT_NVIDIA}"; cat "${DRACUT_NVIDIA}"; exit 1;
}
grep -q 'i915 amdgpu nvidia' "${DRACUT_NVIDIA}" || {
    echo "ERROR: iGPU pre-load not set in ${DRACUT_NVIDIA}"; cat "${DRACUT_NVIDIA}"; exit 1;
}
echo "dracut nvidia config OK: $(grep -vE '^\s*#|^\s*$' "${DRACUT_NVIDIA}")"

### Services
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

systemctl enable nvctk-cdi.service

### ASUS laptop support
dnf -y copr enable lukenukem/asus-linux
dnf -y copr disable lukenukem/asus-linux
dnf -y --enablerepo copr:copr.fedorainfracloud.org:lukenukem:asus-linux install asusctl supergfxctl

dnf -y copr enable sunwire/envycontrol
dnf -y copr disable sunwire/envycontrol
dnf -y --enablerepo copr:copr.fedorainfracloud.org:sunwire:envycontrol install envycontrol

systemctl enable supergfxd.service

# Unlike negativo17, the official packaging DOES ship these, and they are the
# mechanism NVIDIA documents for preserving VRAM across suspend/hibernate.
systemctl enable nvidia-powerd.service
systemctl enable nvidia-suspend.service
systemctl enable nvidia-resume.service
systemctl enable nvidia-hibernate.service

### Clean up the DKMS build tree
#
# The built modules already live in /usr/lib/modules/<kver>/extra, so the
# source/build tree under /var is dead weight -- and /var in a bootc image is
# only first-boot seed state. Removing it also guarantees no copy of the
# signing key survives (DKMS may cache one alongside the build).
rm -rf /var/lib/dkms
rm -f /etc/dkms/framework.conf.d/00-mok-signing.conf
