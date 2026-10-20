'use strict';
// Local Tools-only UI inspection. No orders, claims, grants or match state changes.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {ConsoleSession} = require('../map_c6/console-session.cjs');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'design_refs/daily_stargold_integration_20261019');
function latest(label, expression) {
  const log = fs.readFileSync(path.resolve(root, '../../dota/console.log'), 'utf8');
  const line = log.split(/\r?\n/).filter(value => value.includes(label)).at(-1);
  const match = line && line.match(expression);
  if (!match) throw Error('Current UI command unavailable: ' + label);
  return match[0];
}
async function main() {
  const action = process.argv[2] || 'commands';
  let commands;
  if (action === 'commands') commands = 'find panorama';
  else if (action === 'inspect') commands = latest('[WINDOW_STYLE_REVIEW]', /survival_window_review_\d+/) + ' inspect';
  else if (action === 'open' || action === 'close') commands = latest('[WINDOW_STYLE_REVIEW]', /survival_window_review_\d+/) + (action === 'open' ? ' benefit' : ' close');
  else throw Error('Supported actions: commands, inspect, open, close');
  const s = new ConsoleSession({port:29000, timeoutMs:6000, historyTimeoutMs:15000, retainOutput:false});
  try {
    await s.connect();
    const marker = 'DAILY_STARGOLD_NATIVE_' + crypto.randomBytes(12).toString('hex');
    const result = await s.send([{name:'console_send', arguments:{commands:commands+'\necho '+marker}}],marker,300);
    const safe = result.output.split(/\r?\n/).filter(line => !/(?:token|password|secret|authorization|credential)/i.test(line) && !line.includes(marker));
    const record = {at:new Date().toISOString(), action, commands, native:true, matched:result.expected_output_received, output:safe.join('\n')};
    fs.mkdirSync(out,{recursive:true});
    fs.writeFileSync(path.join(out, 'native_'+action+'_'+Date.now()+'.json'), JSON.stringify(record,null,2));
    console.log(JSON.stringify(record,null,2));
  } finally {await s.close();}
}
main().catch(error => {console.error(error.message);process.exitCode=1;});
