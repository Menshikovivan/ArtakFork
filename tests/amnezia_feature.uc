let feature = require('subscription.amnezia_feature');
function expect(value, message) { if (!value) die('FAIL: ' + message + '\n'); }
let cursor = { load: function() { return true; }, get: function() { return null; } };
expect(!feature.enabled(cursor), 'missing defaults off');
cursor.get = function() { return '0'; };
expect(!feature.enabled(cursor), 'zero disables');
cursor.get = function() { return '1'; };
expect(feature.enabled(cursor), 'explicit one enables');
cursor.load = function() { return null; };
expect(!feature.enabled(cursor), 'invalid UCI fails closed');
print('AWG experimental opt-in tests passed\n');
