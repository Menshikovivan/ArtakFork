const fs = require('fs');
const assert = require('assert');
const code = fs.readFileSync('forkop/files/usr/lib/xray/geodata.uc', 'utf8');
function fn(name) {
  const m = code.match(new RegExp('function ' + name + '\\([^]*?\\n\\}'));
  assert(m, name);
  return m[0].replace(/for \(let (\w+) in /g, 'for (let $1 of ');
}
const type = v => Array.isArray(v) ? 'array' : v === null ? 'null' : typeof v;
const mk = new Function('type', 'keys', 'length', 'object_or_empty', 'array_or_empty', 'empty_matchers', 'push_unique', 'MAX_INLINE_MATCHERS',
  [fn('ingest_rule_object'), fn('supported_source_rule'), fn('source_json_to_matchers'), 'return source_json_to_matchers;'].join('\n'));
const parse = mk(type, Object.keys, v => v.length, v => v || {}, v => Array.isArray(v) ? v : [], () => ({ok:false}),
  (out,v,seen) => { if (!seen[v]) { seen[v]=true; out.push(v); } }, 12000);
assert.deepStrictEqual(parse({version:3,rules:[{domain_suffix:['example.com']},{ip_cidr:['1.2.3.0/24']}]}),
  {domains:['domain:example.com'],ips:['1.2.3.0/24'],ok:true});
for (const bad of [{domain:['a'],port:[443]}, {domain:['a'],ip_cidr:['1.2.3.0/24']},
 {domain:['a'],invert:true}, {type:'logical',rules:[]}, {domain:'example.com'}])
  assert.strictEqual(parse({version:3,rules:[bad]}).ok, false, JSON.stringify(bad));
console.log('Xray JSON list semantics: PASS');

