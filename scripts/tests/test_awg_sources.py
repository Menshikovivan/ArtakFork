import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_awg_sources as mod


def archive(paths):
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode='w:gz') as t:
        for name in paths:
            data = b'test source'
            item = tarfile.TarInfo('source/' + name)
            item.size = len(data)
            t.addfile(item, io.BytesIO(data))
    return out.getvalue()


class SourcesTest(unittest.TestCase):
    def test_prepares_pinned_sources_and_manifest(self):
        def api(path):
            return {'sha': next(s[2] for s in mod.SOURCES if path == s[0] + '/commits/' + s[1])}
        def fetch(url):
            spec = next(s for s in mod.SOURCES if url.endswith('/' + s[2]))
            return archive(spec[4])
        with tempfile.TemporaryDirectory() as temp, patch.object(mod, 'api', api), patch.object(mod, 'fetch', fetch):
            mod.prepare(Path(temp))
            manifest = json.loads((Path(temp) / 'amneziawg-upstream-sources.json').read_text())
            self.assertEqual([s['commit'] for s in manifest['sources']], [s[2] for s in mod.SOURCES])
            self.assertTrue(all((Path(temp) / s[3]).is_file() for s in mod.SOURCES))

    def test_rejects_changed_tag_and_incomplete_archive(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(mod, 'api', return_value={'sha': '0' * 40}):
            with self.assertRaisesRegex(ValueError, 'source tag'):
                mod.prepare(Path(temp))
        with self.assertRaises(ValueError):
            mod.checked_archive(archive(['COPYING']), ('COPYING', 'src/config.c'))

    def test_rejects_parent_paths_and_symlink_for_required_file(self):
        with self.assertRaises(ValueError):
            mod.checked_archive(archive(['COPYING', '../escape']), ('COPYING',))
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode='w:gz') as t:
            item = tarfile.TarInfo('source/COPYING')
            item.type = tarfile.SYMTYPE
            item.linkname = '/etc/passwd'
            t.addfile(item)
        with self.assertRaises(ValueError):
            mod.checked_archive(out.getvalue(), ('COPYING',))


if __name__ == '__main__':
    unittest.main()
