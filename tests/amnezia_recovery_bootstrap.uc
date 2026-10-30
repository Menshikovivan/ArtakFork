let bootstrap = require('subscription.amnezia_recovery_bootstrap');
function expect(v,m) { if (!v) die('FAIL: ' + m + '\n'); }
let calls=[], mode='', held=true, good=false;
let hooks = {
 holds:function(){return held;}, unchanged:function(){return mode != 'changed';},
 guard_ok:function(){push(calls,'verify');return good;},
 stop:function(){push(calls,'stop');return mode != 'stop';},
 audit:function(){push(calls,'audit');return mode != 'audit';},
 record_rollback:function(){push(calls,'journal');return mode != 'journal';},
 restore_pointer:function(){push(calls,'pointer');return mode != 'pointer';},
 install_guard:function(){push(calls,'install');good=true;return true;},
};
let p={ok:true,action:'restore',guards:[{}]};
expect(bootstrap.prepare(p,hooks) && join(',',calls) == 'verify,stop,audit,journal,pointer,install,verify', 'ordered rollback and guard');
good=false; mode='stop'; calls=[];
expect(!bootstrap.prepare(p,hooks) && index(calls,'journal') < 0, 'stop failure avoids journal or firewall mutation');
mode='audit'; calls=[];
expect(!bootstrap.prepare(p,hooks) && index(calls,'install') < 0, 'mark audit failure prevents firewall install');
mode='journal'; calls=[];
expect(!bootstrap.prepare(p,hooks) && index(calls,'pointer') < 0, 'journal durable before pointer');
mode=''; good=true; calls=[];
expect(bootstrap.prepare(p,hooks) && join(',',calls) == 'verify', 'already verified guard preserved');
good=false; p.action='finish'; calls=[];
expect(bootstrap.prepare(p,hooks) && index(calls,'journal') < 0 && index(calls,'pointer') < 0, 'new generation finish retains pointer');
print('AWG recovery bootstrap ordering checks passed\n');
