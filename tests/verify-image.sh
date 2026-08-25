#!/usr/bin/env bash
#
# Smoke test for the built image. Runs INSIDE the container, before anything is
# pushed. The point is that a build which produces an unbootable or gutted image
# fails in CI rather than landing on the workstation via the weekly bootc update.
#
# Local use:
#   just build && just verify

set -uo pipefail

FAILURES=0

fail() {
    echo "  FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

ok() {
    echo "  ok: $*"
}

# Assert a command exists on PATH.
check_bin() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "binary $1"
    else
        fail "binary $1 missing"
    fi
}

# Assert a systemd unit is enabled. Covers both system and --global user units.
check_enabled() {
    local scope=$1 unit=$2
    local state
    state=$(systemctl "${scope}" is-enabled "${unit}" 2>&1)
    case "${state}" in
        enabled | enabled-runtime | static | indirect)
            ok "unit ${unit} (${scope}): ${state}"
            ;;
        *)
            fail "unit ${unit} (${scope}) not enabled: ${state}"
            ;;
    esac
}

echo "== Desktop session =="
# If any of these are missing there is no way to log in.
for b in niri greetd dms dms-greeter quickshell alacritty; do check_bin "$b"; done

echo "== Core tooling =="
for b in tailscaled distrobox flatpak podman zsh nvim chezmoi just; do check_bin "$b"; done

echo "== Virtualisation =="
for b in qemu-system-x86_64 qemu-img virsh virt-install virt-manager virt-viewer swtpm; do
    check_bin "$b"
done
# virtiofsd is a libexec helper libvirt spawns, deliberately not on PATH.
if [[ -x /usr/libexec/virtiofsd ]]; then
    ok "virtiofsd present (host directory sharing)"
else
    fail "virtiofsd missing -- cannot share host directories into guests"
fi
# Guests need UEFI firmware; without edk2-ovmf only legacy BIOS boot works.
if compgen -G "/usr/share/edk2/ovmf/OVMF_CODE*" >/dev/null; then
    ok "OVMF UEFI firmware present"
else
    fail "no OVMF firmware -- UEFI guests cannot boot"
fi
# The wheel polkit rule is what avoids a manual `usermod -aG libvirt`.
if [[ -f /usr/share/polkit-1/rules.d/49-libvirt-wheel.rules ]]; then
    ok "libvirt polkit rule for wheel present"
else
    fail "libvirt wheel polkit rule missing -- users need adding to the libvirt group by hand"
fi

echo "== Kernel =="
KERNEL_COUNT=$(find /usr/lib/modules -maxdepth 1 -type d ! -path /usr/lib/modules | wc -l)
if [[ "${KERNEL_COUNT}" -eq 1 ]]; then
    KVER=$(find /usr/lib/modules -maxdepth 1 -type d ! -path /usr/lib/modules -exec basename '{}' ';')
    ok "single kernel: ${KVER}"
else
    fail "expected 1 kernel, found ${KERNEL_COUNT}"
    KVER=$(find /usr/lib/modules -maxdepth 1 -type d ! -path /usr/lib/modules -exec basename '{}' ';' | sort -V | tail -1)
fi

if [[ -f "/usr/lib/modules/${KVER}/initramfs.img" ]]; then
    ok "initramfs present for ${KVER}"
else
    fail "no initramfs for ${KVER} -- system will not boot"
fi

echo "== NVIDIA =="
# The kmod is built out of tree against a specific kernel; a mismatch here is
# the difference between a working desktop and a black screen.
# Capture modinfo ONCE into a variable. Piping it into `grep -q` or `head`
# makes the reader exit early, modinfo takes SIGPIPE and returns 141, and under
# `set -o pipefail` that non-zero status reads as "no match" -- which reported a
# correctly signed module as unsigned.
NV_MODINFO=""
if NV_MODINFO="$(modinfo -k "${KVER}" nvidia 2>/dev/null)"; then
    ok "nvidia kmod for ${KVER}: $(sed -n 's/^version: *//p' <<<"${NV_MODINFO}" | sed -n 1p)"
    # The open modules are dual-licensed; the proprietary blob reports
    # "NVIDIA". Flag a silent switch back, since it changes GPU support.
    ok "nvidia kmod license: $(sed -n 's/^license: *//p' <<<"${NV_MODINFO}" | sed -n 1p)"
