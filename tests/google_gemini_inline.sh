#!/bin/sh
set -eu
LIB=${FORKOP_LIB:-$(CDPATH= cd -- "$(dirname -- "$0")/../forkop/files/usr/lib" && pwd)}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
cat >"$WORK/fixture.json" <<'JSON'
{"settings":{".name":"settings",".type":"settings","dns_server":"1.1.1.1"},"section":[{".name":"moscow",".type":"section","enabled":"1","action":"connection","community_lists":["google_gemini"],"source_ip_cidr":["192.0.2.10/32"],"ports":["443"],"outbound_jsons":["{\"type\":\"socks\",\"tag\":\"chosen-moscow-node\",\"server\":\"192.0.2.1\",\"server_port\":1080}"]},{".name":"unrelated",".type":"section","enabled":"1","action":"bypass","domain_suffix":["unrelated.example.test"]}]}
JSON
for mode in community reference; do
    if [ "$mode" = reference ]; then
        ucode -e 'let fs=require("fs"); let f=json(fs.readfile(ARGV[0])); f.section[0].rule_set=f.section[0].community_lists; delete f.section[0].community_lists; fs.writefile(ARGV[0],sprintf("%J",f));' "$WORK/fixture.json"
    fi
    ucode -L "$LIB" "$LIB/singbox/generator.uc" generate-config-fixture \
        "$WORK/fixture.json" "$WORK/$mode.json" 127.0.0.1 0 1 '' 1.14.3-extended-2.7.3
    # A real script path is required: CLI/module guards use sourcepath(1),
    # which is empty when a module is required directly from ucode -e.
    cat >"$WORK/check.uc" <<'UCODE'
let fs=require("fs"), catalog=require("singbox.rulesets");
let config=json(fs.readfile(ARGV[0]));
function expect(value,message){ if(!value) die(message+" (mode="+ARGV[1]+")\nGenerated fixture configuration: "+sprintf("%J",config)+"\n"); }
function contains(value,needle){return type(value)=="array" ? index(value,needle)>=0 : value==needle;}
expect(index(split(require("core.constants").COMMUNITY_SERVICES," "),"google_gemini")>=0,"Gemini not registered for configuration validation");
let tag=ARGV[1]=="community" ? "moscow-google_gemini-community-ruleset" : "builtin-google_gemini-ruleset";
let sets=filter(config.route.rule_set,function(s){return s.tag==tag;});
expect(length(sets)==1,"inline Gemini ruleset missing or duplicated; expected tag "+tag);
let set=sets[0];
expect(set.type=="inline" && set.url==null && set.path==null,"Gemini unexpectedly requires remote or local files");
let wanted=["gemini.google.com","aistudio.google.com","generativelanguage.google.com","alkalimining-pa.googleapis.com","proactivebackend-pa.googleapis.com"];
expect(length(set.rules)==1 && sprintf("%J",set.rules[0].domain_suffix)==sprintf("%J",wanted),"Gemini suffixes differ");
expect(catalog.community_kind("google_gemini")=="domains" && catalog.community_url("google_gemini")=="","Gemini catalog is not inline domains");
expect(catalog.community_url("google_ai")!="","existing Google AI catalog was replaced");
let routes=filter(config.route.rules,function(r){return contains(r.rule_set,tag);});
expect(length(routes)==1 && routes[0].outbound=="moscow-out","Gemini did not select Moscow section outbound");
expect(contains(routes[0].source_ip_cidr,"192.0.2.10/32") && contains(routes[0].port,443),"source or port scope lost");
let selectors=filter(config.outbounds,function(o){return o.tag=="moscow-out";});
expect(length(selectors)==1 && contains(selectors[0].outbounds,"chosen-moscow-node"),"chosen Moscow node not in section selector");
let dns=filter(config.dns.rules,function(r){return contains(r.rule_set,tag);});
expect(length(dns)>0,"Gemini DNS query rule missing");
for(let r in dns){
 expect(r.match_response!==true,"Gemini incorrectly treated as response/address ruleset");
 expect(r.server=="fakeip-server","Gemini did not use standard proxied FakeIP DNS");
 expect(contains(r.source_ip_cidr,"192.0.2.10/32"),"DNS source scope lost");
}
let direct=filter(config.route.rules,function(r){return contains(r.domain_suffix,"unrelated.example.test");});
expect(length(direct)==1 && direct[0].outbound=="bypass-out","unrelated direct section changed");
UCODE
    ucode -L "$LIB" "$WORK/check.uc" "$WORK/$mode.json" "$mode"
done
echo 'Inline Google Gemini: five suffixes, Moscow routing, FakeIP DNS, source/port scope and unrelated bypass passed'
