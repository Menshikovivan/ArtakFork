"""Offline runtime tests: Linux root + busybox-static; no real downloads or packages."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[2] / 'artak-install.sh'
VERSION = '2.4.3-canary.2'
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
        for name in ['sh', 'id', 'sha256sum', 'mktemp', 'awk', 'rm', 'mkdir', 'chmod', 'date', 'cp']:
            (self.root / 'bin' / name).symlink_to('busybox')
        shutil.copyfile(INSTALLER, self.root / 'installer.sh')
        self.release('25.12.6')
        self.script('bin/apk', '''if [ "$1" = info ]; then [ ! -e /missing-forkop ]; exit $?; fi
printf 'install:%s\\n' "$*" >> /events
[ "$1" = add ] && [ "$2" = --allow-untrusted ] && [ "$#" = 5 ] || exit 90
shift 2
for file in "$@"; do [ -f "$file" ] || exit 91; done
''')
        self.script('bin/sing-box', 'exit 0\n')
        self.script('bin/sysupgrade', '[ "$1" = -b ]\necho backup >> /events\necho mock-backup > "$2"\n')
        self.script('etc/init.d/forkop', '[ "$1" = restart ]\necho restart >> /events\n')
        self.script('bin/wget', '''[ "$1" = -O ]
case "$3" in
https://github.com/Menshikovivan/ArtakFork/releases/download/2.4.3-canary.2/*) ;;
*) exit 95;;
esac
echo "download:${3##*/}" >> /events
cp "/fixtures/${3##*/}" "$2"
''')
        hashes = []
        for package in PACKAGES:
            name = f'{package}_{VERSION}.apk'
            data = f'offline dummy package: {package}\n'.encode()
            (self.root / 'fixtures' / name).write_bytes(data)
            hashes.append(f'{hashlib.sha256(data).hexdigest()}  {name}\n')
        (self.root / 'fixtures/SHA256SUMS').write_text(''.join(hashes))

    def script(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/sh\nset -eu\n' + body)
        path.chmod(0o755)

    def release(self, version):
        (self.root / 'etc/openwrt_release').write_text(f"DISTRIB_RELEASE='{version}'\n")

    def run_installer(self, *args):
        return subprocess.run(['chroot', str(self.root), '/bin/sh', '/installer.sh', *args],
                              env={'PATH': '/bin:/usr/bin:/usr/sbin:/sbin'},
                              text=True, capture_output=True, timeout=20)

    def events(self):
        path = self.root / 'events'
        return path.read_text().splitlines() if path.exists() else []

    def no_mutations(self):
        self.assertFalse(any(e in ['backup', 'restart'] or e.startswith('install:') for e in self.events()))
        self.assertFalse((self.root / 'root/artakfork-backups').exists())

    def test_check(self):
        result = self.run_installer('--check')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.events()), 4)
        self.assertTrue(all(e.startswith('download:') for e in self.events()))
        self.assertIn('all three APK checksums verified', result.stdout)
        self.no_mutations()

    def test_install(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        expected = 'install:add --allow-untrusted ' + ' '.join(f'./{p}_{VERSION}.apk' for p in PACKAGES)
        self.assertEqual(self.events()[4:], ['backup', expected, 'restart'])
        backups = list((self.root / 'root/artakfork-backups').glob('*.tar.gz'))
        self.assertEqual(len(backups), 1)
        self.assertGreater(backups[0].stat().st_size, 0)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

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

    def test_missing_forkop(self):
        (self.root / 'missing-forkop').touch()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Install Forkop first', result.stderr)
        self.assertEqual(self.events(), [])
        self.no_mutations()

if __name__ == '__main__':
    unittest.main()
