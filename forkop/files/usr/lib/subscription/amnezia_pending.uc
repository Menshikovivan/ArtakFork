// libuci may leave an empty delta file after a successful commit. Only an
// absent path or a readable, regular, genuinely empty file means no delta.
let fs = require('fs');
function pending(path) {
    if (type(path) != 'string' || !match(path, /^\/[^\r\n]+$/)) return true;
    try {
        let st = fs.lstat(path);
        if (st != null) {
            if (st.type != 'file' || st.size != 0 || fs.readfile(path) != '') return true;
            let after = fs.lstat(path);
            return after == null || after.type != 'file' || after.size != 0 || after.inode != st.inode ||
                after.dev?.major != st.dev?.major || after.dev?.minor != st.dev?.minor;
        }
        let parts = match(path, /^(.*)\/([^\/]+)$/);
        if (parts == null) return true;
        let parent = fs.lstat(parts[1]);
        if (parent == null) {
            let p = match(parts[1], /^(.*)\/([^\/]+)$/);
            if (p == null) return true;
            let names = fs.lsdir(p[1]);
            return type(names) != 'array' || index(names,p[2]) >= 0;
        }
        if (parent.type != 'directory') return true;
        let names = fs.lsdir(parts[1]);
        return type(names) != 'array' || index(names,parts[2]) >= 0;
    } catch (e) { return true; }
}
return { pending };
