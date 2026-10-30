#!/bin/sh
# Only for the disposable VM provisioned by amnezia_openwrt_vm.py.
set -eu
umask 077
[ "${ARTAK_DISPOSABLE_VM:-}" = 1 ] && [ -n "${ARTAK_MIRROR:-}" ] || exit 1
echo 'E2E stage: install built packages'
/etc/init.d/firewall stop
# The stock VM firewall can leave a rejecting base chain after stop/reload;
# only this disposable image uses its LAN as the package-download uplink.
nft flush ruleset
ip addr replace 10.0.2.15/24 dev br-lan
ip route replace default via 10.0.2.2 dev br-lan
echo 'E2E stage: verify temporary package uplink'
ip route get 10.0.2.2
ping -c 1 -W 2 10.0.2.2 >/dev/null || { echo 'VM package gateway unreachable' >&2; nft list ruleset; exit 1; }
for package in forkop luci-app-forkop; do
    wget -O "/tmp/$package.apk" "$ARTAK_MIRROR/artak/${package}_2.4.3-canary.10.apk" || { echo "VM package download failed: $package" >&2; nft list ruleset; exit 1; }
done
apk --allow-untrusted --simulate add /tmp/forkop.apk /tmp/luci-app-forkop.apk >/dev/null
apk --allow-untrusted add /tmp/forkop.apk /tmp/luci-app-forkop.apk >/dev/null
command -v timeout >/dev/null || { echo 'APK failed to install required timeout dependency' >&2; exit 1; }
wget -q -O /tmp/sing-box-extended.apk "$ARTAK_MIRROR/extended/sing-box-extended_1.14.3-extended-2.7.3_openwrt_x86_64.apk"
echo '57189d2d2fcfa108aa82e6e9f06ff7e66f71a67f0f8ab7dca16a7ff58ed7b5b0  /tmp/sing-box-extended.apk' | sha256sum -c
apk --allow-untrusted --simulate add /tmp/sing-box-extended.apk >/dev/null
apk --allow-untrusted add /tmp/sing-box-extended.apk >/dev/null
sing-box version | head -n 1
/etc/init.d/rpcd restart
echo 'E2E stage: inspect installed rpcd plugin'
ls -l /usr/libexec/rpcd/luci.artak_awg || exit 1
test -x /usr/libexec/rpcd/luci.artak_awg || { echo 'rpcd plugin is not executable' >&2; exit 1; }
/usr/libexec/rpcd/luci.artak_awg list || { echo 'rpcd plugin list failed' >&2; exit 1; }
count=0
until ubus -S list luci.artak_awg 2>/dev/null | grep -q 'luci.artak_awg'; do
    count=$((count+1)); [ "$count" -lt 60 ] || { echo 'rpcd AWG object did not appear' >&2; ubus list 2>/dev/null || :; logread | grep -i rpcd | tail -30 || :; exit 1; }
    sleep 1
done

echo 'E2E stage: create disposable local peer'
awg genkey >/tmp/e2e-client.key
awg pubkey </tmp/e2e-client.key >/tmp/e2e-client.pub
awg genkey >/tmp/e2e-peer.key
awg pubkey </tmp/e2e-peer.key >/tmp/e2e-peer.pub
ip link add e2epeer type amneziawg
awg set e2epeer private-key /tmp/e2e-peer.key listen-port 29002 peer "$(cat /tmp/e2e-client.pub)" allowed-ips 10.88.1.1/32 endpoint 127.0.0.1:29001 persistent-keepalive 2
ip netns add artak-e2e
ip link set e2epeer netns artak-e2e
ip -n artak-e2e link set lo up
ip -n artak-e2e addr add 10.88.1.2/32 dev e2epeer
ip -n artak-e2e link set e2epeer up
ip -n artak-e2e route add 10.88.1.1/32 dev e2epeer
uci set forkop.settings.awg_experimental=1
uci set forkop.e2etest=section
uci set forkop.e2etest.enabled=1
uci set forkop.e2etest.action=connection
uci add_list forkop.e2etest.fully_routed_ips=192.0.2.99
uci commit forkop
for config in forkop network; do
    delta="/tmp/.uci/$config"
    if [ -e "$delta" ]; then
        echo "E2E stage: $config UCI delta bytes=$(wc -c < "$delta")"
        # Preserve the file to exercise production handling of empty deltas.
    fi
done
printf '[Interface]\nPrivateKey = %s\nAddress = 10.88.1.1/32\nListenPort = 29001\n[Peer]\nPublicKey = %s\nEndpoint = 127.0.0.1:29002\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 2\n' "$(cat /tmp/e2e-client.key)" "$(cat /tmp/e2e-peer.pub)" >/tmp/e2e.conf
ucode -e 'let f=require("fs");let c=f.readfile("/tmp/e2e.conf");if(f.writefile("/tmp/e2e-request",sprintf("%J",{config:c,section:"e2etest"}))==null)exit(1);'

