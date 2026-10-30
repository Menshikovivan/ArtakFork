let redact = require('diagnostics.network_redact');
function expect(v, m) { if (!v) die(m + '\n'); }
let input = "config interface 'wan'\n\toption proto 'dhcp'\n" +
    "config interface 'wg'\n\toption private_key 'SECRET_PRIVATE'\n" +
    "config wireguard_wg\n\toption 'preshared_key' \"SECRET_PSK\"\n" +
    "config interface 'awg'\n\toption \"awg_header_protection_key\" 'SECRET_HEADER'\n" +
    "\toption public_key 'PUBLIC_VALUE'\n\toption private_key_extra 'NOT_A_SECRET'\n";
let output = redact.mask(input);
expect(index(output, 'SECRET_PRIVATE') < 0 && index(output, 'SECRET_PSK') < 0 && index(output, 'SECRET_HEADER') < 0, 'A private key was not masked');
expect(index(output, "option public_key 'PUBLIC_VALUE'") >= 0 && index(output, "option private_key_extra 'NOT_A_SECRET'") >= 0, 'Unrelated network fields changed');
expect(index(output, "config interface 'wan'\n\toption proto 'dhcp'") >= 0, 'WAN configuration changed');
expect(index(output, "option private_key '******'") >= 0 && index(output, "option preshared_key '******'") >= 0, 'Missing masking markers');
print('Network key redaction tests passed\n');
