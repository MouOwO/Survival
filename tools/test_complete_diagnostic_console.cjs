'use strict';
// Pure guard tests; no native process, filesystem fixture, GUI or TCP operation.
const assert = require('node:assert/strict');
const path = require('node:path');
const d = require('./complete_delivery_release_20261103/diagnostic_console.cjs');
const root = path.resolve(__dirname, '..');
const installedPath = path.resolve(root, '../../../../../workshop/content/570/3824360109');
const clone = value => JSON.parse(JSON.stringify(value));
const s = {packageSha: 'a'.repeat(64), transaction: 'complete0603_run01', name: 'pause01'};
const auth = {release_sequence: 2026110603};
const binding = {package_report_sha256: s.packageSha, operator_revision: 'b'.repeat(40), content_sha256: 'c'.repeat(64),
  signed_manifest_sha256: 'd'.repeat(64), source_revision: 'e'.repeat(40),
  source_revisions: {game: 'e'.repeat(40), content: 'f'.repeat(40)},
  collection_source_revisions: {game: 'e'.repeat(40), content: 'f'.repeat(40), operator: 'b'.repeat(40)}};
const files = [{name: '3824360109.vpk', bytes: 500, sha256: '1'.repeat(64)},
  {name: '3824360109_000.vpk', bytes: 1000, sha256: '2'.repeat(64)}];
const pkg = {...binding, release_sequence: 2026110603, status: 'BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION', package_files: files};
const live = {...binding, kind: 'COMPLETE_SIGNED_PACKAGE_ORDINARY_REHEARSAL', owned_launch: true, tools: false,
  cheats_requested: false, offline_logic_requested: false, http_requested: true, workshop_id: '3824360109', port: 29072,
  executable: path.resolve(root, '../../bin/win64/dota2.exe'), file_hold_mode: 'GENERIC_READ_FILE_SHARE_READ_ONLY',
  log_file: path.join(root, 'output/complete_delivery_rehearsal_20261103/complete0603_run01/engine.log'),
  log_origin: 'DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT', launch_route: 'direct', pid: 123,
  native_created_filetime: '134384335261757578', command_line_sha256: '3'.repeat(64),
  keeper: {pid: 124, native_created_filetime: '134384334147749422', command_line_sha256: '4'.repeat(64)}, code_pins: {},
  held_files: files.map((f, i) => ({name: f.name, path: path.join(installedPath, f.name), bytes: f.bytes, file_index: String(100 + i), volume_serial: 42}))};
live.argv = d.expectedArgv(live.log_file, 'direct');
const installed = {...binding, status: 'COMPLETE_SIGNED_CANDIDATE_INSTALLED', original_backup_preserved: true, acf_written: false, journal_written: false};
const transaction = {...binding, kind: live.kind, transaction_id: s.transaction, installed: installedPath, candidate_files: files, code_pins: {}};
function validate(p = pkg, l = live, i = installed, t = transaction) { d.validateLoaded(s, auth, p, l, i, t); }
validate();
assert.deepEqual(d.options([]), {help: true});
const args = ['--action', 'setpause', '--confirm-setpause', 'yes', '--package-sha256', s.packageSha, '--transaction', s.transaction, '--name', 'pause01'];
assert.deepEqual(d.options(args), s);
for (const change of [['--action', 'pause'], ['--action', 'dota_pause'], ['--confirm-setpause', 'no'], ['--transaction', '../complete0603_run01'], ['--name', 'a;quit']]) {
  const a = args.slice(); a[a.indexOf(change[0]) + 1] = change[1]; assert.throws(() => d.options(a));
}
assert.throws(() => d.options(args.concat(['--command', 'quit'])), /FIXED_UNIQUE/);
assert.throws(() => d.options(args.concat(['--action', 'setpause'])), /FIXED_UNIQUE/);
for (const mutate of [l => {l.argv = l.argv.filter(v => v !== '-vconsole');}, l => {l.argv.push('+quit');},
  l => {l.port = 29073;}, l => {l.tools = true;}, l => {l.owned_launch = false;}, l => {l.source_revisions.game = '0'.repeat(40);},
  l => {l.held_files[0].file_index = 'NaN';}, l => {l.held_files[0].path = path.join(installedPath, 'other.vpk');},
  l => {l.file_hold_mode = 'SHARED_WRITE';}]) { const l = clone(live); mutate(l); assert.throws(() => validate(pkg, l)); }
const badInstalled = clone(installed); badInstalled.package_report_sha256 = '0'.repeat(64);
assert.throws(() => validate(pkg, live, badInstalled), /PACKAGE_SHA/);
const badTransaction = clone(transaction); badTransaction.candidate_files.pop();
assert.throws(() => validate(pkg, live, installed, badTransaction), /TRANSACTION/);
const native = {pid: live.pid, name: 'dota2', executable: live.executable, native_created_filetime: live.native_created_filetime,
  command_line_sha256: live.command_line_sha256, keeper_pid: live.keeper.pid, keeper_native_created_filetime: live.keeper.native_created_filetime,
  keeper_command_line_sha256: live.keeper.command_line_sha256, listeners: [{pid: live.pid, port: 29072, address: '127.0.0.1'}],
  files: live.held_files.map(({name, bytes, file_index, volume_serial}) => ({name, bytes, file_index, volume_serial}))};
d.validateNative({live}, native);
for (const mutate of [n => {n.pid++;}, n => {n.native_created_filetime = '134384335261757579';}, n => {n.keeper_pid++;},
  n => {n.command_line_sha256 = '0'.repeat(64);}, n => {n.listeners = [];}, n => {n.listeners[0].pid++;},
  n => {n.listeners[0].port++;}, n => {n.files[0].file_index = '999';}, n => {n.files[0].bytes++;},
  n => {n.files.push(n.files[0]);}, n => {n.files[0].volume_serial++;}]) {
  const n = clone(native); mutate(n); assert.throws(() => d.validateNative({live}, n));
}
console.log('PASS: explicit one-shot command, immutable receipts, exact native argv/generations/listener and held file identity guards; no GUI/TCP executed.');
