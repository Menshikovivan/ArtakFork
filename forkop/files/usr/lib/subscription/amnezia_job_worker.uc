let job = require('subscription.amnezia_job');
let importer = require('subscription.amnezia_rpc_import');
let uci = require('uci');
let checker = require('subscription.amnezia_runtime_check');
let backend = require('subscription.amnezia_apply');
job.run(function(config) {
    return importer.apply(config, { cursor: function() { return uci.cursor(); }, check: checker.check, apply: backend.apply });
});
