let check = require('subscription.amnezia_lifecycle_swap');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let mark=0x18003a99, mode='';
let entry={source:'src',identity:id,revision:id,name:'afawg_1',mark};
let opts={
 cursor:function() { return {load:function() { return true; }}; },
 collect:function() { return [{source:'src',identity:mode == 'changed' ? 'other' : id}]; },
 current_id:function() { return id; },
 restore:function() { return {generation:id,identity:id,revision:id,entries:[{name:'afawg_1'}]}; },
 snapshot:function() { return {entries:[entry]}; },
 read_config:function() { return sprintf('%J',{outbounds:[{type:'direct',bind_interface:'afawg_1',routing_mark:mode == 'bad_mark' ? 1 : mark}]}); },
};
expect(check.verify_generation('src',id,id,{generation:'g',good:'d'},'s','c',opts), 'valid generation');
mode='changed'; expect(!check.verify_generation('src',id,id,{generation:'g',good:'d'},'s','c',opts), 'changed rule rejected');
mode='bad_mark'; expect(!check.verify_generation('src',id,id,{generation:'g',good:'d'},'s','c',opts), 'wrong outbound mark rejected');
print('AWG lifecycle generation/outbound checks passed\n');
