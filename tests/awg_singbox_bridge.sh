#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
python3 - "$ROOT/forkop/files/usr/lib/service/lifecycle.uc" "$WORK/test.uc" "$WORK" <<'PY'
from pathlib import Path
import json, sys
text = Path(sys.argv[1]).read_text()
body = text[text.index('function awg_singbox_swap_bridge('):text.index('function awg_production_swap_factory(')]
body = body.replace("'/etc/forkop/awg-swap-config'", json.dumps(sys.argv[3] + '/backup'))
prefix = '''
let fs = require('fs'), root = getenv('AWG_BRIDGE_TEST_ROOT'), generation = 1, stop_fail = false, commits = 0;
let STATE_UC='state', SINGBOX_UC='singbox', CONFIG_NAME='forkop', RT_TABLE_NAME='100', NFT_TABLE_NAME='ForkopTable', NFT_FAKEIP_MARK='1';
let SECTION_CACHE_DIR = root + '/section-cache';
let SING_BOX_START_STABLE_MIN_AGE=1, SING_BOX_START_VERIFY_TIMEOUT=2;
function as_string(v) { return v == null ? '' : '' + v; }
function config_get() { return root + '/live.json'; }
function singbox_prepare_config_stage(path) { if (!fs.mkdir(path+'.section-cache',0700)) return 1; fs.writefile(path+'.section-cache/item.json','new-meta'); return fs.writefile(path,'new') == null ? 1 : 0; }
function command_output_from_args(args) { let d = fs.readfile(args[1]); return (d == 'old' ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' : d == 'new' ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' : '') + '  file'; }
function command_success_from_args(args) { if (args[0] == 'cp') return fs.writefile(args[3], fs.readfile(args[2])) != null; return false; }
function module_capture(mod,args) { return {status:0,output:sprintf('%J',{pid:100 + generation,start_ticks:200 + generation})}; }
function module_status(mod,args) {
 if (args[0] == 'stop-managed-sing-box-runtime') return stop_fail ? 1 : 0;
 if (args[0] == 'start-managed-sing-box-runtime') { generation++; return 0; }
 return 0;
}
function module_success(mod,args) {
 if (args[0] == 'commit-config-stage') { commits++; fs.writefile(SECTION_CACHE_DIR+'/item.json','new-meta'); return fs.writefile(args[2],fs.readfile(root+'/live.json')) != null && fs.writefile(root+'/live.json',fs.readfile(args[1])) != null; }
 if (args[0] == 'restore-config-stage') return fs.writefile(root+'/live.json',fs.readfile(args[1])) != null;
 if (args[0] == 'publish-section-cache') { if (fs.stat(SECTION_CACHE_DIR) == null && !fs.mkdir(SECTION_CACHE_DIR,0700)) return false; return fs.writefile(SECTION_CACHE_DIR+'/item.json',fs.readfile(args[1]+'.section-cache/item.json')) != null; }
 return true;
}
function expect(v,m) { if (!v) die('FAIL: ' + m + '\\n'); }
'''
suffix = '''
fs.writefile(root+'/live.json','old');
fs.mkdir(SECTION_CACHE_DIR,0700); fs.writefile(SECTION_CACHE_DIR+'/item.json','old-meta');
let h='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
let f=awg_singbox_swap_bridge({source:'src',old_generation:h},{valid:function(){return true;}},function(){return true;},function(){return true;},function(){return true;});
expect(f != null && f.reload() && f.verify_new(), 'new generation staged and verified');
expect(fs.readfile(root+'/live.json') == 'new', 'new config live');
generation++;
expect(!f.verify_new() && f.resume_new() && f.verify_new(), 'restart recovers new config with fresh process provenance');
fs.unlink(SECTION_CACHE_DIR+'/item.json'); fs.rmdir(SECTION_CACHE_DIR);
generation++;
expect(f.resume_new() && f.verify_new() && fs.readfile(SECTION_CACHE_DIR+'/item.json') == 'new-meta', 'reboot reconstructs missing section cache from durable backup');
fs.writefile(SECTION_CACHE_DIR+'/item.json','external-change');
expect(!f.resume_new(), 'restart refuses unexpected section cache');
expect(!f.restore_old() && fs.readfile(SECTION_CACHE_DIR+'/item.json') == 'external-change', 'refuses to overwrite unexpected cache');
fs.writefile(SECTION_CACHE_DIR+'/item.json','new-meta');
let recovered=awg_singbox_swap_bridge({source:'src',old_generation:h},{valid:function(){return true;}},function(){return true;},function(){return true;},function(){return true;});
expect(recovered.restore_old() && recovered.verify_old() && fs.readfile(root+'/live.json') == 'old', 'new bridge recovers old config after simulated process restart');
expect(fs.readfile(SECTION_CACHE_DIR+'/item.json') == 'old-meta', 'old section cache restored');
expect(fs.readfile(f.backup_dir+'/previous.json') == 'old', 'durable backup retained');
stop_fail=true;
let g=awg_singbox_swap_bridge({source:'src2',old_generation:h},{valid:function(){return true;}},function(){return true;},function(){return true;},function(){return true;});
expect(!g.reload() && commits == 1 && fs.readfile(root+'/live.json') == 'old', 'failed stop does not commit new config');
print('AWG sing-box bridge transition and rollback checks passed\\n');
'''
Path(sys.argv[2]).write_text(prefix + body + suffix)
PY
export AWG_BRIDGE_TEST_ROOT="$WORK"
ucode -L "$ROOT/forkop/files/usr/lib" "$WORK/test.uc"
