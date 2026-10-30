let job = require('subscription.amnezia_swap_job');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let request = {version:1,source:'rule_1',identity:hash,revision:hash,old_generation:hash,mode:'only'};
let removed = 0, calls = 0, changed = false;
let deps = {
 factory:function() {}, matches_rule:function() { return !changed; },
 queue:{read:function() { return request; },remove:function(dir,expected) { removed++; return expected == request; }},
 generation:{current_id:function() { return hash; },read_generation:function() { return {identity:hash,kind:'subscription',url:'SECRET_URL',user_agent:'x',hwid:'y'}; }},
 store:{revision:function() { return hash; }},
 execute:function(factory,dirs,source,old,identity,metadata,timeout,opts) {
   calls++; expect(metadata.url == 'SECRET_URL' && opts.current(), 'private metadata and guard'); return {ok:true};
 },
};
let dirs = {queue:'q',generation:'g',candidate:'c',good:'good',journal:'j'};
let result = job.run('rule_1',dirs,deps);
expect(result.ok && !result.cleanup_required && removed == 1 && calls == 1, 'successful request removed');
expect(index(sprintf('%J',result),'SECRET_URL') < 0, 'no URL in result');
changed = true; removed=0; calls=0;
result = job.run('rule_1',dirs,deps);
expect(!result.ok && calls == 0 && removed == 0, 'changed source rejected without mutation');
changed = false;
deps.execute = function() { return {ok:true,cleanup_required:true}; };
result = job.run('rule_1',dirs,deps);
expect(result.ok && result.cleanup_required && removed == 0, 'incomplete cleanup retains request');
expect(!job.run('../bad',dirs,deps).ok, 'invalid source rejected');
print('AWG queued swap job validation tests passed\n');
