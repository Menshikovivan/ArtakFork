import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('awg_bootstrap', ROOT / 'prepare_awg_bootstrap.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class MirrorTest(unittest.TestCase):
    def test_mirror_and_reject_changed_asset(self):
        data = {k: k.encode() for k in mod.HASHES}
        hashes = {k: hashlib.sha256(v).hexdigest() for k, v in data.items()}
        assets = [{'name': f'{k}_{mod.SUFFIX}', 'browser_download_url': f'https://github.com/{mod.REPO}/releases/download/{mod.TAG}/{k}_{mod.SUFFIX}', 'digest': 'sha256:' + hashes[k], 'size': len(v)} for k, v in data.items()]
        def api(path):
            return {'sha': mod.COMMIT} if '/commits/' in path else {'tag_name': mod.TAG, 'assets': assets}
        def fetch(url):
            return b'source' if 'codeload' in url else data[url.rsplit('/', 1)[1].split('_v25')[0]]
        with tempfile.TemporaryDirectory() as tmp, patch.object(mod, 'HASHES', hashes), patch.object(mod, 'api', api), patch.object(mod, 'fetch', fetch):
            mod.prepare(Path(tmp))
            self.assertTrue((Path(tmp) / 'amneziawg-sources.json').exists())
            assets[0]['digest'] = 'sha256:' + '0' * 64
            with self.assertRaises(ValueError):
                mod.prepare(Path(tmp))

if __name__ == '__main__':
    unittest.main()
