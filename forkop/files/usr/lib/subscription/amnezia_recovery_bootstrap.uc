// In-process startup recovery gate. The caller must hold all three lifecycle
// locks and supply trusted hooks; this module never accepts external paths.
function prepare(plan, hooks) {
    if (type(plan) != 'object' || plan.ok !== true || type(hooks) != 'object') return false;
    for (let name in ['holds','unchanged','guard_ok','stop','audit','record_rollback','restore_pointer','install_guard'])
        if (type(hooks[name]) != 'function') return false;
    function stable() { return hooks.holds() === true && hooks.unchanged() === true; }
    try {
        if (!stable()) return false;
        if (hooks.guard_ok() === true) return stable();
        // Never run a managed core while rebuilding a missing guard.
        if (hooks.stop() !== true || !stable() || hooks.audit(plan.guards) !== true || !stable()) return false;
        if (plan.action == 'restore') {
            if (hooks.record_rollback() !== true || hooks.holds() !== true || hooks.restore_pointer() !== true) return false;
        } else if (plan.action != 'finish') return false;
        return hooks.holds() === true && hooks.install_guard() === true && hooks.guard_ok() === true && hooks.holds() === true;
    } catch (e) { return false; }
}
return { prepare };
