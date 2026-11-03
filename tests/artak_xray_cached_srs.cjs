const fs = require('fs');
const path = require('path');
const assert = require('assert');
const code = fs.readFileSync(path.join(__dirname, '../forkop/files/usr/lib/xray/geodata.uc'), 'utf8');
const match = code.match(/function decompile_srs\(srs_path\) \{[\s\S]*?\n\}/);
assert(match, 'SRS converter is missing');
let sourceMtime = 10;
let cacheMtime = 11;
let warning = '';
const run = new Function('as_string', 'file_size', 'empty_matchers', 'MAX_DECOMPILE_BYTES', 'log_message',
  'ensure_dir', 'cache_dir', 'decompile_cache_path', 'file_mtime', 'json_decode_text', 'fs', 'type',
  'array_or_empty', 'file_exists', 'SING_BOX_BIN', 'ARTAK_SRS_BIN', `${match[0]}; return decompile_srs;`)(
  String, () => 10, () => ({ ok: false, domains: [], ips: [] }), 524288,
  (text, level) => { warning = `${level}:${text}`; }, () => true, () => '/cache', () => '/cache/list.json',
  file => file === '/cache/list.json' ? cacheMtime : sourceMtime, JSON.parse,
  { readfile: () => JSON.stringify({ ok: true, domains: ['domain:example.com'], ips: [] }) },
  value => typeof value, value => Array.isArray(value) ? value : [], () => false, '/usr/bin/sing-box', '/usr/libexec/artak-srs');
assert.deepStrictEqual(run('/lists/example.srs').domains, ['domain:example.com']);
assert.strictEqual(warning, '', 'a valid cache must not require sing-box');
cacheMtime = 9;
assert.strictEqual(run('/lists/example.srs').ok, false, 'stale cache cannot be treated as current');
assert(warning.startsWith('warn:'), 'an unavailable converter must be reported');
console.log('Xray cached SRS without sing-box: PASS');
