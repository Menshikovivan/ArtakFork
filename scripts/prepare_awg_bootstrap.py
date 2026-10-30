#!/usr/bin/env python3
"""Mirror reviewed AmneziaWG packages and corresponding source for a release."""
import hashlib
import json
from pathlib import Path
import sys

from prepare_artak_bootstrap import api, fetch

REPO = '2Grey/awg-openwrt'
TAG = 'v25.12.6'
COMMIT = '3f3ec68d594c8e965c988af75ac5314616229c88'
SUFFIX = 'v25.12.6_aarch64_cortex-a53_mediatek_filogic.apk'
HASHES = {
    'amneziawg-tools': '999cb2f8d20c82e56a47283813133e9c04ea3b5c52f8bd7d49af7aa523d3e8d4',
    'kmod-amneziawg': 'f8bce57fcd5d128db758cb32ec98f62ee6ca54adec17541c97fa3f2d51eeb7e8',
    'luci-proto-amneziawg': '2bd2a49fa57769624aa295c38cc807f531802836e118845ff56bc5cd61cc1abe',
}

def prepare(output):
    release = api(f'{REPO}/releases/tags/{TAG}')
    if release.get('draft') or release.get('prerelease') or release.get('tag_name') != TAG:
        raise ValueError('Unexpected upstream AWG release')
    if api(f'{REPO}/commits/{TAG}')['sha'] != COMMIT:
        raise ValueError('Upstream AWG source tag changed')
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    for package, expected in HASHES.items():
        name = f'{package}_{SUFFIX}'
        matches = [a for a in release['assets'] if a['name'] == name]
        url = f'https://github.com/{REPO}/releases/download/{TAG}/{name}'
        if len(matches) != 1 or matches[0]['browser_download_url'] != url or matches[0].get('digest') != 'sha256:' + expected:
            raise ValueError('Missing or changed AWG asset: ' + name)
        data = fetch(url)
        if len(data) != matches[0]['size'] or hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('AWG asset checksum mismatch: ' + name)
        (output / name).write_bytes(data)
        assets.append({'name': name, 'sha256': expected, 'url': url})
    source_url = f'https://codeload.github.com/{REPO}/tar.gz/{COMMIT}'
    source = fetch(source_url)
    (output / 'amneziawg-openwrt-source.tar.gz').write_bytes(source)
    (output / 'amneziawg-sources.json').write_text(json.dumps({'repository': REPO, 'tag': TAG, 'commit': COMMIT, 'assets': assets, 'source_url': source_url, 'source_sha256': hashlib.sha256(source).hexdigest()}, indent=2) + '\n')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: prepare_awg_bootstrap.py OUTPUT_DIRECTORY')
    prepare(Path(sys.argv[1]))
