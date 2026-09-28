# Fedora Noctalia Atomic

A GNOME- and LXQt-free Fedora 44 Atomic desktop image with Noctalia, labwc, automatic
tty1 login, Flatpak, Toolbx, and Distrobox. The host is delivered as a signed OCI
bootc image; desktop packages are composed into the image rather than layered
after installation.

Host networking uses `systemd-networkd` and `systemd-resolved`, with DHCP for
wired Ethernet interfaces. NetworkManager Wi-Fi support is not installed and
NetworkManager is masked in the deployed system.
Bluetooth userspace is not installed, and `bluetooth.service` is masked.

tty1 is configured for passwordless autologin and immediately starts labwc;
labwc then starts Noctalia. Set the GitHub Actions repository
variable `AUTOLOGIN_USER` to the exact login name you will create in Anaconda
(the default is `user`). This is intentionally not suitable for a shared or
physically untrusted machine; LUKS protects data only while the machine is off.

Two images are published:

| Tag | GPU stack |
| --- | --- |
| `latest` | Fedora/Mesa, including Nouveau and XWayland |
| `nvidia` | The same desktop plus UBlue's signed NVIDIA open kernel module and userspace |

The NVIDIA tag is the intended choice for a GTX 1650 SUPER (Turing). It uses
UBlue's current `akmods-nvidia-open:main-44` artifacts and installer so the
module matches the Fedora kernel in the image. This is preferable to building
an akmod at first boot on an immutable host.

## Repository layout

```text
Containerfile                  image composition and optional NVIDIA stage
build_files/build.sh           explicit Fedora package set and service setup
system_files/etc/              Noctalia/labwc, networkd, and session defaults
.github/workflows/build.yml    daily/commit builds, GHCR publishing, signing
.github/workflows/installer.yml on-demand bootc installer ISO
disk_config/iso.toml           Anaconda modules and installed image reference
```

No LXQt session or application is installed. `xorg-x11-server-Xwayland` remains
only for legacy applications. The tty1 login launches labwc directly and
`/etc/xdg/labwc/autostart` launches Noctalia in daemon mode. Noctalia's built-in
Polkit agent is enabled in the default user configuration.

## Create and publish your image

1. Create an empty public GitHub repository named `fedora-lxqt` and push these
   files to its `main` branch.
2. In **Settings → Actions → General**, allow GitHub Actions to read and write
   repository packages. The workflow uses the built-in `GITHUB_TOKEN`; no GHCR
   password is needed.
3. In **Settings → Secrets and variables → Actions → Variables**, create
   `AUTOLOGIN_USER` with the same lowercase username you will use at install.
4. Run **Build and publish bootc images**, or push to `main`.
5. In the repository's Packages page, make the package public if GitHub created
   it private.

The results are:

```text
ghcr.io/OWNER/fedora-lxqt:latest
ghcr.io/OWNER/fedora-lxqt:nvidia
```

Every push is signed keylessly with the workflow's GitHub OIDC identity. That
provides verifiable provenance, but it does not by itself make an installed
host reject unsigned upgrades. Enforced `containers-policy.json` trust is a
separate deployment policy and needs a planned recovery/key-rotation path.

