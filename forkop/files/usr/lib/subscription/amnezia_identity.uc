// Build the same identity used by the subscription downloader without ever
// passing the source URL, user agent or HWID as command-line arguments.
let fs = require('fs');
let common = require('core.common');
function calculate(dir, source, url, ua, hwid) {
    if (type(dir) != 'string' || dir == '' || dir == '/' ||
        type(source) != 'string' || !match(source, /^[A-Za-z0-9_-]{1,100}$/) ||
        type(url) != 'string' || type(ua) != 'string' || type(hwid) != 'string' ||
        !common.secure_private_dir(dir)) return null;
    let stamp = clock();
    let path = sprintf('%s/.identity-%s-%d-%d.tmp', dir, source, stamp[0], stamp[1]);
    if (common.write_private_file(path, sprintf('%J\n', [url, ua, hwid])) == null) {
        fs.unlink(path); return null;
    }
    let quoted = "'" + replace(path, /'/g, "'\\''") + "'";
    let pipe = fs.popen('sha256sum ' + quoted + ' 2>/dev/null', 'r');
    if (!pipe) { fs.unlink(path); return null; }
    let output = pipe.read('all');
    let status = pipe.close();
    fs.unlink(path);
    if (status != 0 || type(output) != 'string') return null;
    let digest = split(trim(output), /[ \t\r\n]+/)[0];
    return match(digest, /^[0-9a-f]{64}$/) ? digest : null;
}
return { calculate };
