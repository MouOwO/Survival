'use strict';
// Query only the ordinary downloaded Workshop process bound to its live receipt.
// The logger reload must be rejected; no resource or profile commands are sent.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const { connect } = require('../map_c6/console-session.cjs');

async function main() {
  const [receiptArgument, pidArgument] = process.argv.slice(2);
  if (process.argv.length !== 4 || !/^[1-9][0-9]{0,9}$/.test(pidArgument || '')) {
    throw Error('receipt_and_pid_required');
  }
  const root = path.resolve(__dirname, '../..');
  const receiptPath = path.resolve(receiptArgument);
  const checked = cp.spawnSync('D:/Survival_安全工具/venv/Scripts/python.exe', [
    '-B', '-X', 'utf8', path.join(__dirname, 'launch_workshop.py'),
    '--check-receipt', receiptPath, '--pid', pidArgument,
  ], { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 20000 });
  if (checked.status !== 0) throw Error('ordinary_workshop_live_receipt_required');
  const proof = JSON.parse(checked.stdout);
  if (proof.ok !== true || proof.status !== 'ORDINARY_WORKSHOP_PROCESS_CHECKED'
      || proof.pid !== Number(pidArgument) || proof.port !== 29007) {
    throw Error('ordinary_workshop_live_receipt_required');
  }
  const target = path.join(path.dirname(receiptPath), 'cheat_gate.json');
  if (fs.existsSync(target)) throw Error('new_cheat_gate_report_required');
  const session = await connect({ port: 29007, timeoutMs: 6000, retainOutput: false });
  try {
    const response = await session.send([{ name: 'console_send', arguments: {
      commands: 'sv_cheats\nscript_reload_code core/logger',
    } }], '', 500);
    const lines = response.output.split(/\r?\n/)
      .filter(line => /sv_cheats|script_reload_code/.test(line)
        && !/[0-9]{15,}|https?:|Bearer/i.test(line))
      .map(line => line.slice(0, 512));
    const convarDisabled = lines.some(line => /sv_cheats["'\s=:]*(?:false|0)\b/i.test(line));
    const reloadRejected = lines.some(line => /script_reload_code/.test(line) && /cheat|sv_cheats/i.test(line));
    const report = {
      at_utc: new Date().toISOString(), pid: proof.pid, port: 29007,
      scope: 'ordinary_workshop_native_engine_not_private_database',
      receipt: path.relative(root, receiptPath).replaceAll('\\', '/'),
      lines, convar_disabled: convarDisabled, reload_rejected: reloadRejected,
      resource_commands_sent: false, cloud_database_access: false,
      passed: convarDisabled && reloadRejected,
    };
    fs.writeFileSync(target, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
    console.log(JSON.stringify(report));
    if (!report.passed) process.exitCode = 1;
  } finally {
    await session.close();
  }
}

main().catch(() => {
  console.error(JSON.stringify({ ok: false, error: 'ordinary_workshop_cheat_gate_check_failed' }));
  process.exitCode = 1;
});
