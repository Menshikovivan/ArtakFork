let uri = require('subscription.wireguard_uri');
function expect(ok, text) { if (!ok) die(text + '\n'); }
let key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D';
let base = 'wireguard://' + key + '@vpn.example.invalid:51820?publickey=' + key + '&address=10.0.0.2%2F32&mtu=1420';
let good = uri.parse(base + '#Example');
expect(good.ok && index(good.config, 'AllowedIPs = 0.0.0.0/0,::/0') >= 0, '3x-ui WG link');
expect(uri.parse('wg://' + key + '@[2001:db8::1]:51820?publickey=' + key + '&address=10.0.0.2%2F32').ok, 'IPv6 endpoint');
expect(uri.parse(base + '&keepalive=25&dns=1.1.1.1&presharedkey=' + key).ok, 'optional fields');
let plus = '++++++++++++++++++++++++++++++++++++++++++8=';
let escaped = replace(replace(plus, /\+/g, '%2B'), /=/g, '%3D');
let pluslink = 'wireguard://' + plus + '@vpn.example.invalid:51820?publickey=' + escaped + '&address=10.0.0.2%2F32';
expect(uri.parse(pluslink).ok, 'literal userinfo plus and encoded query plus');
expect(!uri.parse(replace(pluslink, escaped, plus)).ok, 'raw query plus must not become a key');
expect(!uri.parse(replace(base, 'address=10.0.0.2%2F32', 'address=10.0.0.2%0A%5BPeer%5D')).ok, 'decoded newline');
expect(!uri.parse(replace(base, 'address=10.0.0.2%2F32', 'address=10.0.0.2%GG')).ok, 'invalid escape');
for (let bad in [
    base + '&publicKey=' + key, base + '&other=ignored', base + '&mtu=%0AAddress%3D1.2.3.4',
    base + '&presharedkey=%GG', base + '&address=10.0.0.3%2F32',
    replace(base, 'vpn.example.invalid:51820', 'vpn.example.invalid:0'),
    replace(base, 'wireguard://', 'http://'), replace(base, key, 'not-a-key')
]) expect(!uri.parse(bad).ok, 'Invalid or ambiguous link accepted');
print('WireGuard share-link parser checks passed\n');
