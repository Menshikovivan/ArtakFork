let verify = require('subscription.amnezia_guard_union_verify');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let c = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
let d = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
let e1 = {index:0,name:'afawg_1',table:'15001',priority:'16002',mark:0x18000000 | 15001,source:'src',identity:a,revision:c};
let e2 = {index:0,name:'afawg_2',table:'15002',priority:'16004',mark:0x18000000 | 15002,source:'src',identity:a,revision:d};
let state = '', count = 0;
function get_journal() { count++; return {source:'src',old_generation:a,new_generation:b,old_snapshot:c,new_snapshot:d,phase: state == 'changed' && count > 1 ? 'verified' : 'union'}; }
function get_snapshot(dir) { return dir == 'old' ? {revision:c,entries:[e1]} : {revision:d,entries:[e2]}; }
function get_generation(dir, source, id) {
    let e = id == a ? e1 : e2;
    return {source:'src',identity:a,revision:e.revision,entries:[{index:0,name:e.name,table:e.table,priority:e.priority}]};
}
function make_rule(entry) { return {rule:{family:'inet',table:'ForkopTable',chain:'mangle_output',expr:[
 {match:{op:'==',left:{meta:{key:'mark'}},right:entry.mark}},
 {match:{op:'!=',left:{meta:{key:'oifname'}},right:entry.name}}, {counter:{}}, {drop:null}]}}; }
function runner() {
    let rules = [make_rule(e1), make_rule(e2)];
    if (state == 'missing') pop(rules);
    if (state == 'wrong') rules[1].rule.expr[1].match.right = 'wan';
    if (state == 'bypass') rules[0].rule.expr = [{accept:null}];
    return {ok:true,output:sprintf('%J',{nftables:[{chain:{family:'inet',table:'ForkopTable',name:'mangle_output',type:'route',hook:'output',prio:-150,policy:'accept'}}, ...rules]})};
}
let opts = {read_journal:get_journal,load:get_snapshot,read_generation:get_generation,current_id:function() { return a; },runner,table:'ForkopTable'};
expect(verify.verify('journal','generation','src','old','new',opts).ok, 'valid union accepted');
for (let mode in ['missing','wrong','bypass','changed']) {
 state = mode; count = 0;
 expect(!verify.verify('journal','generation','src','old','new',opts).ok, mode + ' must fail');
}
state = ''; count = 0;
opts.current_id = function() { return b; };
expect(!verify.verify('journal','generation','src','old','new',opts).ok, 'wrong generation pointer');
print('Journaled AWG union guard verification checks passed\n');
