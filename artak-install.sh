#!/bin/sh
# Upgrade an existing Forkop installation; retain its installed sing-box engine.
set -eu

VERSION=2.4.3-canary.2
BASE_URL="https://github.com/Menshikovivan/ArtakFork/releases/download/$VERSION"
CHECK_ONLY=0
case "${1:-}" in
    --check) CHECK_ONLY=1 ;;
    '') ;;
    *) echo 'Usage: sh artak-install.sh [--check]' >&2; exit 1 ;;
esac
[ "$#" -le 1 ] || { echo 'Too many arguments' >&2; exit 1; }
fail() { echo "ArtakFork: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'Run as root.'
for cmd in apk sha256sum mktemp awk; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command: $cmd"
done
[ -r /etc/openwrt_release ] || fail 'OpenWrt 25.12 is required.'
. /etc/openwrt_release
case "${DISTRIB_RELEASE:-}" in
    25.12|25.12.[0-9]*) ;;
    *) fail 'Only stable OpenWrt 25.12 releases with APK are supported.' ;;
esac
case "${DISTRIB_RELEASE#25.12}" in
    *[!0-9.]*) fail 'Prerelease and SNAPSHOT builds are not supported.' ;;
esac
apk info -e forkop >/dev/null 2>&1 || fail 'Install Forkop first; this is an upgrade installer.'
command -v sing-box >/dev/null 2>&1 || fail 'An existing compatible sing-box engine is required.'
[ -x /etc/init.d/forkop ] || fail 'Forkop service is missing.'

download() {
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --output "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$2" "$1"
    else
        fail 'curl or wget with HTTPS support is required.'
    fi
}

WORK_DIR=$(mktemp -d /tmp/artakfork-install.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
cd "$WORK_DIR"
download "$BASE_URL/SHA256SUMS" SHA256SUMS
for package in forkop luci-app-forkop luci-i18n-forkop-ru; do
    file="${package}_${VERSION}.apk"
    download "$BASE_URL/$file" "$file"
    # Select exactly one checksum for each fixed package name. Never check or
    # install additional paths named by the remote checksum manifest.
    awk -v file="$file" '
        $2 == file || $2 == "*" file {
            if (length($1) != 64 || $1 ~ /[^0-9a-fA-F]/) exit 1;
            print $1 "  " file; count++
        }
        END { if (count != 1) exit 1 }
    ' SHA256SUMS > "$file.sha256" || fail "Missing or ambiguous checksum: $file"
    sha256sum -c "$file.sha256" || fail "Checksum failed: $file"
done
if [ "$CHECK_ONLY" = 1 ]; then
    echo "ArtakFork $VERSION: all three APK checksums verified; no configuration or packages changed."
    exit 0
fi

command -v sysupgrade >/dev/null 2>&1 || fail 'sysupgrade is required for a persistent configuration backup.'
BACKUP_DIR=/root/artakfork-backups
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
BACKUP_PATH="$BACKUP_DIR/pre-artakfork-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
sysupgrade -b "$BACKUP_PATH" || fail 'Backup failed; packages were not changed.'
[ -s "$BACKUP_PATH" ] || fail 'Backup is empty; packages were not changed.'
chmod 600 "$BACKUP_PATH"
echo "Configuration backup: $BACKUP_PATH"
# These packages contain the Forkop backend and UI only. The installed engine
# remains in place; this does not bootstrap or replace sing-box.
apk add --allow-untrusted \
    "./forkop_${VERSION}.apk" \
    "./luci-app-forkop_${VERSION}.apk" \
    "./luci-i18n-forkop-ru_${VERSION}.apk"
/etc/init.d/forkop restart
echo "ArtakFork $VERSION installed. Backup: $BACKUP_PATH"
