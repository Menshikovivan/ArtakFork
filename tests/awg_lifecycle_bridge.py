"""Source-wiring checks complement the executable nft factory tests."""
from pathlib import Path

text = (Path(__file__).resolve().parents[1] / 'forkop/files/usr/lib/service/lifecycle.uc').read_text()
rebuild = text[text.index('function nft_rebuild_runtime('):text.index('function nft_candidate_begin(')]
bridge = text[text.index('function awg_nft_union_factory('):text.index('function singbox_init_config(')]
assert "nft-add-awg-union-guards" in rebuild
assert rebuild.index("nft-add-awg-union-guards") < rebuild.rindex("nft-add-awg-guards")
for text_fragment in ("lease.valid()", "nft_candidate_begin()", "nft_rebuild_runtime(union_args)",
                      "runtime-list-cache-active", "apply-list-cache", "nft_populate_runtime_sets()",
                      "nft_candidate_validate()", "nft_candidate_finish(true, true)",
                      "nft_candidate_finish(false)", "checker.verify("):
    assert text_fragment in bridge, text_fragment
assert 'reload(' not in bridge
singbox = text[text.index('function awg_singbox_swap_bridge('):text.index('function awg_production_swap_factory(')]
assert "'/etc/forkop/awg-swap-config'" in singbox
assert singbox.index("'stop-managed-sing-box-runtime'") < singbox.index("'commit-config-stage'")
assert singbox.index("'validate-config-stage'") < singbox.index("'commit-config-stage'")
assert "'restore-config-stage'" in singbox and "check_generation(which)" in singbox
assert "'sha256sum'" in singbox and "live_hash() == expected" in singbox
assert "['cp', '-p', backup, copy]" in singbox
assert singbox.count('!safe()') >= 5
assert 'reload(' not in singbox
print('AWG lifecycle nft bridge wiring checks passed')
