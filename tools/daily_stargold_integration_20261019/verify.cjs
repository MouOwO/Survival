'use strict';
// Exercise real daily/payment code in the existing simulated Panorama harness.
// This report deliberately does not claim native raster or font verification.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const tests = [
  ['tools/tests/daily_accepted_layout.test.cjs'],
  ['tools/tests/daily_button_feedback.test.cjs'],
  ['tools/test_monthly_pass_checkout.cjs'],
  ['tools/tests/daily_unique_tooltip.test.cjs'],
  ['tools/tests/daily_tooltip_dismiss.test.cjs'],
  ['--test', 'tools/tests/daily_monthly_price.test.cjs'],
  ['tools/test_daily_reward_feedback.cjs']
];
const report = {at:new Date().toISOString(), kind:'real_production_JS_simulated_Panorama_regression',
  nativeGameCapture:false, nativeFontRasterizationVerified:false, tests:[], sourceHashes:{}};
for (const source of ['scripts/custom_game/daily_gw2_data.js',
  'scripts/custom_game/daily_remaining_5d5c1152eb.js', 'styles/custom_game/daily_gw2.css',
  'layout/custom_game/daily_gw2_assets.xml']) {
  report.sourceHashes['panorama/src/' + source] = crypto.createHash('sha256')
    .update(fs.readFileSync(path.join(root, 'panorama/src', source))).digest('hex');
}
for (const args of tests) {
  const result = spawnSync(process.execPath, args, {cwd:root, encoding:'utf8', windowsHide:true,
    timeout:60000, maxBuffer:1024 * 1024});
  const row = {command:['node', ...args].join(' '), status:result.status === 0 ? 'PASS' : 'FAIL',
    exitCode:result.status, signal:result.signal, output:(result.stdout || '') + (result.stderr || '')};
  if (result.error) row.error = result.error.message;
  report.tests.push(row);
  console.log(row.status + ' ' + args.at(-1));
  if (row.status === 'FAIL') console.log(row.output.trim());
}
report.status = report.tests.every(row => row.status === 'PASS') ? 'PASS' : 'FAIL';
const output = path.join(root, 'design_refs/daily_stargold_integration_20261019/regression.json');
fs.mkdirSync(path.dirname(output), {recursive:true});
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log('DAILY_STARGOLD_REGRESSION_' + report.status + ': ' + report.tests.length + ' suites; native rasterization requires game capture');
if (report.status !== 'PASS') process.exitCode = 1;
