const fs = require('fs');
const assert = require('assert');
const path = require('path');
const source = fs.readFileSync(path.join(__dirname, '../forkop/files/usr/lib/xray/outbound.uc'), 'utf8');
function extract(name) {
  const match = source.match(new RegExp(`function ${name}\\([^]*?\\n\\}`));
  assert(match, `${name} missing`);
  return match[0];
}
let code = ['as_string', 'object_or_empty', 'trim', 'first_string', 'transport_names', 'apply_transport_names', 'apply_transport']
  .map(extract).join('\n');
// Translate only ucode's value-iteration syntax for this isolated function test.
code = code.replace(/for \(let item in value\)/g, 'for (let item of value)')
  .replace(/for \(let mapping in \[/g, 'for (let mapping of [');
const type = value => Array.isArray(value) ? 'array' : value === null ? 'null' : typeof value === 'number' ? 'int' : typeof value;
const run = new Function('type', 'replace', 'lc', `${code}; return apply_transport;`)(
  type, (value, pattern, replacement) => value.replace(pattern, replacement), value => value.toLowerCase());
const input = { type: 'xhttp', path: '/demo', mode: 'stream-one', host: 'example.com',
  x_padding_bytes: '123-456', x_padding_key: 'sample', x_padding_obfs_mode: true,
  no_grpc_header: false, xmux: { max_connections: 0, max_concurrency: '1-2' } };
const result = run({}, input);
assert.strictEqual(result.network, 'xhttp');
assert.deepStrictEqual(result.xhttpSettings, { path: '/demo', mode: 'stream-one', host: 'example.com',
  xPaddingBytes: '123-456', xPaddingKey: 'sample', xPaddingObfsMode: true, noGRPCHeader: false,
  xmux: { maxConnections: 0, maxConcurrency: '1-2' } });
console.log('XHTTP outbound conversion: PASS');
