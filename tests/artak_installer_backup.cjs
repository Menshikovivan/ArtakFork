const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('install.sh','utf8');
const fn=source.match(/backup_artak_configuration\(\) \{[\s\S]*?\n\}/)[0];
for (const p of ['etc/config/forkop','etc/config/dhcp','etc/config/firewall','etc/init.d/sing-box','usr/bin/sing-box','usr/lib/rust-x']) assert(fn.includes(p),p);
assert(fn.includes('umask 077'));
assert(fn.includes('tar -tzf'));
console.log('Backup includes router configuration and Xrust runtime: PASS');
