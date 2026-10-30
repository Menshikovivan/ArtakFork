#!/usr/bin/env python3
"""Run the netifd/kernel test in a disposable OpenWrt x86 VM via serial."""
import base64
import pathlib
import subprocess
import sys

import pexpect

ROOT = pathlib.Path(__file__).resolve().parents[1]


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
            command(vm, 'base64 -d /tmp/artak-guest.b64 > ' + guest_name)
        upload('amnezia_openwrt_guest.sh', '/tmp/artak-guest.sh')
        upload('openwrt_fw4_guard.sh', '/tmp/artak-fw4.sh')
        command(vm, 'sh /tmp/artak-guest.sh', timeout=600)
        if 'AWG_VM_ALL_TESTS_PASSED' not in vm.before:
            raise RuntimeError('Guest completed without success marker')
        print('OpenWrt VM: both netifd/kernel AWG profiles passed')
        command(vm, 'ARTAK_DISPOSABLE_VM=1 sh /tmp/artak-fw4.sh', timeout=120)
        print('OpenWrt VM: stock firewall reload retained the independent test guard')
    except Exception:
        # Guest script uses generated throwaway keys and never prints them.
        print('OpenWrt guest serial tail:', str(vm.before)[-5000:], file=sys.stderr)
        raise
    finally:
        vm.close(force=True)


if __name__ == '__main__':
    main()
