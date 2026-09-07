// Local, dependency-free browser checks. Does not connect to the game server.
const fs = require('fs'), path = require('path'), os = require('os'), assert = require('assert');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'archive-beast-review-'));
  const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', '--user-data-dir=' + profile, pathToFileURL(path.join(__dirname, 'index.html')).href], { windowsHide: true, stdio: 'ignore' });
  let ws;
  try {
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await sleep(100);
    const port = fs.readFileSync(portFile, 'utf8').split('\n')[0];
    const targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
    const target = targets.find(x => x.type === 'page');
    ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
    let serial = 0; const pending = new Map();
    ws.onmessage = event => { const m = JSON.parse(event.data); const p = pending.get(m.id); if (p) { pending.delete(m.id); m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result); } };
    const call = (method, params = {}) => new Promise((resolve, reject) => { const id = ++serial; pending.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params })); });
    const run = async expression => { const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails)); return result.result.value; };
    await call('Page.enable'); await call('DOM.enable'); await call('CSS.enable');
    await call('Emulation.setDeviceMetricsOverride', { width: 1600, height: 1080, deviceScaleFactor: 1, mobile: false });
    await run('document.fonts.ready');
    const geometry = await run(`(() => {
      const grid = document.getElementById('grid'), cards = [...grid.children], rect = grid.getBoundingClientRect();
      const sameRow = cards.filter(x => x.getBoundingClientRect().top === cards[0].getBoundingClientRect().top).length;
      return { count:cards.length, columns:sameRow, scrolling:grid.scrollHeight > grid.clientHeight, gridBottom:rect.bottom, footerTop:document.querySelector('.page-footer').getBoundingClientRect().top, categories:[...document.querySelectorAll('.nav-item')].map(x=>x.lastElementChild.textContent), disabled:document.getElementById('draw').disabled, unknown:cards.every(x=>x.querySelector('.current').textContent==='—') };
    })()`);
    assert.equal(geometry.count, 40); assert.equal(geometry.columns, 8); assert(geometry.scrolling); assert(geometry.gridBottom <= geometry.footerTop); assert(geometry.disabled && geometry.unknown);
    assert.equal(geometry.categories.length, 9); assert.equal(geometry.categories[8], '瑞兽赐福');
    const doc = await call('DOM.getDocument');
    const fonts = {};
    for (const selector of ['h1', 'h2', '.item-name', '.short-rule']) {
      const node = await call('DOM.querySelector', { nodeId: doc.root.nodeId, selector });
      fonts[selector] = (await call('CSS.getPlatformFontsForNode', { nodeId: node.nodeId })).fonts.map(x => ({ family: x.familyName, custom: x.isCustomFont, glyphs: x.glyphCount }));
    }
    const screenshot = async name => { const result = await call('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(__dirname, name), Buffer.from(result.data, 'base64')); };
    await screenshot('preview.png');
    const bottom = await run(`(() => { const g=document.getElementById('grid');g.scrollTop=g.scrollHeight;const r=g.lastElementChild.getBoundingClientRect();return {bottom:r.bottom,viewportBottom:g.getBoundingClientRect().bottom}; })()`);
    assert(bottom.bottom <= bottom.viewportBottom, 'last row must fit above fixed footer');
    await run(`document.querySelector('[data-id="beast_33"]').focus()`);
    const tip = await run(`document.getElementById('tooltip').textContent`);
    assert(tip.includes('七禽扇') && tip.includes('伐木工攻击成长+3'));
    await screenshot('preview-tooltip.png');
    // Synthetic test-only snapshot: never used in the default visual proposal.
    const states = await run(`(() => {
      const rows=ARCHIVE_DATA.rows.map((x,i)=>({id:x.id,count:i===0?1:i===1?x.target:0}));
      ArchivePreview.setSnapshot({category_id:'beast',rows,social:{tickets:95,remaining:100},last_draw:{pool_id:'beast',name:'七禽扇'}});
      const result={enabled:!document.getElementById('draw').disabled,owned:document.querySelectorAll('.item.owned').length,maxed:document.querySelectorAll('.item.maxed').length,unowned:document.querySelectorAll('.item.unowned').length,first:document.querySelector('.current').textContent};
      document.getElementById('draw').click(); result.pendingDisabled=document.getElementById('draw').disabled;
      ArchivePreview.setSnapshot({category_id:'beast',rows,social:{tickets:0,remaining:100}}); result.noMoneyDisabled=document.getElementById('draw').disabled;
      ArchivePreview.setSnapshot({category_id:'beast',rows,social:{tickets:95,remaining:0}}); result.fullPoolDisabled=document.getElementById('draw').disabled;
      ArchivePreview.setSnapshot({category_id:'beast',rows,social:{tickets:95,remaining:100},pending:1}); result.savingDisabled=document.getElementById('draw').disabled;
      return result;
    })()`);
    assert(states.enabled && states.pendingDisabled && states.noMoneyDisabled && states.fullPoolDisabled && states.savingDisabled);
    assert.equal(states.owned, 2); assert.equal(states.maxed, 1); assert.equal(states.unowned, 38); assert.equal(states.first, '1');
    fs.writeFileSync(path.join(__dirname, 'verification.json'), JSON.stringify({ geometry, bottom, fonts, states }, null, 2));
    console.log('PREVIEW_PASS: 40 items, 8 columns, 9 categories, fixed footer, last row visible, original effect tooltip, snapshot and draw states, actual font report.');
    await call('Browser.close');
  } finally { if (ws) ws.close(); chrome.kill(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
