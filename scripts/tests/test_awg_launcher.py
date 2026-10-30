"""Exercise the exact RPC launcher shell under pipes and without a TTY."""
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which('sh'), 'POSIX shell required')
class LauncherTest(unittest.TestCase):
    def test_returns_before_worker_and_survives_parent_exit(self):
        source = (ROOT / 'forkop/files/usr/lib/subscription/amnezia_preflight_rpc.uc').read_text()
        match = re.search(r'fs\.popen\("([^"\n]+amnezia_job_worker\.uc[^"\n]+)", "r"\)', source)
        self.assertIsNotNone(match)
        command = match.group(1)
        self.assertNotIn('config', command)
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            marker = directory / 'done'
            mock = directory / 'ucode'
            mock.write_text('#!/bin/sh\nsleep 2\nprintf completed > "$AWG_TEST_MARKER"\n')
            mock.chmod(0o755)
            env = dict(os.environ, PATH=tmp + ':' + os.environ['PATH'], AWG_TEST_MARKER=str(marker))
            begin = time.monotonic()
            result = subprocess.run(['sh', '-c', command], stdin=subprocess.DEVNULL,
                                    capture_output=True, text=True, env=env, timeout=5,
                                    start_new_session=True, check=True)
            self.assertLess(time.monotonic() - begin, 1.8)
            self.assertTrue(result.stdout.strip().isdigit())
            self.assertEqual(result.stderr, '')
            for _ in range(50):
                if marker.exists(): break
                time.sleep(.1)
            self.assertEqual(marker.read_text(), 'completed')


if __name__ == '__main__':
    unittest.main()
