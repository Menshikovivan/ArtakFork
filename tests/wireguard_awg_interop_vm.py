#!/usr/bin/env python3
"""Run an isolated ordinary WireGuard vs AmneziaWG kernel test on OpenWrt."""
import base64
import os
import pathlib
import sys
import threading
import http.server

import pexpect
from amnezia_openwrt_vm import Mirror, command

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: wireguard_awg_interop_vm.py DISPOSABLE_RAW_IMAGE')
    image = str(pathlib.Path(sys.argv[1]).resolve())
    mirror = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Mirror)
    threading.Thread(target=mirror.serve_forever, daemon=True).start()
    args = ['-machine', 'accel=tcg', '-m', '384', '-smp', '2',
            '-drive', f'file={image},format=raw,if=virtio', '-netdev', 'user,id=net0',
            '-device', 'virtio-net-pci,netdev=net0', '-nographic', '-monitor', 'none', '-no-reboot']
    vm = pexpect.spawn('qemu-system-x86_64', args, encoding='utf-8', timeout=180)
    try:
        vm.expect('Please press Enter to activate this console', timeout=180)
        vm.sendline('')
        vm.expect(r'root@[^:\r\n]+:[^\r\n]*#', timeout=90)
        def upload(source, destination):
            encoded = base64.b64encode((ROOT / 'tests' / source).read_bytes()).decode('ascii')
            command(vm, ': > /tmp/artak-guest.b64')
            for pos in range(0, len(encoded), 128):
                command(vm, "printf '%s' '" + encoded[pos:pos + 128] + "' >> /tmp/artak-guest.b64")
            command(vm, "ucode -e 'let f=require(\"fs\");let b=f.readfile(\"/tmp/artak-guest.b64\");let d=b64dec(b);if(d==null||f.writefile(\"" + destination + "\",d)==null)exit(1);'")
        upload('amnezia_openwrt_guest.sh', '/tmp/artak-provision.sh')
        upload('wireguard_awg_interop_guest.sh', '/tmp/interop.sh')
        command(vm, f'ARTAK_MIRROR=http://10.0.2.2:{mirror.server_port} sh /tmp/artak-provision.sh', timeout=600)
        command(vm, 'ARTAK_DISPOSABLE_VM=1 sh /tmp/interop.sh', timeout=300)
        if 'WIREGUARD_AWG_INTEROP_PASSED' not in vm.before:
            raise RuntimeError('WireGuard interoperability success marker missing')
        print('Stock WireGuard and non-obfuscated AmneziaWG kernel tunnel passed')
    except Exception:
        print('OpenWrt guest serial tail:', str(vm.before)[-5000:], file=sys.stderr)
        raise
    finally:
        vm.close(force=True)
        mirror.shutdown()
        mirror.server_close()

if __name__ == '__main__':
    main()
