let routes = require('subscription.amnezia_routes');
function expect(value, message) { if (!value) die(message + '\n'); }
let sections = { afawg_a: { '.type': 'interface', proto: 'amneziawg' } }, fail = '';
let cursor = {
    get: function(pkg, name, option) { return option ? sections[name]?.[option] : sections[name]; },
    foreach: function(pkg, kind, cb) {
        for (let name in keys(sections)) if (sections[name]['.type'] == kind) cb(sections[name]);
        return true;
    },
    set: function(pkg, name, option, value) {
        if (option == fail) return null;
        if (value == null) sections[name] = { '.type': option };
        else sections[name][option] = value;
        return true;
    },
    delete: function(pkg, name) { delete sections[name]; return true; }
};
expect(!routes.prepare('wan', '16866', '1000', true, false).ok, 'Unsafe interface');
expect(!routes.prepare('afawg_a', '254', '1000', true, false).ok, 'Unsafe table');
expect(!routes.prepare('afawg_a', '16866', '105', true, false).ok, 'Unsafe priority');
expect(!routes.prepare('afawg_a', '16866', '1000', false, false).ok, 'No families');
let plan = routes.prepare('afawg_a', '16866', '1000', true, true);
expect(plan.ok, sprintf('Route plan rejected: %s; boolean type: %s', plan.error, type(true)));
expect(length(plan.entries) == 6, sprintf('Unexpected route count: %d', length(plan.entries)));
expect(plan.entries[0].options.target == '0.0.0.0/0', sprintf('Unexpected first route target: %s', plan.entries[0].options.target));
sections.other = { '.type': 'rule', priority: '1001', lookup: '252' };
expect(!routes.stage_new(cursor, 'afawg_a', '16866', '1000', true, false).ok, 'Priority collision');
delete sections.other;
sections.other = { '.type': 'route6', table: '16866' };
expect(!routes.stage_new(cursor, 'afawg_a', '16866', '1000', true, false).ok, 'Table collision');
delete sections.other;
fail = 'lookup';
expect(!routes.stage_new(cursor, 'afawg_a', '16866', '1000', true, false).ok, 'Failure accepted');
expect(sections.afawg_a != null && sections.afawg_a_rt4 == null && sections.afawg_a_rl4 == null, 'Rollback failed');
fail = '';
expect(routes.stage_new(cursor, 'afawg_a', '16866', '1000', true, true).ok, 'Stage failed');
expect(sections.afawg_a_rt4.interface == 'afawg_a' && sections.afawg_a_rl4.lookup == '16866' &&
    sections.afawg_a_deny6.action == 'prohibit', 'Wrong staged values');
expect(!routes.stage_new(cursor, 'afawg_a', '16866', '1000', true, false).ok, 'Overwrote existing sections');
print('AmneziaWG route staging tests passed\n');
