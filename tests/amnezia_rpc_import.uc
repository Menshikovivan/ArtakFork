let service = require('subscription.amnezia_rpc_import');
function expect(x, m) { if (!x) die('FAIL: ' + m + '\n'); }
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let conf = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ' + key + '\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n';
let count = 0, applied = 0;
let deps = {
    cursor: function() { return { load: function() { return true; }, get: function(c, n) { return n == 'afawg_1' ? 'present' : null; } }; },
    check: function(t, p) { count++; return { ok: t != '15002' }; },
    apply: function(text, name, table, priority, timeout) { applied++; expect(text == conf && name == 'afawg_3' && table == '15003', 'allocation'); return { ok: true, secret: key }; },
};
let result = service.apply(conf, deps);
expect(result.ok && result.name == 'afawg_3' && applied == 1 && count == 2, 'skips occupied allocations');
expect(index(sprintf('%J', result), key) < 0, 'success strips key');
deps.apply = function() { die('SECRET_FROM_BACKEND'); };
result = service.apply(conf, deps);
expect(!result.ok && index(sprintf('%J', result), 'SECRET_FROM_BACKEND') < 0, 'exception redacted');
expect(!service.apply(conf + 'PostUp = SECRET\n', deps).ok, 'hook rejected before apply');
print('AmneziaWG import RPC dispatcher tests passed\n');
