let fs = require('fs'), pending = require('subscription.amnezia_pending');
function expect(value, message) { if (!value) die('FAIL: ' + message + '\n'); }
let dir = getenv('AWG_PENDING_TEST_DIR');
if (type(dir) != 'string' || dir == '') die('missing test dir\n');
let path = dir + '/delta';
expect(!pending.pending(path), 'missing delta');
expect(fs.writefile(path,'') != null && !pending.pending(path), 'empty committed delta');
expect(fs.writefile(path,'set forkop.x=1\n') != null && pending.pending(path), 'pending nonempty delta');
fs.unlink(path);
expect(fs.symlink('/dev/null',path) && pending.pending(path), 'symlink refused');
fs.unlink(path); fs.mkdir(path,0700);
expect(pending.pending(path), 'directory refused');
fs.rmdir(path);
expect(pending.pending(dir + '/missing-parent/child') == false, 'absent parent directory');
print('AWG UCI pending delta checks passed\n');
