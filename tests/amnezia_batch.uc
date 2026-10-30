let fs = require('fs');
let store = require('subscription.amnezia_store');
let batch = require('subscription.amnezia_batch');
function expect(v, msg) { if (!v) die('FAIL: ' + msg + '\n'); }
let base = ARGV[0], candidates = base + '/candidates', active = base + '/active', good = base + '/good';
expect(fs.mkdir(candidates) && fs.mkdir(active) && fs.mkdir(good), 'fixture directories');
let id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
let text = '[Interface]\nPrivateKey = ' + key + '\nAddress = 10.0.0.2/32\n' +
    '[Peer]\nPublicKey = ' + key + '\nEndpoint = awg.example.invalid:443\nAllowedIPs = 0.0.0.0/0\n';
let link = 'vpn://' + b64enc(text);
expect(store.save(candidates, 'source', id, link + '\n' + link), 'stage candidate');
let next = 0, cleaned = 0;
let opts = {
    cursor: { load: function() { return true; } },
    choose: function() { next++; return { ok:true, name:'afawg_' + next, table:'' + (15000 + next), priority:'' + (16000 + 2 * next) }; },
    uci_check: function() { return { ok:true }; }, live_check: function() { return { ok:true }; },
    with_lock: function(o, cb) { return cb({ apply: function() { return { ok:true }; }, cleanup: function() { cleaned++; return { ok:true }; } }); },
    publish: function() { return true; }
};
expect(batch.activate(candidates, active, good, 'source', id, 1000, opts).ok, 'two-profile activation');
expect(!batch.activate(candidates, active, good, 'source', id, 1000, opts).ok, 'existing source overwritten');
fs.unlink(active + '/source.json'); next = 0; cleaned = 0;
opts.publish = function() { return false; };
let failed = batch.activate(candidates, active, good, 'source', id, 1000, opts);
expect(!failed.ok && !failed.cleanup_required && cleaned == 2 && fs.stat(active + '/source.json') == null, 'batch rollback');
next = 0; cleaned = 0;
opts.publish = function() { return true; };
opts.live_check = function(name) { return { ok: name != 'afawg_2' }; };
let offline = batch.activate(candidates, active, good, 'source', id, 1000, opts);
expect(!offline.ok && !offline.cleanup_required && cleaned == 2 && fs.stat(active + '/source.json') == null, 'second failed profile did not roll back first');
next = 0; cleaned = 0;
opts.live_check = function() { return { ok: true }; };
opts.with_lock = function(o, cb) { return cb({ apply: function(text, name) { return { ok: name != 'afawg_2' }; }, cleanup: function() { cleaned++; return { ok:true }; } }); };
let uncertain = batch.activate(candidates, active, good, 'source', id, 1000, opts);
expect(!uncertain.ok && uncertain.cleanup_required && cleaned == 1 && fs.stat(active + '/source.json') == null, 'uncertain failed apply was hidden');
print('AWG batch publication and rollback checks passed\n');
