// Apply a durable prepare plan using the orchestrator-owned lease. The old
// generation stays selected. A failure leaves the prepare journal intact for
// explicit inspection/recovery; an in-flight operation is never assumed gone.
let journal = require('subscription.amnezia_prepare_journal');
let store = require('subscription.amnezia_store');
let generation = require('subscription.amnezia_generation');
let conf = require('subscription.amnezia_conf');
let verifier = require('subscription.amnezia_verify');
function run(lease, journal_dir, generation_dir, good_dir, source, metadata, timeout_ms, opts) {
    opts = type(opts) == 'object' ? opts : {};
    if (type(lease) != 'object' || type(lease.apply) != 'function' || type(opts.current) != 'function' ||
        type(metadata) != 'object') return {ok:false,error:'Invalid preparation request'};
    let plan = journal.read(journal_dir, source);
    if (plan == null || plan.completed != 0 || plan.inflight != null ||
        generation.current_id(generation_dir, source) != plan.old_generation) return {ok:false,error:'Invalid or interrupted preparation'};
    let path = good_dir + '/' + plan.revision;
    if (store.revision(path, source, plan.identity) != plan.revision) return {ok:false,error:'Candidate revision unavailable'};
    let configs = store.load_configs(path, source, plan.identity), parsed = [];
    if (type(configs) != 'array' || length(configs) != length(plan.entries)) return {ok:false,error:'Candidate profile count changed'};
    let uci_check = type(opts.uci_check) == 'function' ? opts.uci_check : verifier.verify_uci;
    let live_check = type(opts.live_check) == 'function' ? opts.live_check : verifier.verify;
    function current() {
        try { return opts.current() === true && generation.current_id(generation_dir, source) == plan.old_generation &&
            store.revision(path, source, plan.identity) == plan.revision; } catch (e) { return false; }
    }
    function verified(e) {
        let p = parsed[e.index], cursor = opts.cursor || require('uci').cursor();
        if (p == null || !cursor || cursor.load('network') == null) return false;
        let ipv4 = false, ipv6 = false;
        for (let ip in p.peers[0].allowed_ips) {
            if (ip == '0.0.0.0/0') ipv4 = true;
            if (ip == '::/0') ipv6 = true;
        }
        let a = uci_check(cursor, p, e.name, e.table, e.priority, ipv4, ipv6);
        if (type(a) != 'object' || a.ok !== true) return false;
        let b = live_check(e.name, e.table, e.priority, p.interface.addresses, p.peers[0].public_key, ipv4, ipv6, timeout_ms);
        return type(b) == 'object' && b.ok === true;
    }
    try {
        for (let i = 0; i < length(configs); i++) {
            let p = conf.parse_conf(configs[i]);
            if (!p.ok || length(p.peers) != 1) return {ok:false,error:'Candidate profile invalid',recovery_required:true};
            push(parsed, p);
        }
        for (let entry in plan.entries) {
            if (!current() || !journal.begin(journal_dir, source, entry.index))
                return {ok:false,error:'Preparation checkpoint failed',recovery_required:true};
            let result = lease.apply(configs[entry.index], entry.name, entry.table, entry.priority, timeout_ms);
            if (type(result) != 'object' || result.ok !== true || !verified(entry) || !current() ||
                !journal.finish(journal_dir, source, entry.index))
                return {ok:false,error:'Preparation failed; inspect in-flight interface',recovery_required:true};
        }
        let record = {version:1, kind:'subscription', mode:metadata.mode || 'only', source, identity:plan.identity, revision:plan.revision,
            url:metadata.url, user_agent:metadata.user_agent, hwid:metadata.hwid, entries:plan.entries};
        if (record.mode == 'mixed') record.legacy_revision = metadata.legacy_revision;
        let id = generation.stage(generation_dir, good_dir, record, function(e) { return current() && verified(e); });
        if (id == null || !current()) return {ok:false,error:'Cannot stage new generation',recovery_required:true};
        return {ok:true,generation:id,revision:plan.revision};
    } catch (e) { return {ok:false,error:'Preparation failed; inspect journal',recovery_required:true}; }
}
return { run };
