// Real temporary UCI and on-disk generation; netifd/handshake are mocked.
let fs = require('fs');
let uci = require('uci');
let worker = require('subscription.amnezia_manual_worker');
let manual = require('subscription.amnezia_manual_source');
let activate = require('subscription.amnezia_manual_activate');
let importer = require('subscription.amnezia_import');
let feature = require('subscription.amnezia_feature');
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
let root = getenv('ARTAK_TEST_UCI_DIR');
expect(type(root) == 'string' && match(root, /^\/tmp\/artak-uci-test\.[A-Za-z0-9]+$/), 'isolated root');
let text = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=\nEndpoint = example.com:443\nAllowedIPs = 0.0.0.0/0\n';
let cursor = function() { return uci.cursor(root, root + '/delta2', ''); };
let settings = cursor(); expect(settings.load('forkop') != null, 'load settings');
expect(settings.set('forkop','settings','awg_experimental','1') != null && settings.commit('forkop'), 'enable');
let dirs = {candidate:root + '/candidate',last_good:root + '/good',active:root + '/active',generation:root + '/generation'};
let config = {
 config_dir:root, job_root:root, reload_lock:root + '/reload', subscription_lock:root + '/subscription', dirs,
 feature:function() { return feature.enabled(cursor()); }, pending:function() { return false; },
 activate:function(conf, source, identity, paths, state) {
   return activate.activate(conf, source, identity, paths, {
     current:state.current, cursor:{}, verify_cursor:cursor,
     choose:function() { return {ok:true,name:'afawg_1',table:'15001',priority:'16002'}; },
     with_lock:function(o, callback) { return callback({
       apply:function(cfg, name, table, priority) {
         let c = cursor(), result = importer.stage(c, cfg, name, table, priority);
         return result.ok && importer.commit_staged(c).ok ? {ok:true} : {ok:false};
       }, cleanup:function() { return {ok:false}; },
     }); },
     live_check:function() { return {ok:true}; },
   });
 },
};
expect(worker.run(text, 'rule1', config).ok, 'manual worker and generation publication');
let after = cursor(); expect(after.load('forkop') != null && after.load('network') != null, 'fresh cursor after restart');
let identity = manual.from_id(after.get('forkop','rule1','manual_awg_id'));
expect(identity != null, 'persisted rule identity');
let recovered = manual.restore(dirs.last_good, dirs.generation, identity.source, identity.identity, after, 1000,
  {live_check:function() { return {ok:true}; }});
expect(type(recovered) == 'array' && recovered[0].name == 'afawg_1', 'generation restored with real UCI after restart');
expect(after.set('network','afawg_1','mtu','900') != null && after.commit('network'), 'change managed section');
let modified = cursor(); expect(modified.load('network') != null, 'load modified network');
expect(manual.restore(dirs.last_good, dirs.generation, identity.source, identity.identity, modified, 1000,
  {live_check:function() { return {ok:true}; }}) == null, 'changed managed section fails verification');
print('Manual generation restart and changed-section checks passed with real UCI and mock netifd\n');
