let parser = require("subscription.amnezia_conf");
function expect(ok, msg) { if (!ok) die("FAIL: " + msg + "\n"); }
let key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
let common = "[Interface]\nPrivateKey = " + key + "\nAddress = 10.0.0.2/32, fd00::2/128\nJc = 4\nJmin = 40\nJmax = 70\nS1 = 72\nS2 = 56\nS3 = 32\nS4 = 16\nH1 = 101-110\nH2 = 201-210\nH3 = 301-310\nH4 = 401-410\n";
let peer = "\n[Peer]\nPublicKey = " + key + "\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = example.com:10443\nPersistentKeepalive = 25\n";
let v2 = parser.parse_conf(common + peer);
expect(v2.ok && v2.interface.proto == "amneziawg", "2.0 parsed");
expect(v2.interface.awg_h1 == "101-110" && length(v2.interface.addresses) == 2, "header range and address list preserved");
expect(v2.peers[0].endpoint_host == "example.com" && v2.peers[0].route_allowed_ips == "0", "endpoint and route policy");
let v3 = parser.parse_conf(common + "HeaderProtectionKey = " + key + "\nContentPaddingAddition = 10-20\nDisableCookies = on\nRandomTrailers = off\nRekeyAfterTime = 300-500\n" + peer);
expect(v3.ok && v3.interface.awg_disable_cookies == "1" && v3.interface.awg_random_trailers == "0", "3.1 flags");
expect(v3.interface.awg_content_padding_addition == "10-20" && v3.interface.awg_rekey_after_time == "300-500", "3.1 ranges preserved");
expect(!parser.parse_conf(common + "PostUp = malicious\n" + peer).ok, "hooks rejected");
expect(!parser.parse_conf(common + "Jc = 9\n" + peer).ok, "duplicate rejected");
expect(!parser.parse_conf(replace(common, "201-210", "105-115") + peer).ok, "overlapping headers rejected");
expect(!parser.parse_conf(common + replace(peer, "example.com:10443", "example.com:99999")).ok, "port range");
let bad = parser.parse_conf(common + "Unrecognized = SECRET_DO_NOT_LOG\n" + peer);
expect(!bad.ok && index(sprintf("%J", bad), "SECRET_DO_NOT_LOG") < 0 && index(sprintf("%J", bad), key) < 0, "errors hide secrets");
print("AmneziaWG 2.0 and 3.1 conf parser checks passed\n");
