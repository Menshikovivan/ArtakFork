"""Source-wiring checks complement the executable nft factory tests."""
from pathlib import Path

text = (Path(__file__).resolve().parents[1] / 'forkop/files/usr/lib/service/lifecycle.uc').read_text()
rebuild = text[text.index('function nft_rebuild_runtime('):text.index('function nft_candidate_begin(')]
bridge = text[text.index('function awg_nft_union_factory('):text.index('function singbox_init_config(')]
assert "nft-add-awg-union-guards" in rebuild
assert rebuild.index("nft-add-awg-union-guards") < rebuild.index("nft-add-awg-guards")
for text_fragment in ("lease.valid()", "nft_candidate_begin()", "nft_rebuild_runtime(union_args)",
                      "runtime-list-cache-active", "apply-list-cache", "nft_populate_runtime_sets()",
                      "nft_candidate_validate()", "nft_candidate_finish(true, true)",
                      "nft_candidate_finish(false)", "checker.verify("):
    assert text_fragment in bridge, text_fragment
assert 'reload(' not in bridge
print('AWG lifecycle nft bridge wiring checks passed')
