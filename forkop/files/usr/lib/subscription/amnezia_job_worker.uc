let job = require('subscription.amnezia_job');
let worker = require('subscription.amnezia_manual_worker');
job.run(function(config, section) {
    return worker.run(config, section);
});
