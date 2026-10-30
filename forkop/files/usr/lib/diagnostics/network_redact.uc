// Mask WireGuard/AmneziaWG key options in UCI network text, including quoted
// option names. Other diagnostics remain raw and may contain other secrets.
function mask(text) {
    if (type(text) != 'string') return '';
    let lines = split(text, '\n');
    for (let i = 0; i < length(lines); i++) {
        let m = match(lines[i], /^[ \t]*(option|list)[ \t]+['"]?(private_key|preshared_key|awg_header_protection_key)['"]?([ \t]|$)/);
        if (m != null) lines[i] = '\t' + m[1] + ' ' + m[2] + " '******'";
    }
    return join('\n', lines);
}
return { mask };
