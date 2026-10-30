#!/usr/bin/env python3
"""Check ordering of the guarded experimental lifecycle path.

These source-level checks supplement, but cannot replace, a netifd boot test.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
text = (root / 'forkop/files/usr/lib/service/lifecycle.uc').read_text(encoding='utf-8')
startup = text[text.index('function start_main()'):text.index('function refresh_rulesets_after_start()')]
rebuild = text[text.index('function nft_rebuild_runtime()'):text.index('function nft_candidate_begin()')]
assert startup.index('acquire_start_subscription_update_lock()') < startup.index('amnezia-snapshot-build')
assert startup.index('acquire_awg_network_lock()') < startup.index('amnezia-snapshot-build')
assert startup.index('amnezia-snapshot-build') < startup.index('nft_candidate_begin()')
assert startup.index('nft_candidate_finish(true)') < startup.index('singbox_init_config()') < startup.index('start_sing_box_and_wait()')
assert "getenv('FORKOP_AWG_EXPERIMENTAL') == '1'" in startup
assert "getenv('FORKOP_AWG_EXPERIMENTAL') != '1'" in rebuild
assert rebuild.index('acquire_awg_network_lock()') < rebuild.index('nft-add-awg-guards')
assert text.rindex('release_awg_network_lock();') < text.rindex('exit(status);')
assert "const AWG_NETWORK_LOCK_DIR = '/tmp/artak-awg-apply.lock'" in text
print('AWG lifecycle ordering and opt-in checks passed')
