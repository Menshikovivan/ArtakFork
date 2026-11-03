const fs = require('fs');
const assert = require('assert');
const script = fs.readFileSync('install.sh', 'utf8');
const main = script.slice(script.indexOf('main() {'));
assert(main.indexOf('download_artak_srs') < main.indexOf('cleanup_legacy_installation'), 'verify SRS before package changes');
assert(main.indexOf('backup_artak_configuration') < main.indexOf('cleanup_legacy_installation'), 'back up before package changes');
assert(main.indexOf('install_artak_srs') < main.indexOf('post_install'), 'install converter before starting service');
const download = script.match(/download_artak_srs\(\) \{[\s\S]*?\n\}/)[0];
assert(download.includes('sha256sum') && download.includes('checksum mismatch'));
assert(download.includes('aarch64|arm64'));
console.log('Installer converter ordering and checksum guards: PASS');

