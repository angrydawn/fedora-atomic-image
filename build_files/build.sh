#!/usr/bin/bash
set -euo pipefail

nvidia="${1:-false}"
autologin_user="${2:-user}"

if [[ ! "${autologin_user}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid AUTOLOGIN_USER: ${autologin_user}" >&2
  exit 2
fi

# Keep the shell package list explicit so the image does not acquire a full
# desktop-environment package group or unrelated applications.
desktop_packages=(
  labwc
  noctalia
  ghostty
)

platform_packages=(
  cryptsetup
  dbus-daemon
  fastfetch
  firewalld
  fish
  flatpak
  fwupd
  git-core
  gnupg2
  gnupg2-gpg-agent
  gvfs
  gvfs-fuse
  gvfs-mtp
  pipewire
  pipewire-alsa
  pipewire-pulseaudio
  pinentry-qt
  qt6-qtwayland
  toolbox
  distrobox
  udisks2
  pass
  wl-clipboard
  wlr-randr
  wireplumber
  xdg-desktop-portal
  xdg-desktop-portal-gtk
  xdg-user-dirs
  xorg-x11-server-Xwayland
  zram-generator-defaults
)

# Ghostty is not packaged in Fedora's official repositories. This COPR
# currently provides Fedora 44 builds and is enabled only during image builds.
dnf5 -y copr enable scottames/ghostty

dnf5 install -y --setopt=install_weak_deps=False \
  "${desktop_packages[@]}" "${platform_packages[@]}"

dnf5 -y copr disable scottames/ghostty

# Fail the image build if a dependency change removes a session-critical tool.
command -v dbus-run-session labwc noctalia ghostty >/dev/null

# The GTX 1650 SUPER is Turing and supported by NVIDIA's open kernel modules.
# UBlue's staged installer installs a kernel-matched, signed kmod and userspace.
if [[ "${nvidia}" == "true" ]]; then
    test -x /tmp/akmods-nvidia/ublue-os/nvidia-install.sh

    IMAGE_NAME=fedora-lxqt \
        MULTILIB=0 \
        AKMODNV_PATH=/tmp/akmods-nvidia \
        /tmp/akmods-nvidia/ublue-os/nvidia-install.sh
fi
# The installed host uses networkd. NetworkManager may still exist in the
# Fedora base for installer/dependency reasons, so mask it rather than risking
# removal of base-image components.
systemctl disable NetworkManager.service 2>/dev/null || true
systemctl mask NetworkManager.service
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl disable bluetooth.service 2>/dev/null || true
systemctl mask bluetooth.service
systemctl enable firewalld.service
systemctl set-default graphical.target

# Autologin on tty1; the login-shell profile starts labwc. This keeps a
# proper PAM/logind session without carrying a graphical display manager.
install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/sbin/agetty --autologin ${autologin_user} --noclear %I \$TERM
EOF

# Image builds must not carry package-manager caches or machine-specific state.
dnf5 clean all
rm -rf /var/cache/dnf /var/log/dnf* /var/lib/dnf/history*
# /tmp/akmods-nvidia is a read-only BuildKit mount and vanishes after this RUN.
# Clean other temporary entries without attempting to modify that mount.
find /tmp -mindepth 1 -maxdepth 1 ! -name akmods-nvidia \
    -exec rm -rf -- {} +
