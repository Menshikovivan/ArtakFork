let fs = require('fs');
let recovery = require('subscription.amnezia_swap_recovery');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let dir = getenv('ARTAK_AWG_RECOVERY_TEST_DIR');
expect(type(dir) == 'string' && dir != '', 'isolated test directory');
let calls = 0, held = true;
let opts = {
 holds_locks:function() { return held; },
 ops_for_source:function(s) { return {source:s}; },
 recover:function(ops, journal, generation, source) { calls++; return {ok:fs.unlink(journal + '/' + source + '.swap.json')}; },
};
expect(recovery.recover_all(dir, dir, opts).ok && calls == 0, 'empty directory');
expect(recovery.recover_all(dir + '/absent', dir, {holds_locks:function() { return true; }}).ok, 'missing directory is empty');
expect(recovery.recover_all(dir, dir, {holds_locks:function() { return true; }}).ok, 'empty directory needs no provider');
fs.writefile(dir + '/first.prepare.json', '{}');
expect(!recovery.recover_all(dir, dir, opts).ok && fs.stat(dir + '/first.prepare.json') != null, 'prepared resources need inspection');
fs.unlink(dir + '/first.prepare.json');
fs.writefile(dir + '/first.swap.json', '{}');
expect(!recovery.recover_all(dir, dir, {holds_locks:function() { return true; }}).ok, 'journal without provider fails closed');
held = false;
expect(!recovery.recover_all(dir, dir, opts).ok && fs.stat(dir + '/first.swap.json') != null, 'lock required');
held = true;
let result = recovery.recover_all(dir, dir, opts);
expect(result.ok && result.recovered == 1 && calls == 1, 'recover and verify journal cleared');
fs.writefile(dir + '/first.swap.json', '{}');
opts.recover = function() { return {ok:true}; };
expect(!recovery.recover_all(dir, dir, opts).ok, 'success without clearing journal rejected');
fs.unlink(dir + '/first.swap.json');
fs.writefile(dir + '/invalid.name.swap.json', '{}');
expect(!recovery.recover_all(dir, dir, opts).ok, 'invalid journal filename fails closed');
print('AWG swap recovery coordinator checks passed\n');
