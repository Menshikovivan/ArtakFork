const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('forkop/files/usr/lib/xray/runtime.uc', 'utf8');
const code = source.match(/function usable_timeout\(\) \{[\s\S]*?\n\}/)[0]
  .replace(/for \(let (\w+) in /g, 'for (let $1 of ');
const build = new Function('file_exists', 'command_success_from_args', code + '; return usable_timeout;');
assert.strictEqual(build(() => true, () => false)(), '', 'missing BusyBox applet must not be selected');
assert.strictEqual(build(() => true, args => args[0] === '/bin/timeout')(), '/bin/timeout');
assert.strictEqual(build(() => true, () => true)(), '/usr/bin/timeout');
console.log('Xray configuration check ignores broken timeout applet: PASS');
