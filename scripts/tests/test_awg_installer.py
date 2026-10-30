import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'install-awg-dependencies.sh'


@unittest.skipUnless(shutil.which('sh'), 'POSIX shell required')
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = pathlib.Path(self.temp.name)
        self.bin = self.path / 'bin'
        self.bin.mkdir()
        (self.path / 'release').write_text('DISTRIB_ID=OpenWrt\nDISTRIB_RELEASE=25.12.6\nDISTRIB_TARGET=mediatek/filogic\n')
        self.log = self.path / 'commands'
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'], TEST_LOG=str(self.log))
        script = SCRIPT.read_text().replace('/etc/openwrt_release', str(self.path / 'release'))
        script = script.replace('/tmp/artak-awg.XXXXXX', str(self.path / 'temp.XXXXXX'))
        script = script.replace('/root/artak-awg-backup-', str(self.path / 'backup-'))
        self.script = self.path / 'install.sh'
        self.script.write_text(script)
        self.mock('id', 'echo 0')
        self.mock('uname', 'echo aarch64')
        self.mock('wget', 'printf data > "$3"')
        self.mock('sha256sum', '''case "$1" in
*amneziawg-tools*) h=999cb2f8d20c82e56a47283813133e9c04ea3b5c52f8bd7d49af7aa523d3e8d4;;
*kmod-amneziawg*) h=f8bce57fcd5d128db758cb32ec98f62ee6ca54adec17541c97fa3f2d51eeb7e8;;
*) h=2bd2a49fa57769624aa295c38cc807f531802836e118845ff56bc5cd61cc1abe;; esac
echo "$h  $1"''')
        self.mock('sysupgrade', 'echo backup >> "$TEST_LOG"; echo backup > "$2"')
        self.mock('apk', 'echo "apk $*" >> "$TEST_LOG"; case "$*" in *--simulate*) exit "${SIM_FAIL:-0}";; esac')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self):
        return subprocess.run(['sh', str(self.script)], env=self.env, capture_output=True, text=True)

    def test_success_simulates_then_backs_up_then_installs_without_force(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log.read_text().splitlines()
        self.assertIn('--simulate add', lines[0])
        self.assertEqual(lines[1], 'backup')
        self.assertIn(' add ', lines[2])
        self.assertNotIn('--force', '\n'.join(lines))

    def test_simulation_failure_prevents_backup_and_install(self):
        self.env['SIM_FAIL'] = '1'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(len(self.log.read_text().splitlines()), 1)

    def test_hash_mismatch_prevents_apk(self):
        self.mock('sha256sum', 'echo "bad  $1"')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.log.exists())

    def test_wrong_platform_prevents_apk(self):
        (self.path / 'release').write_text('DISTRIB_ID=OpenWrt\nDISTRIB_RELEASE=25.12.6\nDISTRIB_TARGET=wrong/target\n')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
