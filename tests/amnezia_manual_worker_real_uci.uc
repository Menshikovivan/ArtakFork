let fs = require('fs');
let uci = require('uci');
let feature = require('subscription.amnezia_feature');
let worker = require('subscription.amnezia_manual_worker');
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
let root = getenv('ARTAK_TEST_UCI_DIR');
expect(type(root) == 'string' && match(root, /^\/tmp\/artak-uci-test\.[A-Za-z0-9]+$/), 'isolated root');
let config = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n';
let inspect = function() { return uci.cursor(root, root + '/delta2', ''); };
let calls = 0, opts = {
 config_dir: root, job_root: root, reload_lock: root + '/reload', subscription_lock: root + '/subscription',
 dirs: {candidate:root + '/candidate',last_good:root + '/good',active:root + '/active',generation:root + '/generation'},
 feature: function() { return feature.enabled(inspect()); }, pending: function() { return false; },
 activate: function(text, source, identity, dirs, state) {
   calls++; expect(text == config && state.current(), 'mock backend sees current saved binding');
   expect(fs.stat(root + '/reload') != null && fs.stat(root + '/subscription') != null, 'lifecycle locks held');
   return {ok:true,name:'afawg_1'};
 },
};
let c = inspect();
expect(!feature.enabled(c), 'missing setting defaults off');
expect(!worker.run(config, 'rule1', opts).ok && calls == 0, 'disabled worker performs no apply');
expect(c.set('forkop','settings','awg_experimental','1') != null && c.commit('forkop'), 'enable opt-in');
expect(worker.run(config, 'rule1', opts).ok && calls == 1, 'enabled worker applies with mock backend');
let verify = inspect();
expect(verify.load('forkop') != null && match(verify.get('forkop','rule1','manual_awg_id'), /^[0-9a-f]{32}$/), 'source ID committed');
expect(fs.stat(root + '/reload') == null && fs.stat(root + '/subscription') == null, 'locks released');
expect(verify.set('forkop','settings','awg_experimental','0') != null && verify.commit('forkop'), 'disable opt-in');
expect(!worker.run(config, 'rule1', opts).ok && calls == 1, 'disabled again without apply');
print('Manual worker with real UCI and mock backend passed\n');
