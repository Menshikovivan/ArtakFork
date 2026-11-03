const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('forkop/files/usr/lib/xray/geodata.uc', 'utf8');
const fn = source.match(/function decompile_cache_path\(srs_path\) \{[\s\S]*?\n\}/);
assert(fn);
const cachePath = new Function('cache_dir', 'singbox_rulesets', fn[0] + '; return decompile_cache_path;')(
  () => '/cache', {hash12: () => '0123456789ab'});
assert.strictEqual(cachePath('/list.srs'), '/cache/0123456789ab.xray-v2.json');
assert.notStrictEqual(cachePath('/list.srs'), '/cache/0123456789ab.xray.json');
console.log('SRS caches from the old converter are invalidated: PASS');