else
    fail "nvidia kmod missing for kernel ${KVER}"
fi
for b in nvidia-smi nvidia-ctk; do check_bin "$b"; done

# nvcc lives at /usr/local/cuda/bin, not on the default PATH, so check the path
# directly and confirm the profile snippet that puts it on PATH is present.
if [[ -x /usr/local/cuda/bin/nvcc ]]; then
    ok "nvcc: $(/usr/local/cuda/bin/nvcc --version | sed -n 's/.*release \([0-9.]*\).*/\1/p' | head -1)"
else
    fail "nvcc missing at /usr/local/cuda/bin/nvcc"
fi
if [[ -f /etc/profile.d/cuda.sh ]]; then
    ok "cuda PATH profile snippet present"
else
    fail "/etc/profile.d/cuda.sh missing -- nvcc will not be on PATH"
fi

# Secure Boot: modules must be signed by the enrolled MOK, otherwise the
# machine can only boot them with Secure Boot disabled.
if [[ -f /usr/share/secureboot/mok.der ]]; then
    ok "MOK certificate shipped for enrollment"
    if grep -q '^sig_id:' <<<"${NV_MODINFO}"; then
        ok "nvidia kmod signed by: $(sed -n 's/^signer: *//p' <<<"${NV_MODINFO}" | sed -n 1p)"
    else
        fail "nvidia kmod is UNSIGNED -- Secure Boot will not load it"
    fi
else
    fail "no MOK certificate at /usr/share/secureboot/mok.der"
fi

if [[ -f /usr/lib/bootc/kargs.d/00-nvidia.toml ]]; then
    ok "nvidia kargs present"
else
    fail "nvidia kargs missing -- modeset will not be set"
fi

echo "== Third-party repos are disabled =="
# Every repo we add during the build is meant to be switched off in the shipped
# image. A COPR left enabled is a live third-party repo on the workstation.
#
# Ask dnf rather than grepping /etc/yum.repos.d: dnf5's `config-manager setopt`
# records the change in /etc/dnf/repos.override.d/99-config_manager.repo and
# leaves enabled=1 in the original .repo file, so grepping the files reports
# disabled repos as enabled.
ALLOWED_REPOS="fedora fedora-cisco-openh264 updates updates-archive"
while IFS= read -r repoid; do
    [[ -z "${repoid}" ]] && continue
    if [[ " ${ALLOWED_REPOS} " == *" ${repoid} "* ]]; then
        ok "repo ${repoid} enabled (Fedora, expected)"
    else
        fail "third-party repo left enabled: ${repoid}"
    fi
done < <(dnf repolist --enabled --quiet 2>/dev/null | tail -n +2 | awk '{print $1}')

echo "== Services =="
for u in \
    greetd.service \
    tailscaled.service \
    bootc-fetch-apply-updates.timer \
    flatpak-add-flathub-repos.service \
    rechunker-group-fix.service \
    nvctk-cdi.service \
    supergfxd.service \
    firewalld.service \
    auditd.service \
    podman.socket \
    nvidia-powerd.service \
    nvidia-suspend.service \
    nvidia-resume.service \
    nvidia-hibernate.service \
    virtqemud.socket \
    virtnetworkd.socket \
    virtstoraged.socket \
    virtnodedevd.socket \
    virtlogd.socket; do
    check_enabled --system "$u"
done

for u in dms.service fcitx5.service; do
    check_enabled --global "$u"
done

echo "== bootc container lint =="
# Moved here from a Containerfile RUN step; see the note in the Containerfile.
if bootc container lint; then
    ok "bootc container lint"
else
    fail "bootc container lint failed"
fi

echo
if [[ "${FAILURES}" -gt 0 ]]; then
    echo "IMAGE VERIFICATION FAILED: ${FAILURES} problem(s)"
    exit 1
fi
echo "Image verification passed"
