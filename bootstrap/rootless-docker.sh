#!/usr/bin/env bash
set -euo pipefail

# Install rootless-Docker prerequisites for limes, per distro.
#
# limes itself stays distro-agnostic (it only *names* missing deps); this is the
# machine-specific layer that actually installs them. Because limes vendors its own
# dockerd-rootless.sh, everything here is official-repo only -- no AUR on Arch, no
# docker-ce-rootless-extras on Debian/Ubuntu.

# macOS uses limes' Seatbelt backend, which has no daemon, no image and no privileged
# prerequisites -- `lim` is ready as soon as the binary exists. Bail before the sudo prompt
# below, so a direct invocation here doesn't ask for a password to do nothing.
if [[ "$(uname -s)" != Linux ]]; then
    echo "rootless-docker prerequisites are Linux-only; $(uname -s) uses the Seatbelt backend. Skipping."
    exit 0
fi

user="$(id -un)"
apparmor_profile=/etc/apparmor.d/usr.bin.rootlesskit

# ── Detect what's missing (idempotent; no sudo yet) ─────────────────
missing_bins=()
for bin in rootlesskit slirp4netns dockerd newuidmap fuse-overlayfs; do
    command -v "$bin" &>/dev/null || missing_bins+=("$bin")
done

need_subid=false
for f in /etc/subuid /etc/subgid; do
    grep -q "^$user:" "$f" 2>/dev/null || need_subid=true
done

# Ubuntu 24.04+ restricts unprivileged user namespaces; rootlesskit then needs a profile.
need_apparmor=false
if [[ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)" == 1 ]] \
   && [[ ! -e "$apparmor_profile" ]]; then
    need_apparmor=true
fi

if [[ ${#missing_bins[@]} -eq 0 ]] && ! $need_subid && ! $need_apparmor; then
    echo "rootless-docker prerequisites already satisfied."
    exit 0
fi

# ── Distro family via /etc/os-release ───────────────────────────────
id=""; id_like=""
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"; id_like="${ID_LIKE:-}"
fi
family=""
case " $id $id_like " in
    *" arch "*)                 family=arch ;;
    *" fedora "*)               family=fedora ;;
    *" ubuntu "*|*" debian "*)  family=debian ;;
esac

# ── Everything below needs root ─────────────────────────────────────
echo "limes needs rootless-docker prerequisites installed:"
[[ ${#missing_bins[@]} -gt 0 ]] && echo "  - packages providing: ${missing_bins[*]}"
$need_subid    && echo "  - subordinate uid/gid ranges for $user"
$need_apparmor && echo "  - an AppArmor profile for rootlesskit (Ubuntu restricted userns)"
echo

# `sudo -v` authenticates to refresh the timestamp file and prompts even where NOPASSWD:ALL
# applies, so probe with a real command first: passwordless sudo then stays passwordless.
if ! sudo -n true 2>/dev/null && ! sudo -v; then
    {
        echo "This step needs root, but sudo isn't usable here (no passwordless sudo and"
        echo "no way to prompt). Run 'make bootstrap-limes' from an interactive shell, or"
        echo "install the prerequisites manually, then re-run."
    } >&2
    exit 1
fi

# ── Packages ────────────────────────────────────────────────────────
if [[ ${#missing_bins[@]} -gt 0 ]]; then
    case "$family" in
        arch)
            sudo pacman -S --needed --noconfirm docker rootlesskit slirp4netns fuse-overlayfs
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y \
                docker.io rootlesskit slirp4netns uidmap dbus-user-session fuse-overlayfs
            ;;
        fedora)
            {
                echo "Fedora isn't auto-supported: Docker isn't in Fedora's default repos"
                echo "(podman is). Add Docker's dnf repo + engine and the rootless tools,"
                echo "then re-run 'make bootstrap-limes':"
                echo
                echo "  sudo dnf -y install dnf-plugins-core"
                echo "  sudo dnf config-manager --add-repo \\"
                echo "       https://download.docker.com/linux/fedora/docker-ce.repo"
                echo "  sudo dnf -y install docker-ce rootlesskit slirp4netns fuse-overlayfs"
            } >&2
            exit 1
            ;;
        *)
            echo "Unsupported distro (ID=$id). Install manually: ${missing_bins[*]}" >&2
            exit 1
            ;;
    esac
fi

# ── subuid / subgid (shadow; distro-agnostic) ───────────────────────
if $need_subid; then
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$user"
    echo "Added subuid/subgid ranges for $user."
fi

# ── Ubuntu 24.04+ AppArmor profile for rootlesskit ──────────────────
if $need_apparmor; then
    echo "Writing $apparmor_profile ..."
    sudo tee "$apparmor_profile" >/dev/null <<'EOF'
abi <abi/4.0>,
include <tunables/global>

"/usr/bin/rootlesskit" flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
EOF
    sudo systemctl restart apparmor.service || true
fi

echo
echo "rootless-docker prerequisites installed."
