// Exercise the ucode transformation on synthetic data; not a runtime probe.
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync('tools/artak_isolated_xray.uc', 'utf8')
  .replace(/for \(let (\w+) in ([^\n)]+)\)/g, 'for (let $1 of $2)');
function transform(extra = {}, negative = false) {
  const cfg = {routing: {rules: [{type: 'field', inboundTag: ['tproxy-in', 'tproxy6-in'], outboundTag: 'proxy'}]},
    outbounds: [{tag: 'proxy', protocol: 'freedom'}], inbounds: [{tag: 'original'}], ...extra};
  let output;
  vm.runInNewContext(source, {
    require: () => ({readfile: () => JSON.stringify(cfg), writefile: (_, data) => { output = data; return true; }}),
    ARGV: ['input', 'output', '38781', 'private-log', negative ? 'negative' : 'positive'],
    json: JSON.parse, int: Number, type: x => Array.isArray(x) ? 'array' : (x === null ? 'null' : typeof x),
    index: (x, y) => x.indexOf(y), push: (a, x) => a.push(x), sprintf: (_, x) => JSON.stringify(x),
    exit: () => { throw Error('rejected'); }
  });
  return JSON.parse(output);
}
let normal = transform();
assert.strictEqual(normal.inbounds.length, 1);
assert.strictEqual(normal.inbounds[0].listen, '127.0.0.1');
assert.deepStrictEqual(normal.routing.rules[0].inboundTag, ['artak-isolated-test']);
assert.strictEqual(normal.routing.rules[0].outboundTag, 'proxy');
let negative = transform({}, true);
assert.strictEqual(negative.routing.rules[0].outboundTag, 'artak-isolated-block');
assert.strictEqual(negative.outbounds.at(-1).protocol, 'blackhole');
assert.throws(() => transform({reverse: {}}));
console.log('Isolated Xray configuration keeps routing and installs negative control: PASS');
