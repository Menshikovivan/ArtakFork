let fs = require('fs');
let sources = require('subscription.amnezia_snapshot_sources');
function expect(v, msg) { if (!v) die('FAIL: ' + msg + '\n'); }
let base = ARGV[0], gen = base + '/generation', active = base + '/active', cand = base + '/candidate';
expect(fs.mkdir(gen) && fs.mkdir(active) && fs.mkdir(cand), 'fixture dirs');
let token = '0123456789abcdef0123456789abcdef', source = 'manual_' + token;
expect(fs.writefile(gen + '/' + source + '.current', 'present') != null, 'pointer fixture');
let sections = [{'.name':'rule1', enabled:'1', manual_awg_id:token}];
let cursor = {load:function() { return true; }, foreach:function(pkg, type, cb) { if (type == 'section') for (let s in sections) cb(s); }};
let dirs = {generation:gen,active,candidate:cand};
let result = sources.collect(cursor, dirs);
expect(type(result) == 'array' && length(result) == 1 && result[0].source == source && result[0].identity == token + token, 'manual source missing');
push(sections, {'.name':'rule2',enabled:'1',manual_awg_id:token});
expect(sources.collect(cursor, dirs) == null, 'duplicate manual ownership accepted');
pop(sections); fs.unlink(gen + '/' + source + '.current');
expect(fs.writefile(active + '/' + source + '.json', '{}') != null && sources.collect(cursor, dirs) == null, 'unmigrated legacy accepted');
print('AWG snapshot source ownership checks passed\n');
