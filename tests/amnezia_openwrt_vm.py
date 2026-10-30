#!/usr/bin/env python3
"""Run the netifd/kernel test in a disposable OpenWrt x86 VM via serial."""
import base64
import http.server
import os
import pathlib
import re
import subprocess
import sys
import threading
import urllib.request

import pexpect

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Mirror(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Only mirror fixed upstream origins; never expose arbitrary host files
        # or accept arbitrary URL targets from the disposable guest.
        path = self.path.split('?', 1)[0]
        if path.startswith('/openwrt/releases/25.12.6/') and '..' not in path:
            url = 'https://downloads.openwrt.org' + path[len('/openwrt'):]
        elif re.fullmatch(r'/2grey/[A-Za-z0-9_.-]+\.apk', path):
            url = 'https://github.com/2Grey/awg-openwrt/releases/download/v25.12.6/' + path.rsplit('/', 1)[1]
        elif path == '/extended/sing-box-extended_1.14.3-extended-2.7.3_openwrt_x86_64.apk':
            url = 'https://github.com/shtorm-7/sing-box-extended/releases/download/v1.14.3-extended-2.7.3/' + path.rsplit('/', 1)[1]
        elif re.fullmatch(r'/artak/(forkop|luci-app-forkop)_2\.4\.3-canary\.11\.apk', path) and os.getenv('ARTAK_E2E_PACKAGES'):
            package = pathlib.Path(os.environ['ARTAK_E2E_PACKAGES']) / path.rsplit('/', 1)[1]
            try:
                data = package.read_bytes()
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except OSError:
                self.send_error(404)
            return
        else:
            self.send_error(404)
            return
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'ArtakFork-VM-test'})
            with urllib.request.urlopen(req, timeout=90) as upstream:
                data = upstream.read(64 * 1024 * 1024 + 1)
            if len(data) > 64 * 1024 * 1024:
                raise ValueError('upstream response too large')
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception:
            self.send_error(502)

    def log_message(self, format, *args):
        pass


def command(vm, text, timeout=90):
    vm.sendline(text + "; printf '\\n__AWG_EXIT_%s__\\n' \"$?\"")
    vm.expect(r'__AWG_EXIT_(\d+)__', timeout=timeout)
    status = int(vm.match.group(1))
    if status:
        raise RuntimeError(f'OpenWrt guest command failed with status {status}')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: amnezia_openwrt_vm.py DISPOSABLE_RAW_IMAGE')
    image = str(pathlib.Path(sys.argv[1]).resolve())
    mirror = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Mirror)
    threading.Thread(target=mirror.serve_forever, daemon=True).start()
    cmd = ['qemu-system-x86_64', '-machine', 'accel=tcg', '-m', '384', '-smp', '2',
           '-drive', f'file={image},format=raw,if=virtio', '-netdev', 'user,id=net0',
           '-device', 'virtio-net-pci,netdev=net0', '-nographic', '-monitor', 'none', '-no-reboot']
    vm = pexpect.spawn(cmd[0], cmd[1:], encoding='utf-8', timeout=180)
    try:
        vm.expect('Please press Enter to activate this console', timeout=180)
        vm.sendline('')
        # The hostname may still be "(none)" when the early serial shell
        # starts, before OpenWrt's system service sets it to OpenWrt.
        vm.expect(r'root@[^:\r\n]+:[^\r\n]*#', timeout=90)
        def upload(local_name, guest_name):
            encoded = base64.b64encode((ROOT / 'tests' / local_name).read_bytes()).decode('ascii')
            command(vm, ': > /tmp/artak-guest.b64')
            # BusyBox ash/serial line editing truncates long interactive lines.
            for pos in range(0, len(encoded), 128):
                command(vm, "printf '%s' '" + encoded[pos:pos + 128] + "' >> /tmp/artak-guest.b64")
            # OpenWrt's default BusyBox image need not include base64(1).
            command(vm, "ucode -e 'let f=require(\"fs\");let b=f.readfile(\"/tmp/artak-guest.b64\");let d=b64dec(b);if(d==null||f.writefile(\"" + guest_name + "\",d)==null)exit(1);'")
        upload('amnezia_openwrt_guest.sh', '/tmp/artak-guest.sh')
        upload('openwrt_fw4_guard.sh', '/tmp/artak-fw4.sh')
        upload('openwrt_nft_create_only.sh', '/tmp/artak-nft-create.sh')
        command(vm, f'ARTAK_MIRROR=http://10.0.2.2:{mirror.server_port} sh /tmp/artak-guest.sh', timeout=600)
        if 'AWG_VM_ALL_TESTS_PASSED' not in vm.before:
            raise RuntimeError('Guest completed without success marker')
        print('OpenWrt VM: both netifd/kernel AWG profiles passed')
        # The guest provisioning deliberately stopped fw4 while using LAN as
        # an uplink; load it before the subsequent real reload test.
        command(vm, '/etc/init.d/firewall start', timeout=120)
        command(vm, 'ARTAK_DISPOSABLE_VM=1 sh /tmp/artak-fw4.sh', timeout=120)
        print('OpenWrt VM: stock firewall reload retained the independent test guard')
        command(vm, 'ARTAK_DISPOSABLE_VM=1 sh /tmp/artak-nft-create.sh', timeout=120)
        print('OpenWrt VM: nft create-only collision behavior passed')
        if os.getenv('ARTAK_E2E_PACKAGES'):
            upload('amnezia_artak_e2e_guest.sh', '/tmp/artak-e2e.sh')
            command(vm, f'ARTAK_MIRROR=http://10.0.2.2:{mirror.server_port} ARTAK_DISPOSABLE_VM=1 sh /tmp/artak-e2e.sh', timeout=600)
            if 'ARTAK_E2E_PASSED' not in vm.before:
                raise RuntimeError('ArtakFork end-to-end test did not reach its success marker')
            print('OpenWrt VM: ArtakFork AWG end-to-end passed')
    except Exception:
        # Guest script uses generated throwaway keys and never prints them.
        print('OpenWrt guest serial tail:', str(vm.before)[-5000:], file=sys.stderr)
        raise
    finally:
        vm.close(force=True)
        mirror.shutdown()
        mirror.server_close()


if __name__ == '__main__':
    main()