echo 'E2E stage: invoke actual rpcd import'
# Disposable VM only: capture verifier result categories before cleanup.
# No profile values, peer keys, or exception text are recorded.
ucode -e '
let f=require("fs"), p="/usr/lib/forkop/subscription/amnezia_manual_activate.uc", s=f.readfile(p);
let needle="            return type(u) == ";
if (type(s)!="string" || index(s,needle)<0) exit(1);
let injected="            let rr=require(\"subscription.amnezia_activate\").run; let dump={}; for (let fam in [\"-4\",\"-6\"]) { dump[fam+\"-rules\"]=rr([\"ip\",\"-j\",\"-N\",fam,\"rule\",\"show\"]); dump[fam+\"-routes\"]=rr([\"ip\",\"-j\",\"-N\",fam,\"route\",\"show\",\"table\",entry.table]); } require(\"fs\").writefile(\"/tmp/e2e-verify\", sprintf(\"uci=%J live=%J uci_error=%J live_error=%J table=%J priority=%J kernel=%J\",u?.ok,live?.ok,u?.error,live?.error,entry.table,entry.priority,dump));" + "\n";
if (f.writefile(p,replace(s,needle,injected+needle))==null) exit(1);
'
ucode -L /usr/lib/forkop -e 'let f=require("fs");print(sprintf("feature=%J runtime_dir=%J reload_lock=%J subscription_lock=%J forkop_pending=%J network_pending=%J\n",require("subscription.amnezia_feature").enabled(), f.stat("/var/run/forkop")?.type, f.stat("/var/run/forkop.reload.lock")?.type, f.stat("/var/run/forkop/subscription-update.lock")?.type, f.stat("/tmp/.uci/forkop")?.type, f.stat("/tmp/.uci/network")?.type));'
ubus call luci.artak_awg import_conf "$(cat /tmp/e2e-request)" >/tmp/e2e-result || { echo 'ubus import_conf call failed' >&2; exit 1; }
test "$(jsonfilter -i /tmp/e2e-result -e '@.ok')" = true || { echo "import_conf rejected: $(jsonfilter -i /tmp/e2e-result -e '@.error')" >&2; exit 1; }
count=0
while :; do
    ubus call luci.artak_awg import_status '{}' >/tmp/e2e-status || { echo 'ubus import_status call failed' >&2; exit 1; }
    state=$(jsonfilter -i /tmp/e2e-status -e '@.state')
    [ "$state" != running ] && break
    count=$((count+1)); [ "$count" -lt 120 ] || { echo 'import timed out' >&2; exit 1; }
    sleep 1
done
if [ "$state" != done ]; then
    echo "import failed: $state" >&2
    cat /tmp/e2e-verify 2>/dev/null || echo 'verification callback did not run'
    echo 'E2E stage: retry isolated worker for sanitized result'
    ucode -L /usr/lib/forkop -e 'let f=require("fs"), w=require("subscription.amnezia_manual_worker");let r=w.run(f.readfile("/tmp/e2e.conf"),"e2etest");print(sprintf("worker ok=%J error=%J cleanup_required=%J\n",r?.ok,r?.error,r?.cleanup_required));' || :
    ucode -L /usr/lib/forkop -e 'let a=require("subscription.amnezia_allocate"), c=require("uci").cursor(), r=a.choose(c,{});print(sprintf("allocator ok=%J error=%J\n",r?.ok,r?.error));let k=require("subscription.amnezia_runtime_check").check("15001","16002");print(sprintf("kernel check ok=%J error=%J\n",k?.ok,k?.error));let m=require("subscription.amnezia_mark_audit").audit([0x18003a99],{});print(sprintf("mark audit ok=%J error=%J\n",m?.ok,m?.error));' || :
    command -v timeout || echo 'timeout command missing'
    timeout 3 ip -j -N -4 rule show || echo "timeout ip failed: $?"
    timeout 3 nft -j list ruleset >/dev/null || echo "timeout nft failed: $?"
    ubus call network get_proto_handlers 2>/dev/null | grep -o '"amneziawg"' || :
    logread | grep -E 'netifd|forkop|rpcd' | tail -35 | sed -E 's/[A-Za-z0-9+\/]{42,43}=/[REDACTED]/g' || :
    exit 1
fi
iface=$(jsonfilter -i /tmp/e2e-status -e '@.name')
case "$iface" in afawg_*) ;; *) echo 'invalid interface name' >&2; exit 1;; esac
echo "E2E stage: import done, interface $iface"
awg show "$iface" latest-handshakes | awk 'NR==1 && $2>0 {ok=1} END {exit !ok}' || { echo 'missing handshake after import' >&2; exit 1; }
# This synthetic same-host peer is not a normal Internet destination. Install
# only its /32 return path so the guest can reply to the namespace probe.
ip route add 10.88.1.2/32 dev "$iface"
ip netns exec artak-e2e ping -c 3 -W 3 10.88.1.1 || { echo 'peer-to-imported interface ping failed' >&2; ip -n artak-e2e route show; ip link show "$iface"; exit 1; }

echo 'E2E stage: apply Forkop lifecycle and verify guard/config'
/etc/init.d/firewall start
/etc/init.d/forkop restart || { echo 'Forkop restart command failed' >&2; exit 1; }
count=0
while [ ! -s /etc/sing-box/config.json ]; do
    count=$((count+1)); [ "$count" -lt 60 ] || { echo 'Forkop config not generated after restart' >&2; logread | grep -E 'forkop|sing-box' | tail -50 | sed -E 's/[A-Za-z0-9+\/]{42,43}=/[REDACTED]/g' || :; exit 1; }
    sleep 1
done
count=0
until ucode -e 'let f=require("fs");try{let c=json(f.readfile("/etc/sing-box/config.json"));let n=ARGV[0];if(filter(c.outbounds||[],x=>x.bind_interface==n && x.routing_mark!=null)[0])exit(0);}catch(e){} exit(1);' "$iface"; do
    count=$((count+1)); [ "$count" -lt 60 ] || { echo 'generated config lacks AWG outbound or mark' >&2; logread | grep -E 'forkop|sing-box' | tail -60 | sed -E 's/[A-Za-z0-9+\/]{42,43}=/[REDACTED]/g' || :; exit 1; }
    sleep 1
done
nft list table inet ForkopTable | grep -Fq "$iface" || { echo 'nft guard does not mention AWG interface' >&2; exit 1; }
echo ARTAK_E2E_PASSED
