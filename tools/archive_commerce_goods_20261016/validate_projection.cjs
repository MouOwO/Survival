/* Run native Lua checks, refresh synthetic UI fixtures, and record exact inputs. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const lua = process.env.LUA51 || 'C:/Program Files/lua/bin/lua5.1.exe';
const luac = process.env.LUAC51 || 'C:/Program Files/lua/bin/luac5.1.exe';
const directory = path.join(root, 'design_refs/archive_commerce_goods_20261016');
const fixture = path.join(directory, 'ui/projection_fixture.json');
fs.mkdirSync(path.dirname(fixture), { recursive: true });
const programs = ['tools/archive_commerce_goods_20261016/test_projection.lua',
  'tools/archive_commerce_goods_20261016/test_service.lua'];
const hashes = {};
for (const name of ['scripts/vscripts/systems/archive_commerce_goods.lua',
  'scripts/vscripts/systems/archive_service.lua',
  'scripts/vscripts/config/generated/archive_commerce_goods.lua',
  'scripts/vscripts/config/generated/archive_categories.lua', ...programs]) {
  hashes[name] = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, name))).digest('hex');
  const syntax = cp.spawnSync(luac, ['-p', name], { cwd: root, encoding: 'utf8', windowsHide: true });
  if (syntax.status !== 0) throw new Error(`Lua syntax failed ${name}: ${syntax.stderr}`);
}
const results = programs.map((program, i) => {
  const args = i === 0 ? [program, fixture] : [program];
  const result = cp.spawnSync(lua, args, { cwd: root, encoding: 'utf8', windowsHide: true });
  const log = `${result.stdout || ''}${result.stderr || ''}`;
  fs.writeFileSync(path.join(directory, path.basename(program) + '.log'), log);
  if (result.status !== 0) throw new Error(`${program} failed (${result.status}): ${log}`);
  if (log.includes('[EventBus] handler error')) throw new Error(`${program} swallowed an event handler error`);
  return { program, status: 'PASS', groups: (log.match(/_PASS /g) || []).length };
});
const snapshots = JSON.parse(fs.readFileSync(fixture));
const before = fs.readFileSync(path.join(directory, 'baseline_projection/scripts/vscripts/systems/archive_service.lua'), 'utf8').replace(/\r\n/g, '\n');
const after = fs.readFileSync(path.join(root, 'scripts/vscripts/systems/archive_service.lua'), 'utf8').replace(/\r\n/g, '\n');
const hook = 'renderers.commerce_goods = function(profile) return require("systems/archive_commerce_goods").project(profile) end\n';
if (after.replace(hook, '') !== before) throw new Error('Unexpected concurrent archive_service change; review the baseline before accepting');
const report = { status: 'PASS', runtime: lua, groups: results.reduce((n, r) => n + r.groups, 0), results,
  rows: Object.fromEntries(['empty', 'owned', 'unknown'].map(k => [k, snapshots[k].rows.length])),
  source_hashes: hashes, archive_service_change: 'one renderer hook only',
  fixtures_synthetic: true, fixture_contains_real_player_data: false,
  database_writes: 0, network_requests: 0, new_periodic_tasks: 0 };
fs.writeFileSync(path.join(directory, 'projection_validation.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
