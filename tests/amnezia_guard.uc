let guard = require('subscription.amnezia_guard');
function expect(v,m) { if (!v) die(m + '\n'); }
let rev = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let entry = { index:0,name:'afawg_a',table:'16866',priority:'1000',mark:0x18000000 | 16866,
    source:'test',identity:rev,revision:rev };
let mode = '', reads = 0;
function load(dir) { reads++; return { revision:mode == 'changed' && reads > 1 ? 'other' : rev, entries:[entry] }; }
function run(args) {
    let name = mode == 'wrong' ? 'wan' : 'afawg_a';
    let data = { nftables:[
        { chain:{family:'inet',table:'ForkopTable',name:'mangle_output',type:'route',hook:'output',prio:-150,policy:'accept'} },
        { rule:{family:'inet',table:'ForkopTable',chain:'mangle_output',expr:[
            { match:{op:'==',left:{meta:{key:'mark'}},right:entry.mark} },
            { match:{op:'!=',left:{meta:{key:'oifname'}},right:name} },
            {counter:{packets:0,bytes:0}}, {drop:null} ] } }
    ] };
    if (mode == 'priority') data.nftables[0].chain.prio = 0;
    if (mode == 'missing') data.nftables[1].rule.expr[3] = {accept:null};
    return {ok:true,output:sprintf('%J', data)};
}
let opts = { load,runner:run,table:'ForkopTable',snapshot_dir:'/tmp/test' };
expect(guard.verify([entry],rev,opts).ok, 'Valid guard rejected');
for (let state in ['wrong','priority','missing','changed']) {
    mode = state; reads = 0;
    expect(!guard.verify([entry],rev,opts).ok, 'Invalid guard accepted: ' + state);
}
print('AWG guard snapshot verification tests passed\n');
