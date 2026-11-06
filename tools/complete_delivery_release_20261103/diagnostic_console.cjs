'use strict';
// Explicit, one-shot native pause diagnostic. No paid action, GUI, arbitrary
// command, Lua, launch, binding change, retry, or native-admission shortcut.
// Cost: O(V) metadata/identity queries for V held VPK files; zero VPK byte reads.
// One connection and one setpause + nonce command batch. Idle cost is zero.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const ROOT = path.resolve(__dirname, '../..');
const AUTHORITY = path.join(ROOT, 'publishing/workshop/release_authority_complete_20261103.json');
const STORE = 'D:/Survival_本地排演/complete_delivery_20261103';
const INSTALLED = path.resolve(ROOT, '../../../../../workshop/content/570/3824360109');
const EXE = path.resolve(ROOT, '../../bin/win64/dota2.exe');
const PORT = 29072;
const TRANSPORT = path.join(ROOT, 'tools/map_c6/console-session.cjs');
const CODEC = path.join(ROOT, 'tools/map_c6/console.cjs');
const PINS = [[TRANSPORT, '30384f6799afe7375c1729d2bb0ab77987cdb608fb5b064ac12a55bc6211c3f6'],
  [CODEC, 'dc2698c1fd1e79e62f744ab34b373aeaecfea31d85644bd9099cf56c93a94065']];
