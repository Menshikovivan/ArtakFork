#!/usr/bin/env ucode

// Connection keys can contain credentials. They are used only for matching in
// memory and are never returned by this module or written to the report.
let identity = require("subscription.filter_identity");

function array(value) { return type(value) == "array" ? value : []; }
function object(value) { return type(value) == "object" ? value : {}; }

function safe_name(value) {
    if (type(value) != "string" || value == "" || length(value) > 80 ||
        match(value, /[\r\n\t@?=&\\\/]/) ||
        match(lc(value), /(token|secret|password|passwd|uuid|private.?key|api.?key)/) ||
        match(value, /[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}/) ||
        match(value, /[A-Za-z0-9_-]{32,}/) ||
        match(value, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) ||
        match(value, /([A-Za-z0-9-]+\.)+[A-Za-z]{2,}/))
        return "[name hidden]";
    return value;
}

function label(outbound) {
    return safe_name(object(outbound).remark || object(outbound).tag || "");
}

function leaves(value) {
    let result = [];
    for (let outbound in array(object(value).outbounds))
        if (identity.connection_key(outbound) != "")
            push(result, outbound);
    return result;
}

// First match identical connections (including renames), then unique exact
// names (configuration changes). Duplicated names are reported as additions
// and removals instead of guessing which connection changed.
function compare(previous, next) {
    let old = leaves(previous), fresh = leaves(next);
    let used_old = {}, used_new = {}, added = [], removed = [], changed = [];
    for (let i = 0; i < length(fresh); i++) {
        let key = identity.connection_key(fresh[i]);
        for (let j = 0; j < length(old); j++) {
            if (!used_old["" + j] && identity.connection_key(old[j]) == key) {
                used_new["" + i] = true; used_old["" + j] = true;
                if (label(old[j]) != label(fresh[i]))
                    push(changed, { before: label(old[j]), after: label(fresh[i]), kind: "renamed" });
                break;
            }
        }
    }
    for (let i = 0; i < length(fresh); i++) {
        if (used_new["" + i]) continue;
        let name = label(fresh[i]);
        if (name == "[name hidden]") continue;
        let old_index = -1, old_count = 0, new_count = 0;
        for (let j = 0; j < length(old); j++)
            if (!used_old["" + j] && label(old[j]) == name) { old_index = j; old_count++; }
        for (let j = 0; j < length(fresh); j++)
            if (!used_new["" + j] && label(fresh[j]) == name) new_count++;
        if (old_count == 1 && new_count == 1) {
            used_old["" + old_index] = true; used_new["" + i] = true;
            push(changed, { before: name, after: name, kind: "connection_changed" });
        }
    }
    for (let i = 0; i < length(fresh); i++) if (!used_new["" + i]) push(added, label(fresh[i]));
    for (let i = 0; i < length(old); i++) if (!used_old["" + i]) push(removed, label(old[i]));
    return { baseline: type(previous) != "object", added, removed, changed };
}

return { compare, safe_name };
