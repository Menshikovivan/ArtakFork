const fs = require('fs');
const path = require('path');
const assert = require('assert');
const source = fs.readFileSync(path.join(__dirname, '../forkop/files/usr/lib/xray/generator.uc'), 'utf8');
const match = source.match(/function validate_xray_rule_lists\(\) \{[\s\S]*?\n\}/);
assert(match, 'rule list validation is missing');
const code = match[0].replace('for (let section in enabled_sections_any())',
  'for (let section of enabled_sections_any())');
let sections = [];
const validate = new Function('enabled_sections_any', 'option', 'connections',
  'section_has_unmapped_domain_list', 'generate_fail', `${code}; return validate_xray_rule_lists;`)(
  () => sections, (s, key, fallback) => s[key] ?? fallback,
  { is_connections_action: action => action === 'connection' },
  s => s.unmapped, message => { throw new Error(message); });
sections = [{ '.name': 'normal', action: 'connection', unmapped: false }];
assert.doesNotThrow(validate);
for (const action of ['connection', 'bypass', 'block', 'dns']) {
  sections = [{ '.name': 'broken', action, unmapped: true }];
  assert.throws(validate, /cannot load one or more rule lists/, `${action} must not omit a list`);
}
console.log('Xray rejects missing selected rule lists: PASS');
