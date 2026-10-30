let factory = require('subscription.amnezia_nft_swap_factory');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let a='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let b='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let c='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
let d='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
let phase = 'prepared', locked = true, leased = true, mode = '', calls = [], absent = true;
let ctx = {source:'src',journal_dir:'j',generation_dir:'g',old_generation:a,new_generation:b,old_snapshot:c,new_snapshot:d,old_snapshot_dir:'old',new_snapshot_dir:'new'};
let hooks = {
 holds_locks:function() { return locked; }, lease_active:function() { return leased; },
 read_journal:function() { return {source:'src',phase,old_generation:a,new_generation:b,old_snapshot:c,new_snapshot:d}; },
 current_id:function() { return a; }, load:function(dir) { return {revision:dir == 'old' ? c : d}; },
 begin:function() { push(calls,'begin'); return true; },
 rebuild_base:function() { push(calls,'base'); return true; },
 rebuild_recovery:function() { push(calls,'create-only'); return true; },
 install_guards:function() { push(calls,'guard'); return true; },
 apply_lists:function() { push(calls,'lists'); return mode != 'lists'; },
 validate:function() { push(calls,'validate'); if (mode == 'lost') leased = false; return true; },
 commit:function() { push(calls,'commit'); return true; },
 abort:function() { push(calls,'abort'); return true; },
 verify_union:function() { push(calls,'verify'); return mode != 'verify'; },
 table_absent:function() { return absent; },
};
let f = factory.create(ctx,hooks);
expect(f != null && f.install_union(), 'valid candidate');
expect(join(',',calls) == 'begin,base,guard,lists,validate,commit', 'full sets before commit');
phase = 'union'; expect(f.verify_union(), 'union verified');
phase = 'prepared'; mode='lists'; calls=[];
expect(!f.install_union() && index(calls,'commit') < 0 && index(calls,'abort') >= 0, 'failed list apply aborts before commit');
mode='lost'; leased=true; calls=[];
expect(!f.install_union() && index(calls,'commit') < 0 && index(calls,'abort') >= 0, 'lost lease aborts');
leased=true; phase='union'; mode='verify';
expect(!f.verify_union(), 'failed live union check rejected');
mode=''; absent=false; calls=[];
expect(!f.recover_union('union') && length(calls) == 0, 'recovery never replaces an existing table');
absent=true; mode='lists'; calls=[];
expect(!f.recover_union('union') && index(calls,'commit') < 0 && index(calls,'abort') >= 0, 'recovery refuses incomplete list sets');
mode=''; calls=[];
expect(f.recover_union('union') && index(calls,'create-only') >= 0 && index(calls,'verify') > index(calls,'commit'), 'recovery uses create-only and commits then verifies guard');
phase='prepared'; locked=false; calls=[];
expect(!f.install_union() && length(calls) == 0, 'no mutation without locks');
print('AWG nft swap factory fail-closed checks passed\n');
