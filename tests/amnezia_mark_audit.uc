let audit = require('subscription.amnezia_mark_audit');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let mark = 0x18003a99, v4 = [], v6 = [], nft = {nftables:[]};
function runner(args) {
    if (args[2] == 'ip') return {ok:true, output:sprintf('%J', args[5] == '-4' ? v4 : v6)};
    return {ok:true,output:sprintf('%J', nft)};
}
function check() { return audit.audit([mark],{runner}); }
expect(check().ok, 'empty policy');
v4 = [{fwmark:'0x00000002',fwmask:'0x00000002'}];
expect(check().ok, 'nonoverlapping masked rule');
v6 = [{fwmark:'0x18000000',fwmask:'0xff000000'}];
expect(!check().ok, 'wide masked collision');
v6 = [{fwmark:'0x18000000',fwmask:'invalid'}];
expect(!check().ok, 'invalid mask');
v6 = [{fwmark:'0x18000000',not:true}];
expect(!check().ok, 'inverted rule rejected');
v6 = [];
nft = {nftables:[{rule:{expr:[{mangle:{key:{meta:{key:'mark'}},value:1}}]}}]};
expect(check().ok, 'known disjoint constant nft mark');
nft.nftables[0].rule.expr[0].mangle.value = mark;
expect(!check().ok, 'nft constant collision');
nft.nftables[0].rule.expr[0].mangle.value = {'|':[{meta:{key:'mark'}},1]};
expect(!check().ok, 'dynamic mark writer rejected');
nft = {nftables:[{rule:{expr:[{queue:{num:0}}]}}]};
expect(!check().ok, 'opaque queue rejected');
nft = {nftables:[{rule:{expr:[{match:{left:{meta:{key:'mark'}},op:'==',right:mark}},{drop:null}]}}]};
expect(check().ok, 'mark read-only match is allowed');
expect(!audit.audit([mark],{runner:function(){return {ok:false};}}).ok, 'failed inspection rejects');
print('AWG masked mark and nft writer audit checks passed\n');
