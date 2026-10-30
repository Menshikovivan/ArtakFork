let allocate = require('subscription.amnezia_allocate');
function expect(ok, message) { if (!ok) die('FAIL: ' + message + '\n'); }
let cursor = {
 load: function() { return true; },
 get: function(config, name) { return name == 'afawg_3_peer' ? 'occupied' : null; },
 foreach: function(config, kind, cb) { if (kind == 'rule') cb({ priority: '16005' }); },
};
let runner = function() { return { ok: true, output: '[{"ifname":"afawg_1"}]' }; };
let check = function(table) { return table == '15004' ? { ok: false, error: 'Kernel routing table already used' } : { ok: true }; };
let audit = function() { return {ok:true}; };
let r = allocate.choose(cursor, { runner, check, audit });
expect(r.ok && r.name == 'afawg_5' && r.table == '15005' && r.priority == '16010', 'skips kernel, UCI and route collisions');
r = allocate.choose(cursor, { runner: function() { return {ok:false}; }, check, audit });
expect(!r.ok, 'fails closed when kernel cannot be inspected');
r = allocate.choose(cursor, { runner, check: function() { return {ok:false,error:'unexpected failure'}; }, audit });
expect(!r.ok, 'does not treat inspection failure as available');
let many = allocate.choose_many(cursor, 3, {runner, check, audit});
expect(many.ok && length(many.allocations) == 3 && many.allocations[0].name == 'afawg_5' &&
    many.allocations[1].name == 'afawg_6' && many.allocations[2].name == 'afawg_7', 'distinct batch allocations');
expect(!allocate.choose_many(cursor, 0, {runner, check, audit}).ok && !allocate.choose_many(cursor, 33, {runner, check, audit}).ok, 'invalid batch size');
expect(!allocate.choose_many(cursor, 32, {runner, check, audit}).ok, 'partial allocations are not returned');
expect(!allocate.choose_many(cursor, 2, {runner, check:function(table) {
    return table == '15005' ? {ok:true} : {ok:false,error:'inspection failed'};
}, audit}).ok, 'inspection error after partial success fails closed');
many = allocate.choose_many(cursor, 1, {runner, check, audit:function(marks) { return {ok:marks[0] != (0x18000000 | 15005),error:'IP rule mark conflict'}; }});
expect(many.ok && many.allocations[0].name == 'afawg_6', 'skip conflicting mark');
print('AmneziaWG allocation checks passed\n');
