let union = require('subscription.amnezia_guard_union');
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
let a = { name:'afawg_1', table:'15001', priority:'16002', source:'rule', index:0 };
let b = { name:'afawg_2', table:'15002', priority:'16004', source:'rule', index:0 };
let both = union.plan([a], [b], []);
expect(both.ok && length(both.guards) == 2, 'old and new generations do not coexist');
expect(union.plan([a], [a], []).ok && length(union.plan([a], [a], []).guards) == 1, 'shared entry was not deduplicated');
expect(!union.plan([a], [{ name:'afawg_1', table:'15003', priority:'16006' }], []).ok, 'same interface with different allocation accepted');
expect(!union.plan([a], [{ name:'afawg_3', table:'15001', priority:'16006' }], []).ok, 'duplicate table accepted');
expect(!union.plan([a], [{ name:'afawg_3', table:'15003', priority:'16003' }], []).ok, 'overlapping priority accepted');
print('AWG old/new guard union checks passed\n');