const CLOSED = ['close_intent.json', 'hold_end.json', 'hold_failed.json', 'restored.json', 'interrupted_recovery.json'];
function need(ok, code) { if (!ok) throw new Error(code); }
function sha(raw) { return crypto.createHash('sha256').update(raw).digest('hex'); }
function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
function options(args) {
  if (!args.length || same(args, ['--help'])) return {help: true};
  const allowed = new Set(['--action', '--package-sha256', '--transaction', '--name', '--confirm-setpause']);
  need(args.length % 2 === 0, 'EXPLICIT_OPTION_VALUES_REQUIRED');
  const o = {};
  for (let n = 0; n < args.length; n += 2) {
    need(allowed.has(args[n]) && !Object.hasOwn(o, args[n]), 'FIXED_UNIQUE_OPTIONS_REQUIRED');
    o[args[n]] = args[n + 1];
  }
  need(o['--action'] === 'setpause' && o['--confirm-setpause'] === 'yes', 'EXPLICIT_SET_PAUSE_REQUIRED');
  need(/^[a-f0-9]{64}$/.test(o['--package-sha256'] || ''), 'ACTUAL_SIGNED_REPORT_SHA_REQUIRED');
  need(/^complete[0-9]{4}_run[0-9]{2}$/.test(o['--transaction'] || ''), 'EXACT_COMPLETE_TRANSACTION_REQUIRED');
  need(/^[A-Za-z0-9][A-Za-z0-9_-]{0,60}$/.test(o['--name'] || ''), 'UNIQUE_SAFE_NAME_REQUIRED');
  return {packageSha: o['--package-sha256'], transaction: o['--transaction'], name: o['--name']};
}
function regular(file) {
  const resolved = path.resolve(file), root = path.parse(resolved).root;
  let current = root;
  for (const component of resolved.slice(root.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, component);
    need(!fs.lstatSync(current).isSymbolicLink(), 'REPARSE_PATH_REFUSED');
  }
  return resolved;
}
function readJson(file, limit = 2 * 1024 * 1024) {
  const p = regular(file), st = fs.statSync(p);
  need(st.isFile() && st.size <= limit, 'BOUNDED_REGULAR_JSON_REQUIRED');
  const raw = fs.readFileSync(p);
  const value = JSON.parse(raw.toString('utf8').replace(/^\uFEFF/, '')
    .replace(/("(?:native_created_filetime|file_index)"\s*:\s*)(\d+)/g, '$1"$2"'));
  return {raw, value, sha: sha(raw)};
}
function expectedArgv(log, route) {
  need(route === 'direct' || route === 'lobby', 'FIXED_LAUNCH_ROUTE_REQUIRED');
  return ['-steam', '-novid', '-console', '-vconsole', '-vconport', String(PORT), '-condebug', '-con_logfile', log,
    '+sv_cheats', '0', '+survival_archive_http_enabled', '1', '+net_showmsg', 'CUserMsg_CustomGameEvent',
    '+net_restrict_showmsg_socket', 'client'].concat(route === 'direct' ? ['+dota_launch_custom_game', '3824360109', 'ws4_entry'] : []);
}
function validateLoaded(s, auth, pkg, live, installed, transaction) {
  need(auth.release_sequence === pkg.release_sequence && Number.isSafeInteger(pkg.release_sequence) &&
    s.transaction.startsWith('complete' + String(pkg.release_sequence).slice(-4) + '_run'), 'CURRENT_CANDIDATE_SEQUENCE_REQUIRED');
  need(pkg.status === 'BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION', 'SIGNED_CANDIDATE_REQUIRED');
  need(live.kind === 'COMPLETE_SIGNED_PACKAGE_ORDINARY_REHEARSAL' && live.owned_launch === true &&
    live.tools === false && live.cheats_requested === false && live.offline_logic_requested === false &&
    live.http_requested === true && live.workshop_id === '3824360109' && live.port === PORT &&
    path.resolve(live.executable) === EXE && live.file_hold_mode === 'GENERIC_READ_FILE_SHARE_READ_ONLY', 'OWNED_ORDINARY_HELD_PROCESS_REQUIRED');
  const log = path.join(ROOT, 'output/complete_delivery_rehearsal_20261103', s.transaction, 'engine.log');
  need(path.resolve(live.log_file) === log && live.log_origin === 'DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT' &&
    same(live.argv, expectedArgv(live.log_file, live.launch_route)), 'EXACT_NATIVE_VCONSOLE_ARGV_REQUIRED');
  need(installed.status === 'COMPLETE_SIGNED_CANDIDATE_INSTALLED' && installed.original_backup_preserved === true &&
    installed.acf_written === false && installed.journal_written === false, 'CANONICAL_INSTALLATION_REQUIRED');
  need(transaction.kind === live.kind && transaction.transaction_id === s.transaction &&
    path.resolve(transaction.installed) === INSTALLED && same(transaction.candidate_files, pkg.package_files) &&
    same(transaction.code_pins, live.code_pins), 'EXACT_INSTALL_TRANSACTION_REQUIRED');
  for (const receipt of [live, installed, transaction]) {
    need(receipt.package_report_sha256 === s.packageSha, 'RECEIPT_PACKAGE_SHA_CHANGED');
    for (const key of ['operator_revision', 'content_sha256', 'signed_manifest_sha256', 'source_revision']) {
      need(receipt[key] === pkg[key], 'RECEIPT_IMMUTABLE_BINDING_CHANGED');
    }
    for (const key of ['source_revisions', 'collection_source_revisions']) need(same(receipt[key], pkg[key]), 'SOURCE_PAIR_CHANGED');
  }
  need(Number.isSafeInteger(live.pid) && live.pid > 0 && Number.isSafeInteger(live.keeper?.pid) && live.keeper.pid > 0 &&
    /^\d{17,19}$/.test(live.native_created_filetime) && /^\d{17,19}$/.test(live.keeper.native_created_filetime) &&
    /^[a-f0-9]{64}$/.test(live.command_line_sha256) && /^[a-f0-9]{64}$/.test(live.keeper.command_line_sha256), 'EXACT_NATIVE_GENERATIONS_REQUIRED');
  need(Array.isArray(pkg.package_files) && pkg.package_files.length >= 2 && pkg.package_files.length <= 1001 &&
    Array.isArray(live.held_files) && live.held_files.length === pkg.package_files.length, 'COMPLETE_HELD_FILE_SET_REQUIRED');
  const held = new Map(live.held_files.map(f => [f.name, f]));
  need(held.size === pkg.package_files.length, 'UNIQUE_HELD_FILE_SET_REQUIRED');
  pkg.package_files.forEach((file, index) => {
    const name = index ? '3824360109_' + String(index - 1).padStart(3, '0') + '.vpk' : '3824360109.vpk';
    const h = held.get(name);
    need(file.name === name && Number.isSafeInteger(file.bytes) && file.bytes > 0 && h && h.bytes === file.bytes &&
      /^[a-f0-9]{64}$/.test(file.sha256) && path.resolve(h.path) === path.join(INSTALLED, name) &&
      /^\d{1,20}$/.test(h.file_index) && Number.isInteger(h.volume_serial), 'EXACT_HELD_FILE_IDENTITY_REQUIRED');
  });
}
function binding(s) {
  const a = readJson(AUTHORITY), auth = a.value;
  const reportDir = path.resolve(auth.report_directory || '');
  need(reportDir.startsWith(path.join(ROOT, 'output') + path.sep) &&
    path.resolve(auth.recipe_path) === path.join(__dirname, 'pipeline_recipe.py'), 'FIXED_AUTHORITY_REPORT_REQUIRED');
  const p = readJson(path.join(reportDir, 'package.json'), 64 * 1024 * 1024);
  need(p.sha === s.packageSha, 'EXACT_SIGNED_REPORT_SHA_REQUIRED');
  const folder = path.join(STORE, s.transaction);
  CLOSED.forEach(name => need(!fs.existsSync(path.join(folder, name)), 'CLOSED_TRANSACTION_REFUSED'));
  const l = readJson(path.join(folder, 'process.json'));
  const i = readJson(path.join(folder, 'installed.json'));
  const t = readJson(path.join(folder, 'transaction.json'));
  validateLoaded(s, auth, p.value, l.value, i.value, t.value);
  for (const [file, digest] of PINS) need(sha(fs.readFileSync(regular(file))) === digest, 'REVIEWED_TRANSPORT_CHANGED');
  for (const [file, digest] of Object.entries(l.value.code_pins || {})) {
    need(path.resolve(file).startsWith(path.join(ROOT, 'tools') + path.sep) && /^[a-f0-9]{64}$/.test(digest) &&
      sha(fs.readFileSync(regular(file))) === digest, 'CANONICAL_OPERATOR_PIN_CHANGED');
  }
  need(l.value.code_pins?.[auth.rehearsal_path.replaceAll('/', '\\')] === auth.rehearsal_sha256 ||
    l.value.code_pins?.[auth.rehearsal_path] === auth.rehearsal_sha256, 'CURRENT_AUTHORITY_OPERATOR_REQUIRED');
  return {live: l.value, reportDir, pins: [a.sha, p.sha, l.sha, i.sha, t.sha]};
}
function validateNative(bound, actual) {
  const live = bound.live;
  for (const key of ['pid', 'native_created_filetime', 'command_line_sha256']) need(actual[key] === live[key], 'LIVE_PROCESS_GENERATION_CHANGED');
  need(path.resolve(actual.executable) === EXE && actual.name === 'dota2' &&
    actual.keeper_pid === live.keeper.pid && actual.keeper_native_created_filetime === live.keeper.native_created_filetime &&
    actual.keeper_command_line_sha256 === live.keeper.command_line_sha256, 'LIVE_KEEPER_OR_EXECUTABLE_CHANGED');
  need(Array.isArray(actual.listeners) && actual.listeners.length > 0 && actual.listeners.length <= 4 &&
    actual.listeners.every(l => l.pid === live.pid && l.port === PORT && ['127.0.0.1', '0.0.0.0', '::', '::1'].includes(l.address)),
    'OWNED_NATIVE_VCONSOLE_LISTENER_REQUIRED');
  need(actual.files.length === live.held_files.length, 'INSTALLED_FILE_SET_CHANGED');
  const index = new Map(actual.files.map(f => [f.name, f]));
  need(index.size === live.held_files.length, 'DUPLICATE_INSTALLED_FILE');
  for (const expected of live.held_files) {
    const got = index.get(expected.name);
    need(got && ['bytes', 'file_index', 'volume_serial'].every(k => got[k] === expected[k]), 'INSTALLED_HELD_FILE_CHANGED');
  }
}
function inspectNative(bound) {
  const config = Buffer.from(JSON.stringify({pid: bound.live.pid, keeper: bound.live.keeper.pid, installed: INSTALLED})).toString('base64');
  // Only base64 of internally validated identity/path data is inserted into PS.
  const script = String.raw`$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$cfg=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${config}'))|ConvertFrom-Json
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Runtime.InteropServices;using Microsoft.Win32.SafeHandles;
public static class DiagnosticHeldFile {
 [StructLayout(LayoutKind.Sequential)] public struct Info {public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME Created,Access,Written; public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static string[] Read(string p) {using(var f=new FileStream(p,FileMode.Open,FileAccess.Read,FileShare.Read)){Info i;if(!GetFileInformationByHandle(f.SafeFileHandle,out i))throw new IOException("native_file_identity_failed");return new[]{f.Length.ToString(),i.Volume.ToString(),(((ulong)i.IndexHigh<<32)|i.IndexLow).ToString()};}}
}
'@
function Hash-Text([string]$t){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($t))).ToLowerInvariant()}
$g=Get-Process -Id $cfg.pid;$k=Get-Process -Id $cfg.keeper
$gc=Get-CimInstance -ErrorAction Stop Win32_Process -Filter ('ProcessId='+$cfg.pid)
$kc=Get-CimInstance -ErrorAction Stop Win32_Process -Filter ('ProcessId='+$cfg.keeper)
$listeners=@(Get-NetTCPConnection -LocalPort 29072 -State Listen -ErrorAction Stop|ForEach-Object{[ordered]@{address=$_.LocalAddress;port=[int]$_.LocalPort;pid=[int]$_.OwningProcess}})
$files=@(Get-ChildItem -LiteralPath $cfg.installed -Force|ForEach-Object{if($_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'unexpected_installed_entry'};$i=[DiagnosticHeldFile]::Read($_.FullName);[ordered]@{name=$_.Name;bytes=[long]$i[0];volume_serial=[uint32]$i[1];file_index=$i[2]}})
[ordered]@{pid=[int]$g.Id;name=$g.ProcessName;executable=$g.Path;native_created_filetime=$g.StartTime.ToUniversalTime().ToFileTimeUtc().ToString();command_line_sha256=(Hash-Text $gc.CommandLine);keeper_pid=[int]$k.Id;keeper_native_created_filetime=$k.StartTime.ToUniversalTime().ToFileTimeUtc().ToString();keeper_command_line_sha256=(Hash-Text $kc.CommandLine);listeners=$listeners;files=$files}|ConvertTo-Json -Depth 6 -Compress`;
  const reply = spawnSync('D:/7/pwsh.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')],
    {encoding: 'utf8', timeout: 20000, windowsHide: true, maxBuffer: 512 * 1024});
  need(!reply.error && reply.status === 0, 'READONLY_NATIVE_IDENTITY_QUERY_FAILED');
  const actual = JSON.parse(reply.stdout.replace(/^\uFEFF/, ''));
  validateNative(bound, actual);
  return actual;
}
function writeNew(file, data) {
  const fd = fs.openSync(file, 'wx');
  try { fs.writeFileSync(fd, JSON.stringify(data, null, 2) + '\n'); fs.fsyncSync(fd); }
  finally { fs.closeSync(fd); }
}
async function run(s) {
  const bound = binding(s), before = inspectNative(bound);
  const out = path.join(bound.reportDir, 'diagnostic_console', s.transaction);
  fs.mkdirSync(out, {recursive: true}); regular(out);
  const intent = path.join(out, s.name + '.intent.json'), resultPath = path.join(out, s.name + '.result.json');
  need(!fs.existsSync(resultPath), 'UNIQUE_DIAGNOSTIC_RESULT_REQUIRED');
  const result = {kind: 'NATIVE_SETPAUSE_DIAGNOSTIC_NOT_ADMISSION', transaction: s.transaction, package_report_sha256: s.packageSha,
    diagnostic_script_sha256: sha(fs.readFileSync(__filename)),
    pid: bound.live.pid, native_created_filetime: bound.live.native_created_filetime, binding_sha256: bound.pins,
    started_utc: new Date().toISOString(), status: 'NOT_SENT', sent: 0, marker_received: false, pause_state: 'UNVERIFIED',
    before, after: null, raw_output_retained: false, history_retained: false, paid_actions: 0, automatic_retry: false};
  writeNew(intent, {...result, status: 'EXPLICIT_SETPAUSE_INTENT'});
  const {ConsoleSession} = require(TRANSPORT);
  const session = new ConsoleSession({host: '127.0.0.1', port: PORT, timeoutMs: 4000, historyTimeoutMs: 10000,
    retainOutput: false, maxPendingOutputChars: 16384});
  const marker = 'SURVIVAL_NATIVE_SETPAUSE_' + crypto.randomBytes(16).toString('hex');
  try {
    await session.connect();
    inspectNative(bound);
    need(same(binding(s).pins, bound.pins), 'BINDING_CHANGED_BEFORE_SEND');
    const reply = await session.send([{name: 'console_send', arguments: {commands: 'setpause\necho ' + marker}}], marker, 150);
    result.sent = reply.sent; result.marker_received = reply.expected_output_received === true;
    need(result.marker_received, 'SET_PAUSE_TRANSPORT_NOT_ACKNOWLEDGED');
    result.after = inspectNative(bound);
    need(same(binding(s).pins, bound.pins), 'BINDING_CHANGED_AFTER_SEND');
    result.status = 'ACKNOWLEDGED_REQUIRES_ACTUAL_PAUSE_VISUAL_CONFIRMATION';
  } catch (error) {
    result.sent = Number.isInteger(error.sent) ? error.sent : result.sent;
    result.error_code = /^[A-Z0-9_]+$/.test(error.message || '') ? error.message : 'NATIVE_CONSOLE_DIAGNOSTIC_FAILED';
    result.status = 'FAILED_PRESERVED_NO_AUTOMATIC_RETRY';
  } finally {
    await session.close(); result.ended_utc = new Date().toISOString(); writeNew(resultPath, result);
  }
  return {result_path: resultPath, status: result.status, marker_received: result.marker_received,
    pause_state: result.pause_state, error_code: result.error_code || null};
}
if (require.main === module) (async () => {
  const selected = options(process.argv.slice(2));
  if (selected.help) { console.log('Explicit one-shot native setpause only: --action setpause --confirm-setpause yes --package-sha256 SHA --transaction completeNNNN_runNN --name UNIQUE. No GUI, arbitrary command, paid action, retry or acceptance. Echo does not prove paused state.'); return; }
  const result = await run(selected); console.log(JSON.stringify(result)); if (result.error_code) process.exitCode = 1;
})().catch(error => { console.error(JSON.stringify({status: 'REFUSED_OR_RECORD_FAILED', error_code:
  /^[A-Z0-9_]+$/.test(error.message || '') ? error.message : 'LOCAL_GUARD_OR_IO_FAILED'})); process.exitCode = 1; });
module.exports = {options, expectedArgv, validateLoaded, validateNative, binding};
