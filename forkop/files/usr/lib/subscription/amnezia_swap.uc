// Internal transaction state machine for replacing an active AWG source.
// Hooks are trusted in-process implementations invoked while subscription,
// network and firewall lifecycle locks are held. This state machine does not
// itself persist a crash journal and must not be used by production until the
// lifecycle provides durable recovery and a firewall guard for both sets.
// Hook errors and connection data are never returned or logged.
function execute(ops) {
    let required = ['prepare', 'install_union', 'verify_union', 'publish',
        'reload', 'verify_new', 'restore_old', 'verify_old', 'discard_new', 'retire_old'];
    if (type(ops) != 'object') return { ok:false, error:'Invalid swap transaction' };
    for (let name in required)
        if (type(ops[name]) != 'function') return { ok:false, error:'Incomplete swap transaction' };
    let prepared = false, union_installed = false, published = false, previous_restored = true;
    function call(name) { try { return ops[name]() === true; } catch (e) { return false; } }
    function fail(message) {
        if (published) {
            previous_restored = call('restore_old') && call('verify_old');
        } else previous_restored = call('verify_old');
        // Preserve the union guard and new resources if the old route could
        // not be verified; deleting them here could cut off or expose traffic.
        let cleaned = false;
        if (prepared && previous_restored) cleaned = call('discard_new');
        return { ok:false, error:message, recovery_required:!previous_restored || (prepared && !cleaned), union_installed };
    }
    if (!call('prepare')) return { ok:false, error:'Could not prepare new AWG profiles', recovery_required:true };
    prepared = true;
    if (!call('install_union')) return fail('Could not install union guard');
    union_installed = true;
    if (!call('verify_union')) return fail('Union guard verification failed');
    published = true;
    if (!call('publish')) return fail('Could not publish new AWG profiles');
    if (!call('reload') || !call('verify_new')) return fail('Could not verify new AWG routing');
    // Failure to retire old profiles must not tear down verified new routing.
    if (!call('retire_old')) return { ok:true, cleanup_required:true };
    return { ok:true, cleanup_required:false };
}
return { execute };
