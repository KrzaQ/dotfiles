#!/usr/bin/env bash
set -euo pipefail

# Install rootless-Docker prerequisites for limes, and give it a usable data-root.
#
# limes itself stays distro-agnostic (it only *names* missing deps) and cannot become root;
# this is the machine-specific layer that actually installs them. Because limes vendors its
# own dockerd-rootless.sh, everything here is official-repo only -- no AUR on Arch, no
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
limes_config_d="${XDG_CONFIG_HOME:-$HOME/.config}/limes/config.d"
data_root_dropin="$limes_config_d/local-data-root.toml"
data_root_default="${XDG_DATA_HOME:-$HOME/.local/share}/limes/docker"
data_root_fallback="/var/lib/limes/$user/docker"

# The filesystem of `path`, asking the nearest existing ancestor: the data-root is created
# by `lim bootstrap` later, and a filesystem is a property of the mount point anyway.
fs_of() {
    local p="$1"
    while [[ ! -e "$p" ]]; do p="$(dirname "$p")"; done
    stat -f -c %T "$p"
}

# Docker stacks an overlay over its data-root, and these cannot carry an overlayfs
# upperdir. A copy of limes' own list (`util::unsupported_upperdir_fs`), and deliberately
# only that: this decides whether to *choose a different default*, while limes stays the
# authority that refuses to bootstrap onto one.
fs_rejects_upperdir() {
    case "$1" in
        ecryptfs | fuse* | nfs* | overlayfs) return 0 ;;
        *) return 1 ;;
    esac
}

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

# An encrypted home (ecryptfs, which several distro installers offer to set up) cannot hold
# the daemon's data-root. Left alone, that surfaces as an EINVAL deep inside buildkit on the
# first image build, so move the data-root off $HOME instead -- only when nothing already
# sets it, since a choice already made is not ours to overrule.
need_data_root=false
data_root_fs=""
if ! grep -qs '^[[:space:]]*data_root' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/limes/config.toml" "$limes_config_d"/*.toml; then
    data_root_fs="$(fs_of "$data_root_default")"
    fs_rejects_upperdir "$data_root_fs" && need_data_root=true
fi

if [[ ${#missing_bins[@]} -eq 0 ]] && ! $need_subid && ! $need_apparmor && ! $need_data_root
then
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
$need_data_root && echo "  - a data-root at $(dirname "$data_root_fallback") (\$HOME is on \
$data_root_fs, which cannot hold an overlayfs upperdir)"
echo

# System-wide, root-owned changes deserve a look at the list above before they happen.
# Gated on a TTY so unattended provisioning still runs straight through -- the -y /
# --noconfirm below is about the package manager, not about consent.
if [[ -t 0 ]]; then
    read -rp "Install these now? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Aborted; limes needs these to run." >&2
        exit 1
    fi
fi

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

# ── A data-root the daemon can stack an overlay on ──────────────────
if $need_data_root; then
    parent="$(dirname "$data_root_fallback")"
    fallback_fs="$(fs_of "$parent")"
    if fs_rejects_upperdir "$fallback_fs"; then
        {
            echo "Nowhere to put the data-root: \$HOME is on $data_root_fs and the fallback"
            echo "$parent is on $fallback_fs, neither of which can hold an overlayfs"
            echo "upperdir. Pick a path on ext4/xfs/btrfs by hand and set it in"
            echo "$data_root_dropin:"
            echo
            echo '  data_root = "/some/path/docker"'
        } >&2
        exit 1
    fi

    # Only the per-user dir is ours; /var/lib/limes stays root-owned so one user's limes
    # cannot rename another's out from under them. `lim bootstrap` creates the `docker`
    # subdir itself, as the user, which keeps limes owning its own tree.
    sudo install -d -m 755 /var/lib/limes
    sudo install -d -o "$user" -g "$(id -gn)" -m 700 "$parent"
    echo "Created $parent (on $fallback_fs)."

    # A whole file limes considers installer-owned, which is what config.d/ is for. It
    # names an absolute machine-specific path, so it must not be the synced dotfiles.toml
    # drop-in -- and sorting after that filename means it wins if the two ever collide.
    mkdir -p "$limes_config_d"
    cat > "$data_root_dropin" <<EOF
# Generated by dotfiles bootstrap/rootless-docker.sh. Machine-local -- do not sync.
#
# \$HOME is on $data_root_fs, which the kernel refuses as an overlayfs upperdir, so the
# daemon cannot keep its layers there: the symptom is an EINVAL inside buildkit on the
# first image build. Nothing of yours lives here -- the image is rebuildable and real work
# reaches the sandbox through mounts -- so it is fine that this path is outside the
# encrypted home.
data_root = "$data_root_fallback"
EOF
    echo "Wrote $data_root_dropin"

    if [[ -d "$data_root_default" ]]; then
        echo "Note: $data_root_default is now unused ($(du -sh "$data_root_default" 2>/dev/null | cut -f1)); remove it when you're satisfied this works."
    fi
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
