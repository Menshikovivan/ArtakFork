let runtime = require('subscription.amnezia_runtime_check');
function expect(v, m) { if (!v) die(m + '\n'); }
let mode = '', calls = 0;
function runner(args) {
    calls++;
    if (mode == 'failure') return { ok: false };
    if (mode == 'invalid') return { ok: true, output: 'invalid' };
    let rule = args[4] == 'rule';
    let data = rule ? [{ priority: 105, table: '100' }, { priority: 32766, table: '254' }] : [{ table: '254' }];
    if (mode == 'priority' && rule) push(data, { priority: 1001, table: '111' });
    if (mode == 'table' && !rule) push(data, { table: '16866' });
    if (mode == 'alias' && rule) push(data, { table: 'custom' });
    return { ok: true, output: sprintf('%J', data) };
}
expect(runtime.check('16866', '1000', runner).ok && calls == 4, 'Expected available allocation');
for (let failure in ['priority', 'table', 'alias', 'failure', 'invalid']) {
    mode = failure;
    expect(!runtime.check('16866', '1000', runner).ok, 'Conflict or invalid response accepted: ' + failure);
}
expect(!runtime.check('254', '1000', runner).ok, 'Reserved table accepted');
print('AWG kernel routing allocation tests passed\n');
