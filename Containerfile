ARG FEDORA_VERSION=44
ARG NVIDIA=false
ARG AUTOLOGIN_USER=user

FROM ghcr.io/ublue-os/akmods-nvidia-open:main-${FEDORA_VERSION} AS nvidia

# Fedora's GNOME/KDE-free Atomic desktop base. It is an OCI/bootc image, not a
# traditional mutable Fedora container.
FROM quay.io/fedora-ostree-desktops/base-atomic:${FEDORA_VERSION}

ARG NVIDIA
ARG AUTOLOGIN_USER

COPY build_files/build.sh /usr/libexec/fedora-lxqt-build
COPY system_files/ /

RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=nvidia,source=/rpms,target=/tmp/akmods-nvidia,ro \
    /usr/bin/bash /usr/libexec/fedora-lxqt-build "${NVIDIA}" "${AUTOLOGIN_USER}" && \
    rm -f /usr/libexec/fedora-lxqt-build

RUN bootc container lint
