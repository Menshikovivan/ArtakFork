let job = require('subscription.amnezia_job');
job.run(function(config) { sleep(3000); return { ok: config != null, name: 'afawg_1' }; });
