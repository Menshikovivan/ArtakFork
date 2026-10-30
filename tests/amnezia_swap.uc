let swap = require('subscription.amnezia_swap');
function expect(value, msg) { if (!value) die('FAIL: ' + msg + '\n'); }
function scenario(fail_at, throws) {
    let calls = [], ops = {};
    for (let name in ['prepare','install_union','verify_union','publish','reload','verify_new','restore_old','verify_old','discard_new','retire_old']) {
        let n = name;
        ops[n] = function() { push(calls, n); if (n == throws) die('private fixture'); return n != fail_at; };
    }
    return { result: swap.execute(ops), calls };
}
let success = scenario('', '');
expect(success.result.ok && !success.result.cleanup_required, 'successful swap');
expect(join(',', success.calls) == 'prepare,install_union,verify_union,publish,reload,verify_new,retire_old', 'swap ordering');
let reload_fail = scenario('reload', '');
expect(!reload_fail.result.ok && !reload_fail.result.recovery_required &&
    join(',', reload_fail.calls) == 'prepare,install_union,verify_union,publish,reload,restore_old,verify_old,discard_new', 'reload rollback');
let guard_fail = scenario('verify_union', '');
expect(!guard_fail.result.ok && join(',', guard_fail.calls) == 'prepare,install_union,verify_union,verify_old,discard_new', 'guard refusal');
let recovery = scenario('verify_old', 'reload');
expect(!recovery.result.ok && recovery.result.recovery_required && index(join(',', recovery.calls), 'discard_new') < 0, 'failed recovery deleted new resources');
let retire = scenario('retire_old', '');
expect(retire.result.ok && retire.result.cleanup_required, 'deferred cleanup');
expect(index(sprintf('%J', recovery.result), 'private fixture') < 0, 'exception leaked');
print('AWG swap transaction ordering and rollback passed\n');
