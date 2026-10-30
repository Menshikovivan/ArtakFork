#!/usr/bin/env python3
"""Mirror the upstream sources referenced by the pinned 2Grey AWG recipes."""
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tarfile

from prepare_artak_bootstrap import api, fetch

SOURCES = (
    ('amnezia-vpn/amneziawg-tools', 'v3.1.20260812',
     'ee0f0a9aa34ff0a0da4b3433b9512781cfe02843', 'amneziawg-tools-source.tar.gz',
     ('src/config.c', 'src/encoding.c', 'COPYING')),
    ('amnezia-vpn/amneziawg-linux-kernel-module', 'v3.1.20260906',
     '4569c4c67f3a57414969260cafbbd04694fbaae0', 'amneziawg-kmod-source.tar.gz',
     ('src/netlink.c', 'src/device.h', 'COPYING')),
)


def checked_archive(data, required):
    # Never extract archive members. Check expected source and licence paths
    # under exactly one top-level directory before publishing the archive.
    if not data or len(data) > 128 * 1024 * 1024:
        raise ValueError('Invalid source archive size')
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            names = archive.getnames()
            roots = {name.split('/', 1)[0] for name in names if name}
            if len(roots) != 1:
                raise ValueError('Unexpected source archive roots')
            root = next(iter(roots))
            for path in required:
                member = archive.getmember(root + '/' + path)
                if not member.isfile():
                    raise ValueError('Expected source file is not regular')
            if any(name.startswith('/') or '..' in name.split('/') for name in names):
                raise ValueError('Unsafe source archive path')
    except (tarfile.TarError, KeyError) as exc:
        raise ValueError('Invalid or incomplete source archive') from exc


def prepare(output):
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for repo, tag, commit, filename, required in SOURCES:
        if not re.fullmatch(r'[0-9a-f]{40}', commit):
            raise ValueError('Invalid source commit pin')
        resolved = api(f'{repo}/commits/{tag}').get('sha')
        if resolved != commit:
            raise ValueError(f'{repo}: source tag no longer matches reviewed commit')
        url = f'https://codeload.github.com/{repo}/tar.gz/{commit}'
        data = fetch(url)
        checked_archive(data, required)
        digest = hashlib.sha256(data).hexdigest()
        (output / filename).write_bytes(data)
        records.append({'repository': repo, 'tag': tag, 'commit': commit,
                        'url': url, 'file': filename, 'bytes': len(data), 'sha256': digest})
    manifest = {'schema': 1, 'recipes': '2Grey/awg-openwrt@3f3ec68d594c8e965c988af75ac5314616229c88',
                'note': 'Source archives follow recipe pins; binary reproducibility is not verified.',
                'sources': records}
    (output / 'amneziawg-upstream-sources.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: prepare_awg_sources.py OUTPUT_DIRECTORY')
    prepare(Path(sys.argv[1]))
