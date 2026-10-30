// Copy a validated snapshot to a private immutable directory named by SHA-256.
// The caller holds all lifecycle locks and retains both snapshots until swap
// completion or verified recovery. No subscription credentials are stored.
let fs = require('fs');
let common = require('core.common');
let snapshot = require('subscription.amnezia_snapshot');
function publish(source_dir, base) {
    if (type(base) != 'string' || base == '' || base == '/') return null;
    let base_stat = fs.lstat(base);
    if (base_stat != null && base_stat.type != 'directory') return null;
    if (!common.secure_private_dir(base)) return null;
    let source = snapshot.load(source_dir);
    if (source == null) return null;
    let target = base + '/' + source.revision;
    if (fs.lstat(target) != null) {
        let st = fs.lstat(target), existing = st.type == 'directory' ? snapshot.load(target) : null;
        return existing != null && existing.revision == source.revision ? source.revision : null;
    }
    if (!common.secure_private_dir(target)) return null;
    let content = fs.readfile(source_dir + '/snapshot.json');
    if (type(content) != 'string' || length(content) > 32768) return null;
    let stamp = clock(), tmp = sprintf('%s/.snapshot-%d-%d.tmp', target, stamp[0], stamp[1]);
    if (common.write_private_file(tmp, content) == null) { fs.unlink(tmp); return null; }
    if (!fs.rename(tmp, target + '/snapshot.json')) { fs.unlink(tmp); return null; }
    let result = snapshot.load(target), after = snapshot.load(source_dir);
    return result != null && after != null && result.revision == source.revision && after.revision == source.revision ? source.revision : null;
}
return { publish };
