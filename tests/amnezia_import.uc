let importer = require('subscription.amnezia_import');
function expect(v, message) { if (!v) die(message + '\n'); }
let fixture = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' +
    'Address = 10.0.0.2/32\n[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=\n' +
    'AllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:8443\n';
let sections = { wan: { '.type': 'interface', proto: 'dhcp' } }, commits = 0, fail = '';
let cursor = {
    load: function(pkg) { return true; },
    get: function(pkg, name, opt) { return opt ? sections[name]?.[opt] : sections[name]; },
    foreach: function(pkg, typ, cb) { for (let name in keys(sections)) if (sections[name]['.type'] == typ) cb(sections[name]); return true; },
    set: function(pkg, name, opt, val) {
        if (opt == fail) return null;
        if (val == null) sections[name] = { '.type': opt }; else sections[name][opt] = val;
        return true;
    },
    delete: function(pkg, name) { delete sections[name]; return true; },
    commit: function(pkg) { commits++; return fail != 'commit'; }
};
expect(!importer.stage(cursor, 'invalid', 'afawg_x', '16866', '1000').ok, 'Invalid config accepted');
expect(commits == 0 && sections.wan.proto == 'dhcp', 'Invalid import changed network');
fail = 'lookup';
expect(!importer.stage(cursor, fixture, 'afawg_x', '16866', '1000').ok, 'Route failure accepted');
expect(sections.afawg_x == null && sections.afawg_x_peer == null && sections.afawg_x_rt4 == null && sections.wan.proto == 'dhcp', 'Failed staging modified other sections');
fail = '';
let result = importer.stage(cursor, fixture, 'afawg_x', '16866', '1000');
expect(result.ok && result.ipv4 && !result.ipv6 && sections.afawg_x.proto == 'amneziawg', 'Import not staged');
expect(commits == 0 && sections.wan.proto == 'dhcp', 'Staging committed or changed WAN');
expect(importer.commit_staged(cursor).ok && commits == 1, 'Commit not called');
fail = 'commit';
expect(!importer.commit_staged(cursor).ok && commits == 2, 'Commit failure not reported');
print('AmneziaWG import orchestration tests passed\n');
