let fs = require('fs');
let queue = require('subscription.amnezia_swap_queue');
function expect(v, m) { if (!v) die('FAIL: ' + m + '\n'); }
let dir = ARGV[0], a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
let c = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
expect(queue.enqueue(dir, 'rule-1', a, b, c), 'enqueue');
let first = queue.read(dir, 'rule-1');
expect(first != null && first.revision == b, 'queue read');
expect(queue.enqueue(dir, 'rule-1', a, c, b), 'newer request');
expect(!queue.remove(dir, first), 'superseded request removed');
let second = queue.read(dir, 'rule-1');
expect(second.revision == c && queue.remove(dir, second) && queue.read(dir, 'rule-1') == null, 'matching request removal');
expect(!queue.enqueue(dir, 'rule-1', a, b, c, 'mixed', 'bad'), 'mixed request without legacy hash accepted');
expect(queue.enqueue(dir, 'rule-1', a, b, c, 'mixed', a), 'mixed request enqueue');
let mixed = queue.read(dir, 'rule-1');
expect(mixed.mode == 'mixed' && mixed.legacy_revision == a && queue.remove(dir, mixed), 'mixed binding lost');
expect(!queue.enqueue(dir, '../bad', a, b, c), 'unsafe source accepted');
print('AWG swap queue supersession checks passed\n');
