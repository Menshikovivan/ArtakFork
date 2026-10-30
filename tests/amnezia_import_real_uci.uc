// Runs only against a test-owned temporary UCI tree, never /etc/config.
let uci = require('uci');
let importer = require('subscription.amnezia_import');
function expect(v, m) { if (!v) die(m + '\n'); }
let dir = getenv('ARTAK_TEST_UCI_DIR');
if (type(dir) != 'string' || !match(dir, /^\/tmp\/artak-uci-test\.[A-Za-z0-9]+$/))
    die('Expected temporary test directory\n');
let fixture = '[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 10.0.0.2/32\n' +
    '[Peer]\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\nAllowedIPs = 0.0.0.0/0\nEndpoint = vpn.example:8443\n';
let c = uci.cursor(dir, dir + '/delta', '');
expect(c != null, 'Could not construct isolated UCI cursor');
let stage = importer.stage(c, fixture, 'afawg_test', '16866', '1000');
expect(stage.ok, 'Import staging failed: ' + stage.error);
expect(importer.commit_staged(c).ok, 'Commit failed');
let verify = uci.cursor(dir, dir + '/delta2', '');
expect(verify != null && verify.load('network') != null, 'Cannot reload test network');
expect(verify.get('network', 'wan', 'proto') == 'dhcp', 'WAN changed');
expect(verify.get('network', 'afawg_test', 'proto') == 'amneziawg', 'AWG interface not committed');
expect(verify.get('network', 'afawg_test_peer', 'route_allowed_ips') == '0', 'Unexpected global route setting');
expect(verify.get('network', 'afawg_test_rt4', 'table') == '16866', 'Private route absent');
expect(!importer.stage(verify, fixture, 'afawg_test', '16866', '1000').ok, 'Duplicate interface accepted');
print('Isolated real UCI import test passed\n');
