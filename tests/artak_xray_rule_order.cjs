// Exercise the Xray route generator with overlapping user sections.
const fs = require('fs');
const assert = require('assert');
const path = require('path');
const source = fs.readFileSync(path.join(__dirname, '../forkop/files/usr/lib/xray/generator.uc'), 'utf8');
const match = source.match(/function apply_primary_tproxy_routes\(config, xray_sections\) \{[\s\S]*?\n\}/);
assert(match, 'route generator is missing');
// ucode's for-in iterates values; JavaScript's equivalent is for-of.
const body = match[0].replace(/for \(let section in enabled_sections_any\(\)\)/g,
  'for (let section of enabled_sections_any())');
const calls = [];
const sections = [
  { name: 'first-proxy', action: 'connection' },
  { name: 'second-bypass', action: 'bypass' },
  { name: 'third-block', action: 'block' },
  { name: 'fourth-proxy', action: 'connection' }
];
const run = new Function('enabled_sections_any', 'apply_section_resolved_pins', 'section_policy_tproxy_target',
  'connections', 'option', 'section_tproxy_target', 'apply_section_tproxy_matchers',
  'apply_section_tproxy_sources', 'push', 'xray_constants', 'tproxy_inbound_tags', 'plane_fallback_tag',
  `${body}; return apply_primary_tproxy_routes;`)(
  () => sections, () => {}, section => ['bypass', 'block'].includes(section.action) ? section.action : null,
  { is_connections_action: value => value === 'connection' },
  (section, key, fallback) => section[key] ?? fallback, (_, section) => section.name,
  (_, section, target) => calls.push(['domain', section.name, target]),
  (_, section, target) => calls.push(['source', section.name, target]),
  (array, item) => array.push(item),
  { FAKEIP_INET4_RANGE: '198.18.0.0/15', FAKEIP_INET6_RANGE: 'fc00::/18', BLACKHOLE_TAG: 'block', FREEDOM_TAG: 'direct' },
  () => ['tproxy'], () => 'direct');
const config = { routing: { rules: [] } };
run(config, []);
for (const kind of ['domain', 'source']) {
  assert.deepStrictEqual(calls.filter(call => call[0] === kind).map(call => call[1]), sections.map(section => section.name),
    `${kind} rules must retain the user's section order`);
}
assert.strictEqual(config.routing.rules.at(-1).outboundTag, 'direct', 'unmatched traffic must keep its fallback');
console.log('Xray section priority and fallback: PASS');
