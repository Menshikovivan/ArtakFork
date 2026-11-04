// Check the selector logic on synthetic data; router ucode tests remain required.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
let source = fs.readFileSync('tools/artak_isolated_expected.uc', 'utf8')
  .replace('for (let key in keys(r))', 'for (let key of keys(r))')
  .replace(/for \(let (\w+) in ([^\n)]+)\)/g, 'for (let $1 of $2)');
function select(rules, extra = {}) {
  const cfg = { routing: { rules, ...extra }, outbounds: [
    {tag: 'proxy-a'}, {tag: 'proxy-b'}, {tag: 'direct'}
  ] };
  let result;
  const env = {
    require: () => ({readfile: () => JSON.stringify(cfg), writefile: (_, data) => { result = data; return true; }}),
    ARGV: ['private-input', 'gemini.google.com', 'private-output'],
    json: JSON.parse, lc: s => s.toLowerCase(), type: x => Array.isArray(x) ? 'array' : (x === null ? 'null' : typeof x),
    index: (x, y) => x.indexOf(y), length: x => x.length, substr: (s, start) => s.slice(start),
    keys: Object.keys, push: (a, x) => a.push(x), sprintf: (_, x) => JSON.stringify(x) + '\n',
    exit: () => { throw Error('ambiguous'); }
  };
  vm.runInNewContext(source, env);
  return JSON.parse(result);
}
const route = (domains, target) => ({type: 'field', inboundTag: ['tproxy-in'], domain: domains, ...target});
assert.deepStrictEqual(select([route(['full:gemini.google.com'], {outboundTag: 'proxy-a'})]), ['proxy-a']);
assert.deepStrictEqual(select([route(['domain:google.com'], {balancerTag: 'b'})],
  {balancers: [{tag: 'b', selector: ['proxy-']}]}), ['proxy-a', 'proxy-b']);
assert.throws(() => select([route(['geosite:google'], {outboundTag: 'direct'}),
  route(['full:gemini.google.com'], {outboundTag: 'proxy-a'})]));
assert.throws(() => select([{type: 'field', inboundTag: ['tproxy-in'], source: ['192.168.1.4'],
  domain: ['full:gemini.google.com'], outboundTag: 'proxy-a'}]));
assert.throws(() => select([{type: 'field', inboundTag: ['tproxy-in'], outboundTag: 'direct'},
  route(['full:gemini.google.com'], {outboundTag: 'proxy-a'})]));
console.log('Isolated route selection rejects ambiguous rules: PASS');
