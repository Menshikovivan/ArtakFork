#!/bin/sh
# Bootstrap or upgrade ArtakFork on the supported OpenWrt APK platform.
set -eu
VERSION=2.4.3-canary.7
BASE_VERSION=1.0.5
ENGINE_VERSION=1.14.3-extended-2.7.3
ENGINE_FILE=sing-box-extended_1.14.3-extended-2.7.3_openwrt_aarch64_cortex-a53.apk
BASE_URL="https://github.com/Menshikovivan/ArtakFork/releases/download/$VERSION"
CHECK_ONLY=0
case "${1:-}" in --check) CHECK_ONLY=1;; '') ;; *) echo 'Usage: sh artak-install.sh [--check]' >&2; exit 1;; esac
[ "$#" -le 1 ] || { echo 'Too many arguments' >&2; exit 1; }
fail() { echo "ArtakFork: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'Run as root.'
for cmd in apk sha256sum mktemp awk mkdir chmod date rm; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command: $cmd"
done
[ -r /etc/openwrt_release ] || fail 'OpenWrt 25.12 is required.'
. /etc/openwrt_release
case "${DISTRIB_RELEASE:-}" in 25.12|25.12.[0-9]*) ;; *) fail 'Stable OpenWrt 25.12 is required.';; esac
case "${DISTRIB_RELEASE#25.12}" in *[!0-9.]*) fail 'Prerelease and SNAPSHOT builds are unsupported.';; esac
[ "${DISTRIB_ARCH:-}" = aarch64_cortex-a53 ] || fail 'Only aarch64_cortex-a53 is supported.'
command -v sysupgrade >/dev/null 2>&1 || fail 'sysupgrade is required for a configuration backup.'
download() {
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --output "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -O "$2" "$1"
    else fail 'curl or wget with HTTPS support is required.'; fi
}
WORK_DIR=$(mktemp -d /tmp/artakfork-install.XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
cd "$WORK_DIR"
download "$BASE_URL/SHA256SUMS" SHA256SUMS
FILES="$ENGINE_FILE"
AWG_SUPPORTED=0
if [ "${DISTRIB_RELEASE:-}" = 25.12.6 ] && [ "${DISTRIB_TARGET:-}" = mediatek/filogic ]; then
    AWG_SUPPORTED=1
    FILES="$FILES install-awg-dependencies.sh"
fi
for package in forkop luci-app-forkop luci-i18n-forkop-ru; do
    FILES="$FILES upstream-${package}_${BASE_VERSION}.apk ${package}_${VERSION}.apk"
done
for file in $FILES; do
    download "$BASE_URL/$file" "$file"
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
    echo "ArtakFork $VERSION: downloaded files verified; no configuration or packages changed."
    exit 0
fi
HAS_FORKOP=0
apk info -e forkop >/dev/null 2>&1 && HAS_FORKOP=1
CURRENT_ENGINE=''
if command -v sing-box >/dev/null 2>&1; then
    CURRENT_ENGINE=$(sing-box version 2>/dev/null | awk 'NR == 1 { print; exit }')
fi
CHANGE_ENGINE=1
[ "$CURRENT_ENGINE" != "sing-box version $ENGINE_VERSION" ] || CHANGE_ENGINE=0
BACKUP_DIR=/root/artakfork-backups
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
BACKUP_PATH="$BACKUP_DIR/pre-artakfork-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
sysupgrade -b "$BACKUP_PATH" || fail 'Backup failed; packages were not changed.'
[ -s "$BACKUP_PATH" ] || fail 'Backup is empty; packages were not changed.'
chmod 600 "$BACKUP_PATH"
echo "Configuration backup: $BACKUP_PATH"
apk update
# Simulate every required transaction before stopping services or installing.
# Including the engine in these plans lets APK resolve conflicts and dependencies.
set --
[ "$CHANGE_ENGINE" = 0 ] || set -- "./$ENGINE_FILE"
if [ "$HAS_FORKOP" = 0 ]; then
    apk --simulate add --allow-untrusted "$@" \
        "./upstream-forkop_${BASE_VERSION}.apk" \
        "./upstream-luci-app-forkop_${BASE_VERSION}.apk" \
        "./upstream-luci-i18n-forkop-ru_${BASE_VERSION}.apk"
fi
apk --simulate add --allow-untrusted "$@" \
    "./forkop_${VERSION}.apk" "./luci-app-forkop_${VERSION}.apk" "./luci-i18n-forkop-ru_${VERSION}.apk"
if [ "$AWG_SUPPORTED" = 1 ]; then
    sh ./install-awg-dependencies.sh "$VERSION" || fail 'AmneziaWG dependency installation failed.'
else
    echo 'AmneziaWG dependencies are not available for this OpenWrt target; installing ArtakFork without them.'
fi
if [ "$CHANGE_ENGINE" = 1 ]; then
    [ ! -x /etc/init.d/forkop ] || /etc/init.d/forkop stop
    # Stop only a standalone engine when replacing its binary. Same-version
    # upgrades never stop sing-box and leave Forkop-managed processes alone.
    if [ -x /etc/init.d/sing-box ]; then
        if /etc/init.d/sing-box running; then /etc/init.d/sing-box stop; fi
    fi
    apk add --allow-untrusted "./$ENGINE_FILE"
fi
[ ! -x /etc/init.d/sing-box ] || /etc/init.d/sing-box disable
if [ "$HAS_FORKOP" = 0 ]; then
    apk add --allow-untrusted \
        "./upstream-forkop_${BASE_VERSION}.apk" \
        "./upstream-luci-app-forkop_${BASE_VERSION}.apk" \
        "./upstream-luci-i18n-forkop-ru_${BASE_VERSION}.apk"
fi
apk add --allow-untrusted \
    "./forkop_${VERSION}.apk" "./luci-app-forkop_${VERSION}.apk" "./luci-i18n-forkop-ru_${VERSION}.apk"
if [ "$AWG_SUPPORTED" = 1 ]; then
    command -v ubus >/dev/null 2>&1 || fail 'Cannot inspect netifd protocol handlers: ubus is missing.'
    command -v grep >/dev/null 2>&1 || fail 'Cannot inspect netifd protocol handlers: grep is missing.'
    HANDLERS=$(ubus call network get_proto_handlers 2>/dev/null) || fail 'Cannot inspect netifd protocol handlers.'
    if ! printf '%s\n' "$HANDLERS" | grep -q '"amneziawg"'; then
        # netifd loads shell protocol handlers at daemon startup, not on its
        # normal config reload. Run restart in a HUP-immune detached process:
        # SSH and Wi-Fi can drop before it finishes.
        AWG_RESTART_LOCK=/tmp/artak-awg-netifd-restart.lock
        mkdir "$AWG_RESTART_LOCK" 2>/dev/null || fail 'AWG network restart is already pending; inspect /root/artakfork-backups/awg-network-restart.log.'
        AWG_RESTART_JOB=$(mktemp /tmp/artak-awg-netifd-restart.XXXXXX) || { rmdir "$AWG_RESTART_LOCK"; fail 'Could not create AWG restart job.'; }
        chmod 700 "$AWG_RESTART_JOB"
        cat > "$AWG_RESTART_JOB" <<'AWG_RESTART_SCRIPT'
#!/bin/sh
set -u
LOCK=/tmp/artak-awg-netifd-restart.lock
trap 'rmdir "$LOCK" 2>/dev/null || true; rm -f "$0"' EXIT
echo 'ArtakFork: waiting 5 seconds before restarting network.'
/bin/sleep 5
if ! /etc/init.d/network restart; then
    echo 'ArtakFork: network restart failed; Forkop was not started.'
    exit 1
fi
n=0
while [ "$n" -lt 90 ]; do
    handlers=$(ubus call network get_proto_handlers 2>/dev/null) || handlers=''
    if printf '%s\n' "$handlers" | grep -q '"amneziawg"'; then
        if /etc/init.d/forkop restart; then
            echo 'ArtakFork: AWG handler is available and Forkop restarted.'
            exit 0
        fi
        echo 'ArtakFork: AWG handler is available but Forkop restart failed.'
        exit 1
    fi
    n=$((n+1))
    /bin/sleep 1
done
echo 'ArtakFork: AWG handler did not become available; Forkop was not started.'
exit 1
AWG_RESTART_SCRIPT
        echo 'ArtakFork: AWG requires a network restart. SSH and Wi-Fi may disconnect briefly; the job continues automatically.'
        echo 'Progress log: /root/artakfork-backups/awg-network-restart.log'
        (trap '' HUP; exec /bin/sh "$AWG_RESTART_JOB") </dev/null >"$BACKUP_DIR/awg-network-restart.log" 2>&1 &
        echo "ArtakFork $VERSION installed; network restart scheduled. Backup: $BACKUP_PATH"
        exit 0
    fi
fi
/etc/init.d/forkop restart
echo "ArtakFork $VERSION installed. Backup: $BACKUP_PATH"
