// Internal job adapter. Call only after updater locks are released; the
// orchestrator reacquires reload -> subscription -> AWG locks. URL and keys
// are read from private in-memory records, never CLI arguments or logs.
let queue = require('subscription.amnezia_swap_queue');
let generation = require('subscription.amnezia_generation');
let store = require('subscription.amnezia_store');
let orchestrator = require('subscription.amnezia_orchestrator');
function run(source, dirs, deps) {
    if (type(source) != 'string' || !match(source, /^[A-Za-z0-9_-]{1,100}$/) ||
        type(dirs) != 'object' || type(deps) != 'object' || type(deps.factory) != 'function' ||
        type(deps.matches_rule) != 'function') return {ok:false,error:'Invalid swap job'};
    let q = deps.queue || queue, gen = deps.generation || generation, st = deps.store || store;
    let execute = deps.execute || orchestrator.prepare_and_execute;
    try {
        let request = q.read(dirs.queue, source);
        if (request == null || gen.current_id(dirs.generation, source) != request.old_generation ||
            st.revision(dirs.candidate, source, request.identity) != request.revision)
            return {ok:false,error:'Stale swap request'};
        let old = gen.read_generation(dirs.generation, source, request.old_generation);
        if (type(old) != 'object' || old.identity != request.identity || old.kind != 'subscription')
            return {ok:false,error:'Current generation unavailable'};
        let metadata = {url:old.url, user_agent:old.user_agent, hwid:old.hwid, mode:request.mode};
        if (request.mode == 'mixed') metadata.legacy_revision = request.legacy_revision;
        let serialized = sprintf('%J', request);
        function current() {
            try {
                let now = q.read(dirs.queue, source);
                return now != null && sprintf('%J', now) == serialized &&
                    st.revision(dirs.candidate, source, request.identity) == request.revision &&
                    deps.matches_rule(source, request.identity, metadata) === true;
            } catch (e) { return false; }
        }
        if (!current()) return {ok:false,error:'Swap source changed'};
        let result = execute(deps.factory, dirs, source, request.old_generation, request.identity, metadata, 5000,
            {current, lib:deps.lib || '/usr/lib/forkop'});
        if (type(result) != 'object' || result.ok !== true) return {ok:false,error:'Swap did not complete'};
        if (result.cleanup_required || !q.remove(dirs.queue, request)) return {ok:true,cleanup_required:true};
        return {ok:true,cleanup_required:false};
    } catch (e) { return {ok:false,error:'Swap job failed'}; }
}
return { run };
