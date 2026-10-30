let allocate = require('subscription.amnezia_allocate');
function expect(ok, message) { if (!ok) die('FAIL: ' + message + '\n'); }
let cursor = {
 load: function() { return true; },
 get: function(config, name) { return name == 'afawg_3_peer' ? 'occupied' : null; },
 foreach: function(config, kind, cb) { if (kind == 'rule') cb({ priority: '16005' }); },
};
let runner = function() { return { ok: true, output: '[{"ifname":"afawg_1"}]' }; };
let check = function(table) { return table == '15004' ? { ok: false, error: 'Kernel routing table already used' } : { ok: true }; };
let r = allocate.choose(cursor, { runner, check });
expect(r.ok && r.name == 'afawg_5' && r.table == '15005' && r.priority == '16010', 'skips kernel, UCI and route collisions');
r = allocate.choose(cursor, { runner: function() { return {ok:false}; }, check });
expect(!r.ok, 'fails closed when kernel cannot be inspected');
r = allocate.choose(cursor, { runner, check: function() { return {ok:false,error:'unexpected failure'}; } });
expect(!r.ok, 'does not treat inspection failure as available');
print('AmneziaWG allocation checks passed\n');
