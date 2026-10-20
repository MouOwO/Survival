'use strict';
const fs = require('node:fs'), crypto = require('node:crypto');
const {ConsoleSession} = require('../map_c6/console-session.cjs');
(async () => {
    const nonce = 'native_mode_spawns_' + crypto.randomBytes(8).toString('hex');
    const prefix = '[MODE_SPAWN_PROBE][' + nonce + '] ';
    const session = new ConsoleSession({timeoutMs: 6000, historyTimeoutMs: 10000,
        retainOutput: false, maxPendingOutputChars: 1024 * 1024});
    try {
        await session.connect();
        const result = await session.send([{name: 'dota_run_lua', arguments: {
            code: `require('tests/mode_spawn_contract_probe').run('${nonce}')`,
        }}], '', 250, {responsePrefix: prefix + 'SUMMARY '});
        const lines = result.output.split(/\r?\n/).filter(line => line.startsWith(prefix));
        const summary = result.matched_line;
        const report = {nonce, summary, passed: summary.includes('SUMMARY ok=true markers=27 routes=12 modes=3 errors=0 restored=true'),
            read_only: true, log: lines};
        if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(report, null, 2) + '\n');
        console.log(JSON.stringify({passed: report.passed, summary}));
        if (!report.passed) process.exitCode = 1;
    } finally { await session.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
