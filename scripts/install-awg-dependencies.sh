#!/bin/sh
# Pinned third-party packages for official OpenWrt 25.12.6 mediatek/filogic.
set -eu
umask 077

fail() { echo "AmneziaWG dependencies: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'Run as root.'
[ -r /etc/openwrt_release ] || fail 'OpenWrt release information missing.'
. /etc/openwrt_release
[ "${DISTRIB_ID:-}" = OpenWrt ] || fail 'Unsupported distribution.'
[ "${DISTRIB_RELEASE:-}" = 25.12.6 ] || fail 'Requires OpenWrt 25.12.6.'
[ "${DISTRIB_TARGET:-}" = mediatek/filogic ] || fail 'Requires mediatek/filogic.'
[ "$(uname -m)" = aarch64 ] || fail 'Requires aarch64.'
for cmd in apk wget sha256sum sysupgrade mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing $cmd."
done
tmp=$(mktemp -d /tmp/artak-awg.XXXXXX) || fail 'Cannot create temporary directory.'
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
base=https://github.com/2Grey/awg-openwrt/releases/download/v25.12.6
suffix=v25.12.6_aarch64_cortex-a53_mediatek_filogic.apk
download() {
    name=$1; expected=$2
    file="$tmp/${name}_${suffix}"
    wget -q -O "$file" "$base/${name}_${suffix}" || fail "Download failed: $name."
    actual=$(sha256sum "$file")
    actual=${actual%% *}
    [ "$actual" = "$expected" ] || fail "Checksum mismatch: $name."
}
download amneziawg-tools 999cb2f8d20c82e56a47283813133e9c04ea3b5c52f8bd7d49af7aa523d3e8d4
download kmod-amneziawg f8bce57fcd5d128db758cb32ec98f62ee6ca54adec17541c97fa3f2d51eeb7e8
download luci-proto-amneziawg 2bd2a49fa57769624aa295c38cc807f531802836e118845ff56bc5cd61cc1abe
set -- "$tmp/amneziawg-tools_$suffix" "$tmp/kmod-amneziawg_$suffix" "$tmp/luci-proto-amneziawg_$suffix"
echo 'Checking package dependencies and kernel ABI...'
apk --allow-untrusted --simulate add "$@" || fail 'Simulation failed; no packages installed. Kernel ABI or dependencies may be incompatible.'
backup="/root/artak-awg-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
[ ! -e "$backup" ] || fail 'Backup path already exists.'
sysupgrade -b "$backup" || fail 'Backup failed; no packages installed.'
[ -s "$backup" ] || fail 'Backup is empty; no packages installed.'
echo "Configuration backup: $backup"
echo 'Installing pinned AmneziaWG dependencies...'
apk --allow-untrusted add "$@" || fail "Installation failed. Configuration backup: $backup"
echo 'Dependencies installed. This does not import or activate a VPN profile.'
