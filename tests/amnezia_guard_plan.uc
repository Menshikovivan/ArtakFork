let guard = require('subscription.amnezia_guard_plan');
function expect(v,m) { if (!v) die(m + '\n'); }
let entries = [{name:'afawg_a',table:'16866',priority:'1000'}, {name:'afawg_b',table:'16867',priority:'1002'}];
let p = guard.plan(entries, [], 0x08000000);
expect(p.ok && length(p.guards) == 2 && p.guards[0].mark != p.guards[1].mark &&
    (p.guards[0].mark & 0x08000000) == 0x08000000, 'Invalid marks');
expect(!guard.plan(entries, [p.guards[0].mark], 0x08000000).ok, 'Collision accepted');
expect(!guard.plan(entries, [], 0x04000000).ok, 'Unexpected outbound mark accepted');
expect(!guard.plan([entries[0], entries[0]], [], 0x08000000).ok, 'Duplicate accepted');
print('Experimental AWG guard allocation tests passed\n');
