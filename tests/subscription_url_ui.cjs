const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const view = 'luci-static/resources/view/forkop/';
// These functions have no nested function declarations. Taking the declaration
// up to the next declaration tests the actual shipped code, including bundles.
function declaration(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `missing ${name}`);
  const end = source.indexOf('function ', start + 9);
  assert.notEqual(end, -1, `missing boundary after ${name}`);
  return source.slice(start, end);
}
const mainSource = fs.readFileSync(path.join(root, 'luci-app-forkop/htdocs', view, 'main.js'), 'utf8');
const helpers = ['asciiHostname', 'validAsciiDomain', 'validateDomain', 'isIPv4', 'isIPv6',
                 'unbracketHost', 'isValidHost', 'isValidPort', 'validateUrl'];
const context = vm.createContext({ URL, _: value => value });
vm.runInContext(helpers.map(name => declaration(mainSource, name)).join('\n') +
                '\nthis.main = { validateUrl };', context);
const files = process.argv[2] ? [path.resolve(process.argv[2])] : [
  path.join(root, 'luci-app-forkop/htdocs', view, 'section.js'),
  path.join(root, 'luci-app-forkop/generated', view, 'section.js'),
];
for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  vm.runInContext(['parseSubscriptionUrlEntry', 'validateSubscriptionUrlEntry']
    .map(name => declaration(source, name)).join('\n'), context);
  const validate = value => context.validateSubscriptionUrlEntry('test-section', value);
  for (const value of [
    'https://subscription.example.test/subscription/test?format=xray',
    'https://other-provider.example.test:8443/feed',
    'https://aes2215.vs2112.51343.ru/feed',
    'https://sub.flintnet.pro/feed', 'https://sub.hat.onl/feed',
    '  https://subscription.example.test/feed  ', '', null,
  ]) assert.equal(validate(value), true, `${file}: rejected ${value}`);
  for (const value of [
    'http://subscription.example.test/feed', 'file:///tmp/feed', 'https://',
    'https://bad host/feed', 'https://subscription.example.test/a b',
    'https://subscription.example.test/a\tb', 'not-a-url',
    'https://subscription.example.test/feed | Custom/1',
  ]) assert.notEqual(validate(value), true, `${file}: accepted invalid ${value}`);
  assert.equal(context.parseSubscriptionUrlEntry('  https://subscription.example.test/feed  ').url,
               'https://subscription.example.test/feed');
  console.log(`${path.relative(root, file)}: subscription URL validation passed`);
}
