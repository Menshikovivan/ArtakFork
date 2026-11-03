const fs=require('fs'),cp=require('child_process'),path=require('path'),assert=require('assert');
const src=fs.readFileSync('install.sh','utf8');
const get=n=>src.match(new RegExp(n+'\\(\\) \\{[\\s\\S]*?\\n\\}'))[0];
const sh=process.env.ARTAK_TEST_SH||(process.platform==='win32'?path.resolve(path.dirname(cp.execFileSync('where.exe',['git'],{encoding:'utf8'}).trim().split(/\r?\n/)[0]),'../usr/bin/sh.exe'):'/bin/sh');
function run(failure){let script=`ARTAK_TXN_ARMED=0; ARTAK_ROLLBACK_READY=0; backup_file=/tmp/test; FORKOP_PACKAGE_VERSION=test; REPO_OWNER=test; REPO_NAME=test; FORKOP_RELEASE_TAG=test
stage(){ echo STAGE:$1; [ '${failure}' != "$1" ] || exit 7; }
parse_args(){ :; }; check_root(){ :; }; init_tmp_dir(){ :; }; detect_fetcher(){ :; }; sync_time(){ :; }; check_system(){ :; }; check_artak_free_space(){ :; }; check_artak_uci_clean(){ :; }; detect_legacy_installation(){ :; }; decide_i18n_installation(){ :; }; select_sing_box_installation(){ :; }; pkg_list_update(){ :; }; ensure_bootstrap_ucode_runtime(){ :; }; resolve_forkop_release(){ :; }; download_forkop_packages(){ :; }; download_artak_srs(){ :; }; prepare_artak_xray(){ :; }; prepare_artak_community_lists(){ :; }; backup_artak_configuration(){ :; }; prepare_artak_rollback(){ stage preflight; ARTAK_ROLLBACK_READY=1; }; cleanup_legacy_installation(){ stage cleanup; }; install_backend_package(){ stage backend; }; migrate_legacy_configuration(){ :; }; install_ui_packages(){ :; }; install_selected_sing_box(){ :; }; install_artak_srs(){ :; }; install_artak_xray(){ :; }; install_artak_community_lists(){ :; }; uci(){ stage uci; }; post_install(){ stage post; }; restore_artak_previous(){ echo RESTORE; }; cleanup(){ echo CLEAN; }; msg(){ :; }; warn(){ :; }; fail(){ exit 1; }
${get('installer_exit')}
${get('main')}
main`;
return cp.spawnSync(sh,['-c',script],{encoding:'utf8'});}
for(const stage of ['cleanup','backend','uci','post']){let r=run(stage);assert.notStrictEqual(r.status,0,stage);assert(r.stdout.includes('RESTORE'),stage);assert(r.stdout.indexOf('RESTORE')<r.stdout.indexOf('CLEAN'),stage);}
let early=run('preflight');assert.notStrictEqual(early.status,0);assert(!early.stdout.includes('RESTORE'));
let ok=run('none');assert.strictEqual(ok.status,0,ok.stdout+ok.stderr);assert(!ok.stdout.includes('RESTORE'));assert(ok.stdout.includes('STAGE:uci'));
console.log('Installer transaction success and injected failures: PASS');
