# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /build
COPY system_files /files
# Public Secure Boot certificate (not secret). The matching private key is
# supplied at build time as a secret; see docs/secureboot.md.
COPY secureboot /secureboot
# Base Image
FROM quay.io/fedora/fedora-bootc:44

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.


RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/build.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/apps.sh

COPY --from=ghcr.io/ublue-os/brew:latest /system_files /
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /usr/bin/systemctl preset brew-setup.service && \
    /usr/bin/systemctl preset brew-update.timer && \
    /usr/bin/systemctl preset brew-upgrade.timer
# The CUDA toolkit is multiple GiB of downloads; without the /var/cache mount
# every byte of it would be baked into this layer on top of the installed files.
#
# mok.key signs the NVIDIA kernel modules for Secure Boot. It is a secret mount,
# so it lives on tmpfs and never lands in a layer. Builds without it still
# succeed; the modules are just unsigned and Secure Boot cannot be used.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=mok_key,target=/run/secrets/mok.key \
    /ctx/build/nvidia.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/cleanup.sh

### LINTING
## `bootc container lint` is deliberately NOT a RUN step here. During
## `podman build` the /sys mount can expose securityfs, and the var-tmpfiles
## lint then dies on /sys/kernel/security/ima/binary_runtime_measurements with
## EPERM (tpm2-tss-fapi ships a tmpfiles.d entry for that path). The same lint
## passes cleanly under `podman run`, so it runs in tests/verify-image.sh
## instead -- which still gates the CI push, and additionally runs the smoke
## tests. See `just verify`.
