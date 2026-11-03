const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync('forkop/files/usr/lib/xray/geodata.uc', 'utf8');
const fn = source.match(/function community_matchers\(name\) \{[\s\S]*?\n\}/)[0].replace(/for \(let (\w+) in /g, 'for (let $1 of ');
function converter(withDomain) {
 const deps = {
  trim: x => x.trim(), as_string: String, empty_matchers: () => ({ok:false, domains:[], ips:[]}),
  community_subnet_ips: () => ['192.0.2.0/24'], resolve_community_ext_tag: () => '',
  dat_matcher_usable: () => false, push_unique: (a,v,seen) => {if(!seen[v]) { seen[v]=true; a.push(v); }},
  community_lst_readable: () => '/fake', file_size: () => withDomain ? 1 : 0,
  lst_to_matchers: () => ({ok:true,domains:['domain:example.org'],ips:[]}), array_or_empty: x => Array.isArray(x)?x:[],
  adlist_dat_path: () => '', ADLIST_CODE: '', readable_cache_file: () => '', supercell_json_path: () => '',
  source_json_to_matchers: () => ({ok:false}), json_decode_text: () => ({}), fs: {readfile: () => ''},
  v2fly_geosite_tag: () => '', github_list_path: () => '', native_xray_list_name: () => true,
  singbox_rulesets: {community_url: () => ''}, cached_srs_path: () => '', decompile_srs: () => ({ok:false}),
  length: x => x.length, log_message: () => {}
 };
 return new Function(...Object.keys(deps), fn + '; return community_matchers;')(...Object.values(deps));
}
for (const name of ['youtube','telegram','meta','discord']) {
 assert.strictEqual(converter(false)(name).ok,false, name+' must reject subnet-only data');
 assert.strictEqual(converter(true)(name).ok,true, name+' accepts matching domain data');
}
console.log('Service lists reject missing domain data: PASS');
