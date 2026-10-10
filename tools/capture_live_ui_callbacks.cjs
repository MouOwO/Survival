'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { connect } = require('./map_c6/console-session.cjs');
const command = commands => ({ name: 'console_send', arguments: { commands } });
const lua = code => ({ name: 'dota_run_lua', arguments: { code } });
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const directory = path.resolve(__dirname, '../output/live_ui_callbacks/' + Date.now());
  fs.mkdirSync(directory, { recursive: true });
  const session = await connect({ port: 29001, timeoutMs: 10000, historyTimeoutMs: 15000 });
  let ready = false, fps = 0, restoreAttack;
  const lowAttack = process.argv.includes('--low-attack');
  const liveWarmupMs = process.argv.includes('--settled-ui') ? 6000 : 1500;
  // Stable native aliases may retain a destroyed Panorama context after reload.
  // Use the commands registered by the newest actual client context instead.
  const log = fs.readFileSync(path.resolve(__dirname, '../../../dota/console.log'), 'utf8');
  const registrations = log.split(/\r?\n/).filter(line => line.includes('[TOOLS_PROBE_COMMANDS] '))
    .map(line => JSON.parse(line.slice(line.indexOf('{'))))
    .filter(value => value.api === 'SurvivalClientCallbackProbe');
  const probe = registrations.at(-1)?.commands;
  if (!probe || !Object.values(probe).every(value => /^survival_client_callback_\w+$/.test(value))) {
    await session.close(); throw new Error('Current client Tools probe commands unavailable');
  }
  try {
    const value = await session.send([command('cl_showfps')], '', 400);
    const match = value.output.match(/"?cl_showfps"?\s*=\s*"?(\d+)/);
    if (match) fps = Number(match[1]);
    const prepared = await session.send([lua('require("tests/manual_live_combat_diagnosis").prepare()')], 'LIVE_DIAG_READY');
    ready = true;
    if (lowAttack) {
      const before = prepared.output.split(/\r?\n/).find(line => line.startsWith('[LIVE_DIAG_STATE] '));
      const state = before && JSON.parse(before.slice('[LIVE_DIAG_STATE] '.length));
      if (!state || !Number.isFinite(state.debug_attack) || state.debug_attack <= 0) {
        throw new Error('Low-attack comparison requires an existing restorable debug override');
      }
      restoreAttack = state.debug_attack;
      await session.send([lua('local r=require("core/event_bus").request("hero.combat_stats.debug_attack.request",{player_id=0,attack=1000000}) assert(r and r.ok,"temporary attack change failed") print("LOW_ATTACK_READY")')], 'LOW_ATTACK_READY');
    }
    // Resource reload and generated Lua compilation stay outside timed capture.
    await sleep(10000);
    await session.send([command('survival_live_diag_20261010 begin')], 'LIVE_DIAG_BEGIN');
    await sleep(liveWarmupMs);
    await session.send([command(probe.start + '\ncl_showfps 4\ncl_resetfps\nvprof_off\nvprof_on\nvprof_reset')], '', 500, { responsePrefix: '[CLIENT_CALLBACK_PROBE] started ' });
    console.log('UI_CALLBACK_CAPTURE_RUNNING');
    await sleep(20000);
    await session.send([command(probe.report + '\ncl_printfps\nvprof_generate_report\nvprof_off')], '', 1500);
    await session.send([command('survival_live_diag_20261010 report')], 'LIVE_DIAG_REPORT');
  } finally {
    await session.send([command(probe.stop + '\ncl_showfps ' + fps + '\nvprof_off')], '', 400);
    if (restoreAttack !== undefined) {
      await session.send([lua('local r=require("core/event_bus").request("hero.combat_stats.debug_attack.request",{player_id=0,attack=' + restoreAttack + '}) assert(r and r.ok,"original attack restoration failed") print("ORIGINAL_ATTACK_RESTORED")')], 'ORIGINAL_ATTACK_RESTORED');
    }
    if (ready) await session.send([command('survival_live_diag_20261010 cleanup')], 'LIVE_DIAG_CLEAN');
    fs.writeFileSync(path.join(directory, 'capture.log'), session.rawOutput);
    const csv = path.resolve(__dirname, '../prof_template_map.csv');
    if (fs.existsSync(csv)) fs.copyFileSync(csv, path.join(directory, 'client_frames.csv'));
    console.log('ARTIFACT ' + directory);
    console.log(session.rawOutput.split(/\r?\n/).filter(line => /\[CLIENT_CALLBACK_PROBE\]|LIVE_DIAG_CLOCK|Average.*fps|Peak.*frame/.test(line)).join('\n'));
    await session.close();
  }
})().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