To verify a published image:

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/OWNER/fedora-lxqt/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/OWNER/fedora-lxqt:nvidia
```

## Install from the generated ISO

Run **Build installer ISO** after the `nvidia` image has been published, then
download the workflow artifact and write the ISO to USB. In Anaconda, select
automatic storage and enable **Encrypt my data** (or configure encrypted LUKS2
storage manually). Encryption is an installer/storage property, not something
embedded in the OCI image. SELinux remains enforcing from Fedora's base.

The installer workflow substitutes your actual lowercase GHCR owner into its
configuration and installs the `nvidia` stream. Change both `:nvidia`
occurrences in `installer.yml` to `:latest` for the Mesa/Nouveau image.

The installer uses Image Builder's `anaconda-iso` path because it accepts the
custom image directly as its payload; the newer `bootc-installer` type instead
requires a separate Anaconda-containing bootc image plus a payload reference.
Test the artifact in a VM
before installing physical hardware and retain a Fedora rescue USB.

## Rebase an existing Fedora Atomic system

First remove host package layering if practical (`rpm-ostree status` shows it),
back up `/home` and `/etc`, and ensure the GHCR package is public. Then:

```bash
sudo bootc switch ghcr.io/OWNER/fedora-lxqt:nvidia
sudo systemctl reboot
```

Check the staged and booted deployments with:

```bash
bootc status
```

Switching from a GNOME/KDE Atomic image preserves user data and `/etc`; old
desktop-specific user configuration also remains. A clean ISO install gives the
most predictable result and lets Anaconda configure LUKS directly.

## Secure Boot and NVIDIA

Fedora's kernel/shim remains Secure Boot compatible. The NVIDIA kernel module
is signed by the Universal Blue akmods key, which is distinct from the cosign
keyless signature on this OCI image. Before switching while Secure Boot is
enabled, enroll the module-signing certificate from the currently booted
deployment (the exact installed path is normally shown by the UBlue installer):

```bash
sudo mokutil --import /etc/pki/akmods/certs/akmods-ublue.der
```

Choose a one-time password, reboot, and complete enrollment in MokManager.
Confirm it before relying on NVIDIA:

```bash
mokutil --test-key /etc/pki/akmods/certs/akmods-ublue.der
modinfo -F signer nvidia
```

If the certificate path changes upstream, inspect
`rpm -ql ublue-os-akmods-addons | grep -E '\\.(der|cer)$'` rather than disabling
Secure Boot. Keep the previous deployment until the NVIDIA session is proven.

## Updates and rollback

The scheduled workflow rebuilds daily against Fedora 44 updates. On a client:

```bash
sudo bootc upgrade --check
sudo bootc upgrade
sudo systemctl reboot
```

To undo a bad deployment:

```bash
sudo bootc rollback
sudo systemctl reboot
```

You can also select the previous deployment in the boot menu. A rollback is
only durable until another upgrade; pinning immutable digest tags is the next
step if long-lived release channels are needed.

Flatpak is intended for GUI applications, while `toolbox create` or
`distrobox-create` provides mutable development environments. Keep host
`rpm-ostree install` use exceptional so deployments remain reproducible.

The host also includes `pass`, GnuPG, `gpg-agent`, Qt pinentry, Git support for
password-store synchronization, and `wl-clipboard` for copying secrets in the
Wayland session. Existing stores can be restored under `~/.password-store` and
private keys imported with `gpg --import`.

`cryptsetup` is included for LUKS2 management. Disk encryption itself is
created by Anaconda during installation; select **Encrypt my data** and verify
the resulting layout before committing it. The generated initramfs then uses
the installer-created crypttab and kernel arguments to unlock the root volume.

`wlr-randr` is included for labwc output configuration. For example:

```bash
wlr-randr
wlr-randr --output DP-1 --mode 1920x1080@144.000000 \
  --pos 0,0 --output HDMI-A-1 --pos 1920,0
```

Use the exact output and mode names printed by the first command. Put the final
command in `~/.config/labwc/autostart` to apply it whenever labwc starts.

Fedora's `zram-generator-defaults` enables compressed swap in RAM using the
distribution-maintained systemd generator. Inspect it after boot with:

```bash
zramctl
swapon --show
```

## Fedora release upgrades

Do not silently change `FEDORA_VERSION`. Update the version in `Containerfile`,
`build.yml`, and `image-template.env` together, let CI build both images, test
in a VM, and only then switch clients to the new tag. The NVIDIA akmods stage
must have a matching `main-N` publication before the build can succeed.

## Known boundaries

- This is a custom image, not a Fedora Edition and not covered by Fedora's
  official desktop release validation.
- The NVIDIA path depends on Universal Blue's akmods publishing service. CI
  should be treated as a gate: never deploy a failed or untested daily build.
- A tty1 autologin starts labwc (Wayland) without a display manager, and labwc
  starts Noctalia. Other virtual consoles and SSH remain ordinary shell logins.
- The generic GTK portal supplies file chooser and related desktop portals.
- The default network file configures every Ethernet link with DHCP. For a
  static address or multiple NICs, replace
  `system_files/etc/systemd/network/20-wired.network` with a narrower match and
  the desired networkd configuration.
