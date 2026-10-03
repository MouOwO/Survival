const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const root = path.resolve(__dirname, '..');
const csvCopy = path.join(root, 'output/tower_visual_test/tower_visual_profiles.csv');
fs.mkdirSync(path.dirname(csvCopy), { recursive: true });
fs.copyFileSync(path.join(root, 'data/csv/资源系统/tower_visual_profiles.csv'), csvCopy);
const lua = process.env.LUA51 || (process.platform === 'win32' ? 'C:/Program Files/lua/bin/lua5.1.exe' : 'lua5.1');
const result = spawnSync(lua, ['scripts/vscripts/tests/test_tower_visual_lifecycle.lua', csvCopy], {
    cwd: root, encoding: 'utf8', windowsHide: true
});
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.error) throw result.error;
process.exitCode = result.status === null ? 1 : result.status;
