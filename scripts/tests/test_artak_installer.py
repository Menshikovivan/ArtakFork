"""Offline runtime tests: Linux root + busybox-static; no real downloads or packages."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

INSTALLER = Path(__file__).resolve().parents[2] / 'artak-install.sh'
VERSION = '2.4.3-canary.7'
ENGINE = 'sing-box-extended_1.14.3-extended-2.7.3_openwrt_aarch64_cortex-a53.apk'
PACKAGES = ['forkop', 'luci-app-forkop', 'luci-i18n-forkop-ru']
SUPPORTED = sys.platform.startswith('linux') and hasattr(os, 'geteuid') and os.geteuid() == 0

@unittest.skipUnless(SUPPORTED, 'Requires Linux root and busybox-static')
class InstallerRuntime(unittest.TestCase):
    def setUp(self):
        busybox = shutil.which('busybox')
        self.assertIsNotNone(busybox, 'Install busybox-static')
        temporary = tempfile.TemporaryDirectory(prefix='artak-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ['bin', 'tmp', 'root', 'etc/init.d', 'fixtures', 'dev']:
            (self.root / name).mkdir(parents=True, exist_ok=True)
        # Redirections only; no host device is exposed inside the test root.
        (self.root / 'dev/null').touch()
        shutil.copyfile(busybox, self.root / 'bin/busybox')
        (self.root / 'bin/busybox').chmod(0o755)
        for name in ['sh', 'id', 'sha256sum', 'mktemp', 'awk', 'rm', 'mkdir', 'rmdir', 'chmod', 'date', 'cp', 'cat', 'grep']:
            (self.root / 'bin' / name).symlink_to('busybox')
        shutil.copyfile(INSTALLER, self.root / 'installer.sh')
        self.release('25.12.6')
        self.script('bin/apk', '''if [ "$1" = info ]; then [ -e /has-forkop ]; exit $?; fi
if [ "$1" = update ]; then echo update >> /events; exit 0; fi
if [ "$1" = --simulate ]; then
    echo "simulate:$*" >> /events
    [ ! -e /simulate-fail ]; exit $?
fi
printf 'install:%s\\n' "$*" >> /events
[ "$1" = add ] && [ "$2" = --allow-untrusted ] || exit 90
shift 2
for file in "$@"; do [ -f "$file" ] || exit 91; done
''')
        self.script('bin/sing-box', 'echo "sing-box version 1.14.3-extended-2.7.3"\n')
        self.script('etc/init.d/sing-box', 'echo "engine:$1" >> /events\n')
        self.script('bin/sysupgrade', '[ "$1" = -b ]\necho backup >> /events\necho mock-backup > "$2"\n')
        self.script('etc/init.d/forkop', 'echo "forkop:$1" >> /events\n')
        self.script('bin/ubus', '''[ "$1" = call ] && [ "$2" = network ] && [ "$3" = get_proto_handlers ] || exit 1
if [ -e /awg-no-handler ]; then echo '{}'; else echo '{"amneziawg":{}}'; fi
''')
        self.script('bin/sleep', 'exit 0\n')
        self.script('etc/init.d/network', '''echo "network:$1" >> /events
[ ! -e /network-fail ] || exit 1
[ -e /network-preserve ] || rm -f /awg-no-handler
''')
        self.script('bin/wget', '''[ "$1" = -O ]
case "$3" in
https://github.com/Menshikovivan/ArtakFork/releases/download/2.4.3-canary.7/*) ;;
*) exit 95;;
esac
echo "download:${3##*/}" >> /events
cp "/fixtures/${3##*/}" "$2"
''')
        hashes = []
        for name in [ENGINE] + [f'{p}_{VERSION}.apk' for p in PACKAGES] + [f'upstream-{p}_1.0.5.apk' for p in PACKAGES]:
            data = f'offline dummy package: {name}\n'.encode()
            (self.root / 'fixtures' / name).write_bytes(data)
            hashes.append(f'{hashlib.sha256(data).hexdigest()}  {name}\n')
        helper = b'#!/bin/sh\necho "awg-deps:$1" >> /events\n'
        (self.root / 'fixtures/install-awg-dependencies.sh').write_bytes(helper)
        hashes.append(f'{hashlib.sha256(helper).hexdigest()}  install-awg-dependencies.sh\n')
        (self.root / 'fixtures/SHA256SUMS').write_text(''.join(hashes))

    def script(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/sh\nset -eu\n' + body)
        path.chmod(0o755)

    def release(self, version):
        (self.root / 'etc/openwrt_release').write_text(f"DISTRIB_RELEASE='{version}'\nDISTRIB_ARCH='aarch64_cortex-a53'\nDISTRIB_TARGET='mediatek/filogic'\n")

    def run_installer(self, *args):
        return subprocess.run(['chroot', str(self.root), '/bin/sh', '/installer.sh', *args],
                              env={'PATH': '/bin:/usr/bin:/usr/sbin:/sbin'},
                              text=True, capture_output=True, timeout=20)

    def events(self):
        path = self.root / 'events'
        return path.read_text().splitlines() if path.exists() else []

    def no_mutations(self):
        self.assertFalse(any(e in ['backup', 'update'] or e.startswith(('install:', 'simulate:', 'engine:', 'forkop:')) for e in self.events()))
        self.assertFalse((self.root / 'root/artakfork-backups').exists())

    def test_check(self):
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.events()), 9)
        self.assertTrue(all(e.startswith('download:') for e in self.events()))
        self.assertIn('downloaded files verified', result.stdout)
        self.no_mutations()

    def test_fresh_bootstrap(self):
        (self.root / 'bin/sing-box').unlink()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events()[9:]
        self.assertEqual(events[:2], ['backup', 'update'])
        self.assertTrue(events[2].startswith('simulate:'))
        self.assertTrue(events[3].startswith('simulate:'))
        self.assertIn('awg-deps:' + VERSION, events)
        installs = [e for e in events if e.startswith('install:')]
        self.assertEqual(len(installs), 3)
        self.assertEqual(installs[0], 'install:add --allow-untrusted ./' + ENGINE)
        self.assertIn('./upstream-forkop_1.0.5.apk', installs[1])
        self.assertIn('./forkop_' + VERSION + '.apk', installs[2])
        self.assertEqual(events[-1], 'forkop:restart')
        self.assertIn('engine:disable', events)
        backups = list((self.root / 'root/artakfork-backups').glob('*.tar.gz'))
        self.assertEqual(len(backups), 1)
        self.assertGreater(backups[0].stat().st_size, 0)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_missing_awg_handler_schedules_network_then_forkop(self):
        (self.root / 'awg-no-handler').touch()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('SSH and Wi-Fi may disconnect', result.stdout)
        log = self.root / 'root/artakfork-backups/awg-network-restart.log'
        for _ in range(100):
            if log.exists() and 'AWG handler is available' in log.read_text(): break
            time.sleep(.05)
        events = self.events()
        self.assertIn('network:restart', events)
        self.assertIn('forkop:restart', events)
        self.assertLess(events.index('network:restart'), events.index('forkop:restart'))
        self.assertIn('AWG handler is available', log.read_text())

    def test_failed_network_restart_does_not_start_forkop(self):
        (self.root / 'awg-no-handler').touch()
        (self.root / 'network-fail').touch()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for _ in range(100):
            p = self.root / 'root/artakfork-backups/awg-network-restart.log'
            if p.exists() and 'network restart failed' in p.read_text(): break
            time.sleep(.05)
        self.assertIn('network:restart', self.events())
        self.assertNotIn('forkop:restart', self.events())
        self.assertIn('network restart failed', p.read_text())

    def test_handler_timeout_does_not_start_forkop(self):
        (self.root / 'awg-no-handler').touch()
        (self.root / 'network-preserve').touch()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        p = self.root / 'root/artakfork-backups/awg-network-restart.log'
        for _ in range(100):
            if p.exists() and 'handler did not become available' in p.read_text(): break
            time.sleep(.05)
        self.assertNotIn('forkop:restart', self.events())
        self.assertIn('handler did not become available', p.read_text())

    def test_existing_matching_engine_skips_base_and_engine(self):
        (self.root / 'has-forkop').touch()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events()[9:]
        self.assertIn('awg-deps:' + VERSION, events)
        self.assertEqual(events[:2], ['backup', 'update'])
        installs = [e for e in events if e.startswith('install:')]
        expected = 'install:add --allow-untrusted ' + ' '.join(f'./{p}_{VERSION}.apk' for p in PACKAGES)
        self.assertEqual(installs, [expected])
        self.assertNotIn('forkop:stop', events)
        self.assertNotIn('engine:stop', events)
        self.assertIn('engine:disable', events)
        self.assertEqual(events[-1], 'forkop:restart')

    def test_missing_forkop_matching_engine_installs_base_and_own_only(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events()[9:]
        self.assertEqual(events[:2], ['backup', 'update'])
        installs = [e for e in events if e.startswith('install:')]
        expected_base = 'install:add --allow-untrusted ' + ' '.join(
            f'./upstream-{p}_1.0.5.apk' for p in PACKAGES)
        expected_own = 'install:add --allow-untrusted ' + ' '.join(
            f'./{p}_{VERSION}.apk' for p in PACKAGES)
        self.assertEqual(installs, [expected_base, expected_own])
        self.assertNotIn('forkop:stop', events)
        self.assertNotIn('engine:stop', events)
        self.assertIn('engine:disable', events)
        self.assertEqual(events[-1], 'forkop:restart')

    def test_simulation_failure_leaves_services_and_packages_untouched(self):
        (self.root / 'simulate-fail').touch()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        events = self.events()[9:]
        self.assertEqual(events[:2], ['backup', 'update'])
        self.assertEqual(len([e for e in events if e.startswith('simulate:')]), 1)
        self.assertFalse(any(e.startswith(('install:', 'forkop:', 'engine:')) for e in events))

    def test_corrupt_hash(self):
        (self.root / 'fixtures' / f'forkop_{VERSION}.apk').write_bytes(b'corrupted')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Checksum failed', result.stderr)
        self.no_mutations()

    def test_other_release(self):
        self.release('24.10.4')
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertEqual(self.events(), [])
        self.no_mutations()

    def test_unsupported_architecture(self):
        path = self.root / 'etc/openwrt_release'
        path.write_text("DISTRIB_RELEASE='25.12.6'\nDISTRIB_ARCH='x86_64'\n")
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertEqual(self.events(), [])
        self.no_mutations()

if __name__ == '__main__':
    unittest.main()
