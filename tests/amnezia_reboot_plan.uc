let reboot = require('subscription.amnezia_reboot_plan');
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
let a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let id = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
let old = {index:0,name:'afawg_1',table:'15001',priority:'16002'};
let next = {index:0,name:'afawg_2',table:'15002',priority:'16004'};
let journal = {source:'rule',phase:'verified',old_generation:a,new_generation:b,old_snapshot:a,new_snapshot:b};
let pointer = b, changed = false;
let opts = {
    read_journal:function() { return journal; }, current_id:function() { return pointer; },
    read_generation:function(dir, source, which) { return {source:'rule',identity:id,revision:which,entries:[which == a ? old : next]}; },
    load:function(dir) {
        let which = substr(dir, length(dir)-64), x = which == a ? old : next;
        let e = {source:'rule',identity:id,revision:which,index:x.index,name:x.name,table:x.table,priority:x.priority,mark:0x18000000 | int(x.table)};
        return {revision:changed ? a : which,entries:[e]};
    }
};
let result = reboot.plan('/journal','/gen','/snap','rule',opts);
expect(result != null && result.action == 'finish' && length(result.guards) == 2, 'verified reboot plan');
journal.phase = 'published';
expect(reboot.plan('/journal','/gen','/snap','rule',opts).action == 'restore', 'unverified new generation accepted');
journal.phase = 'union';
expect(reboot.plan('/journal','/gen','/snap','rule',opts).action == 'restore', 'crash pointer window accepted');
journal.phase = 'prepared';
expect(reboot.plan('/journal','/gen','/snap','rule',opts) == null, 'prepared phase accepted without union snapshots');
journal.phase = 'verified'; changed = true;
expect(reboot.plan('/journal','/gen','/snap','rule',opts) == null, 'wrong snapshot hash accepted');
print('AWG reboot guard recovery plan checks passed\n');
