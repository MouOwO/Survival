'use strict';

// Design review only: detached images and an isolated file:// Chrome profile.
// No Panorama, game client, account, network service, or real draw is invoked.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { browser, sleep } = require('../market_filter_20261017/browser.cjs');
const { fixture } = require('../lottery_gw2/fixture.cjs');

const root = path.resolve(__dirname, '../..');
const html = path.join(root, 'design_refs/lottery_five_official_20261019/五套官方抽奖界面.html');
const dataFile = path.join(root, 'output/lottery_five_official_20261019/data.json');
const out = path.join(root, 'output/lottery_five_official_20261019/qa');
const hash = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const report = { success: false, kind: 'offline-design-fixture', nativeGameVerified: false, html, generatedAt: new Date().toISOString(), checks: [], screenshots: [] };

function check(name, passed, details) {
    report.checks.push({ name, passed: !!passed, ...(details === undefined ? {} : { details }) });
    if (!passed) throw new Error(name + ': ' + JSON.stringify(details));
}
function saveReport() {
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
}

async function main() {
    fs.mkdirSync(out, { recursive: true });
    check('Final review HTML and fixture data exist', fs.existsSync(html) && fs.existsSync(dataFile));
    const data = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
    const formal = fixture();
    report.htmlSha256 = hash(fs.readFileSync(html));
    report.htmlBytes = fs.statSync(html).size;
    report.formalSources = formal.source;
    check('Five complete official UI themes and four real project pools', data.schemes.length === 5 && data.pools.length === 4);
    const poolAudit = data.pools.map((pool) => {
        const row = formal.pools.find((p) => p.pool_id === pool.id);
        const pity = formal.pity.find((p) => p.pool_id === pool.id && p.trigger_mode === 'batch_only');
        return { id: pool.id, name: pool.name, singleCost: pool.singleCost, tenCost: pool.tenCost, pity: pool.pity, correct: !!row && pool.name === row.display_name && pool.singleCost === Number(row.single_cost) && pool.tenCost === Number(row.ten_cost) && pool.pity === '十连保底 ' + String(pity.target_quality).toUpperCase() && pool.ticketKind === (row.ticket_content_id === 'special_lottery_ticket' ? 'special' : 'normal') };
    });
    check('Pool names, costs, ticket types and guarantees match current CSV', poolAudit.every((row) => row.correct), poolAudit);
    check('Five actual official backgrounds differ', new Set(data.schemes.map((s) => s.assets.background.sourcePath)).size === 5, data.schemes.map((s) => ({ id: s.id, sourcePath: s.assets.background.sourcePath })));
    check('Five actual official primary button assets differ', new Set(data.schemes.map((s) => s.assets.button.sourcePath)).size === 5, data.schemes.map((s) => ({ id: s.id, sourcePath: s.assets.button.sourcePath })));
    check('Five actual official treasure hero images differ', new Set(data.schemes.map((s) => s.assets.hero.sourcePath)).size === 5, data.schemes.map((s) => ({ id: s.id, sourcePath: s.assets.hero.sourcePath })));
    check('All theme asset identities and official URI are recorded', data.schemes.every((s) => Object.values(s.assets).every((a) => a.id && a.sourcePath.startsWith('panorama/images/') && /^(s2r:\/\/panorama\/images\/|file:\/\/\{images\}\/)/.test(a.uri) && /^data:image\//.test(a.preview))));

    let b;
    try {
        b = await browser();
        await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
        await b.go(html);
        check('Offline review page initialized', await b.run('Boolean(window.lotteryDemoAPI&&lotteryDemoAPI.version===1)'));
        const decode = await b.run(`(async function(){
            var images=new Set();
            function scan(v){if(typeof v==='string'){if(v.startsWith('data:image/'))images.add(v)}else if(Array.isArray(v))v.forEach(scan);else if(v&&typeof v==='object')Object.values(v).forEach(scan)}
            scan(lotteryDemoAPI.getData());var all=[...images],cursor=0,decoded=0,failed=[];
            await Promise.all(Array.from({length:16},async function(){while(cursor<all.length){var i=cursor++,img=new Image();try{img.src=all[i];await img.decode();if(!img.naturalWidth||!img.naturalHeight)throw Error('zero size');decoded++}catch(e){failed.push({index:i,error:String(e)})}finally{img.removeAttribute('src')}}}));
            return {unique:all.length,decoded:decoded,failed:failed};
        })()`);
        check('Every unique embedded official or current-project image decodes', decode.unique > 30 && decode.decoded === decode.unique && !decode.failed.length, decode);

        async function shot(name, width, height) {
            const file = path.join(out, 'browser', name + '.png');
            await b.shot(file, width, height);
            report.screenshots.push(path.relative(root, file).replaceAll('\\', '/'));
        }
        async function stageShot(name) {
            const bounds = await b.run('(function(){var r=document.getElementById("stageHost").getBoundingClientRect();return{x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height}})()');
            const result = await b.call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { ...bounds, scale: 1 } });
            const file = path.join(out, 'browser', name + '.png');
            fs.mkdirSync(path.dirname(file), { recursive: true });
            fs.writeFileSync(file, Buffer.from(result.data, 'base64'));
            report.screenshots.push(path.relative(root, file).replaceAll('\\', '/'));
            if (!report.stageScreenshots) report.stageScreenshots = [];
            report.stageScreenshots.push({ file: path.relative(root, file).replaceAll('\\', '/'), bounds });
        }
        const layoutChecks = [];
        for (const viewport of [{ width: 1920, height: 1080 }, { width: 1280, height: 720 }]) {
            await b.call('Emulation.setDeviceMetricsOverride', { ...viewport, deviceScaleFactor: 1, mobile: false });
            for (const scheme of data.schemes) {
                for (const pool of data.pools) {
                    await b.run('lotteryDemoAPI.setScheme(' + JSON.stringify(scheme.id) + ');lotteryDemoAPI.setPool(' + JSON.stringify(pool.id) + ');lotteryDemoAPI.resize()');
                    const result = await b.run(`(function(){
                        var api=lotteryDemoAPI,state=api.getState(),d=api.getData(),pool=d.pools.find(p=>p.id===state.pool),scheme=d.schemes.find(s=>s.id===state.scheme),root=document.getElementById('mainCanvas'),scene=root.querySelector('.lottery-scene'),host=document.getElementById('stageHost');
                        var expected=[['.window-header',35,45,1608,74],['.sidebar-panel',35,123,299,746],['.main-panel',334,123,1309,681],['.bottom-bar',334,804,1309,65]],geometry=expected.every(function(e){var n=root.querySelector(e[0]);return n.offsetLeft===e[1]&&n.offsetTop===e[2]&&n.offsetWidth===e[3]&&n.offsetHeight===e[4]});
                        var draw=root.querySelector('.draw-area').getBoundingClientRect(),rewards=root.querySelector('.reward-showcase').getBoundingClientRect(),wallet=root.querySelector('.wallet').getBoundingClientRect(),close=root.querySelector('.window-close').getBoundingClientRect(),hostRect=host.getBoundingClientRect(),hero=root.querySelector('.featured-hero');
                        return {scheme:state.scheme,pool:state.pool,geometry:geometry,poolLabel:root.querySelector('.banner-heading').textContent===pool.name,activePool:root.querySelectorAll('.pool-choice.active').length===1&&root.querySelector('.pool-choice.active').dataset.pool===pool.id,singleCost:root.querySelector('[data-draw="1"] .draw-cost').textContent.trim()==='× '+pool.singleCost,tenCost:root.querySelector('[data-draw="10"] .draw-cost').textContent.trim()==='× '+pool.tenCost,pity:root.querySelector('.draw-pity').textContent===pool.pity,hero:!!hero&&hero.getAttribute('src')===scheme.assets.hero.preview,heroSemantic:root.querySelector('.featured-label').textContent==='本期珍藏'&&!root.querySelector('.featured-label').textContent.includes('UR'),rewards:root.querySelectorAll('.preview-reward').length===4,drawClear:draw.left>rewards.right&&draw.bottom<=root.querySelector('.main-panel').getBoundingClientRect().bottom+1,walletRight:wallet.right<close.left&&wallet.left>root.querySelector('.window-header').getBoundingClientRect().left+900*host.clientWidth/1672,headerBalance:root.querySelector('[data-wallet-balance]').textContent===String(state.balances[state.pool]),noOverflow:document.documentElement.scrollWidth<=innerWidth+1,hostFits:hostRect.left>=0&&hostRect.right<=innerWidth+1&&hostRect.top>=0&&hostRect.bottom<=innerHeight+2,images:[...root.querySelectorAll('img')].every(i=>i.complete&&i.naturalWidth>0)};
                    })()`);
                    // Source changes can create new img elements whose data URL
                    // decode finishes one task after synchronous rendering.
                    if (!result.images) result.images = await b.run('Promise.all([...document.querySelectorAll("#mainCanvas img")].map(i=>i.decode().then(()=>true).catch(()=>false))).then(a=>a.every(Boolean))');
                    Object.assign(result, await b.run(`(function(){
                        var state=lotteryDemoAPI.getState(),scheme=lotteryDemoAPI.getData().schemes.find(s=>s.id===state.scheme),root=document.getElementById('mainCanvas');
                        function uses(node,asset){if(!asset)return true;return [node,...node.querySelectorAll('*')].some(function(n){return ['','::before','::after'].some(function(p){var style=getComputedStyle(n,p||null);return style.backgroundImage.includes(asset.preview)||style.maskImage.includes(asset.preview)})||n.tagName==='IMG'&&n.getAttribute('src')===asset.preview})}
                        return {backgroundSkin:uses(root.querySelector('.main-art'),scheme.assets.background),primarySkin:uses(root.querySelector('.draw-action.ten'),scheme.assets.button),secondarySkin:uses(root.querySelector('.draw-action.single'),scheme.assets.buttonSecondary),activePoolSkin:uses(root.querySelector('.pool-choice.active'),scheme.assets.tabSelected)};
                    })()`));
                    layoutChecks.push({ width: viewport.width, ...result });
                    check(viewport.width + 'px ' + scheme.id + ' / ' + pool.id + ' complete fixed-reference layout and correct data', Object.entries(result).filter(([key]) => !['scheme', 'pool'].includes(key)).every(([, value]) => value), result);
                    if (pool.id === data.pools[0].id) {
                        await shot(viewport.width + 'x' + viewport.height + '_' + scheme.id + '_map', viewport.width, viewport.height);
                        if (viewport.width === 1920) await stageShot(viewport.width + 'x' + viewport.height + '_' + scheme.id + '_map_stage');
                    }
                }
            }
        }
        report.layoutCases = layoutChecks.length;

        await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
        const flows = [];
        for (const scheme of data.schemes) {
            for (const pool of data.pools) {
                const flow = await b.run(`(function(){
                    var api=lotteryDemoAPI;api.setScheme(${JSON.stringify(scheme.id)});api.setPool(${JSON.stringify(pool.id)});api.reset();api.setSkipAnimation(true);var before=api.getState().balances[${JSON.stringify(pool.id)}],single=api.draw(1),a=api.getState();
                    var singleCorrect=single&&a.phase==='results'&&a.results.length===1&&a.balances[a.pool]===before-${Number(pool.singleCost)}&&document.querySelectorAll('#mainCanvas .result-item').length===1;
                    document.querySelector('[data-confirm-results]').click();var confirmed=api.getState().phase==='idle'&&!document.querySelector('[data-result-overlay]');
                    var ten=api.draw(10),b=api.getState(),tenCorrect=ten&&b.phase==='results'&&b.results.length===10&&b.balances[b.pool]===before-${Number(pool.singleCost)}-${Number(pool.tenCost)}&&document.querySelectorAll('#mainCanvas .result-item').length===10;
                    var overlay=document.querySelector('[data-result-overlay]'),full=overlay.offsetLeft===0&&overlay.offsetTop===0&&overlay.offsetWidth===1672&&overlay.offsetHeight===941;
                    document.querySelector('.result-buttons [data-draw]').click();var c=api.getState(),again=c.phase==='results'&&c.results.length===10&&c.records.length===21&&c.balances[c.pool]===before-${Number(pool.singleCost)}-${2 * Number(pool.tenCost)};
                    api.confirmResults();return {scheme:api.getState().scheme,pool:api.getState().pool,single:singleCorrect,confirmed:confirmed,ten:tenCorrect,fullCanvas:full,again:again,backToIdle:api.getState().phase==='idle'};
                })()`);
                flows.push(flow);
                check('Local draw chain ' + scheme.id + ' / ' + pool.id, Object.entries(flow).filter(([key]) => !['scheme', 'pool'].includes(key)).every(([, value]) => value), flow);
            }
        }
        report.drawFlowCases = flows.length;

        await b.run('lotteryDemoAPI.setScheme(' + JSON.stringify(data.schemes[0].id) + ');lotteryDemoAPI.setPool(' + JSON.stringify(data.pools[0].id) + ');lotteryDemoAPI.reset();lotteryDemoAPI.draw(1)');
        check('Draw enters full-canvas animation and blocks duplicate draws', await b.run('(function(){var api=lotteryDemoAPI,s=api.getState(),balance=s.balances[s.pool],duplicate=api.draw(10),overlay=document.querySelector("[data-animation-overlay]");return s.phase==="drawing"&&!!overlay&&overlay.offsetWidth===1672&&overlay.offsetHeight===941&&!duplicate&&api.getState().balances[s.pool]===balance})()'));
        await shot('1920x1080_animation', 1920, 1080);
        await sleep(1300);
        check('1150ms opening timer reveals one local reward', await b.run('lotteryDemoAPI.getState().phase==="results"&&document.querySelectorAll(".result-item").length===1'));
        await shot('1920x1080_single_result', 1920, 1080);
        await b.run('lotteryDemoAPI.confirmResults();lotteryDemoAPI.setSkipAnimation(false);lotteryDemoAPI.draw(10);document.querySelector("[data-finish-animation]").click()');
        check('Animation skip action immediately reveals all ten local rewards', await b.run('lotteryDemoAPI.getState().phase==="results"&&document.querySelectorAll(".result-item").length===10'));
        await sleep(500); // Capture after all staggered reward-reveal keyframes.
        await shot('1920x1080_ten_result', 1920, 1080);
        await b.run('lotteryDemoAPI.confirmResults();document.querySelector("[data-skip-animation]").click();lotteryDemoAPI.draw(1)');
        check('Skip animation checkbox directly shows results', await b.run('lotteryDemoAPI.getState().skipAnimation&&lotteryDemoAPI.getState().phase==="results"&&!document.querySelector("[data-animation-overlay]")'));
        await b.run('lotteryDemoAPI.confirmResults()');
        for (const kind of ['preview', 'records', 'notice']) {
            await b.run('document.querySelector(' + JSON.stringify('[data-modal="' + kind + '"]') + ').click()');
            check(kind + ' footer action opens its local modal', await b.run('lotteryDemoAPI.getState().modal===' + JSON.stringify(kind) + '&&Boolean(document.querySelector(".game-modal[role=dialog]"))'));
            if (kind === 'preview') {
                check('Preview lists all formal rewards of the active pool', await b.run('document.querySelectorAll(".pool-preview-grid .reward-image-wrap").length===lotteryDemoAPI.getData().pools.find(p=>p.id===lotteryDemoAPI.getState().pool).rewards.length'));
                await shot('1920x1080_pool_details', 1920, 1080);
            } else if (kind === 'records') {
                check('History shows the local draws from this page', await b.run('document.querySelectorAll(".record-row").length===lotteryDemoAPI.getState().records.length'));
                await shot('1920x1080_history', 1920, 1080);
            }
            await b.run('document.querySelector("[data-close-modal]").click()');
            check(kind + ' close action removes only the modal', await b.run('lotteryDemoAPI.getState().modal===null&&!document.querySelector(".game-modal-mask")&&lotteryDemoAPI.getState().phase==="idle"'));
        }
        await b.run('lotteryDemoAPI.openModal("notice")');
        await b.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
        check('Escape closes a modal', await b.run('lotteryDemoAPI.getState().modal===null'));
        await b.run('lotteryDemoAPI.openModal("notice");document.querySelector("[data-modal-mask]").click()');
        check('Click outside a modal closes it', await b.run('lotteryDemoAPI.getState().modal===null'));
        await b.run('document.querySelector(".wallet-plus").click()');
        const topupBefore = await b.run('lotteryDemoAPI.getState().balances[lotteryDemoAPI.getState().pool]');
        check('Balance plus opens clearly marked local fixture controls', await b.run('lotteryDemoAPI.getState().modal==="topup"&&document.querySelector(".game-modal-content").textContent.includes("本页演示数据")'));
        await b.run('document.querySelector(' + JSON.stringify('[data-add-tickets="100"]') + ').click()');
        check('Local plus action increases fixture balance by exactly 100', await b.run('lotteryDemoAPI.getState().balances[lotteryDemoAPI.getState().pool]') === topupBefore + 100);
        await b.run('lotteryDemoAPI.reset();lotteryDemoAPI.toggleCompare(true)');
        check('Comparison renders five complete reference canvases', await b.run('document.querySelectorAll("#compareView .stage-canvas").length===5&&document.querySelectorAll("#compareView .lottery-scene").length===5&&[...document.querySelectorAll("#compareView .lottery-scene")].every(s=>s.offsetWidth===1672&&s.offsetHeight===941&&s.querySelectorAll(".pool-choice").length===4&&s.querySelectorAll(".draw-action").length===2)'));
        const compareHeight = await b.run('document.documentElement.scrollHeight');
        await shot('1920_compare_all_five', 1920, Math.min(compareHeight, 6500));
        await b.run('document.querySelector(' + JSON.stringify('#compareView [data-scheme="' + data.schemes[2].id + '"]') + ').click()');
        check('Choosing a comparison scheme opens its interactive full view', await b.run('!lotteryDemoAPI.getState().compare&&lotteryDemoAPI.getState().scheme===' + JSON.stringify(data.schemes[2].id)));

        await b.call('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: false });
        await b.run('lotteryDemoAPI.resize()');
        check('390px review page has no horizontal overflow', await b.run('document.documentElement.scrollWidth<=innerWidth+1'));
        await shot('390x844_single', 390, 844);
        await b.run('lotteryDemoAPI.toggleCompare(true)');
        check('390px five-canvas comparison has no horizontal overflow', await b.run('document.documentElement.scrollWidth<=innerWidth+1&&document.querySelectorAll("#compareView .stage-canvas").length===5'));
        await shot('390x844_compare', 390, 844);
        const webResources = await b.run('performance.getEntriesByType("resource").map(r=>r.name).filter(u=>/^https?:/.test(u))');
        check('Review never requests any HTTP or HTTPS resource', !webResources.length, webResources);
        check('Review has no external script or stylesheet dependencies', await b.run('![...document.querySelectorAll("script[src],link[rel=stylesheet]")].some(n=>/^https?:/.test(n.src||n.href))'));
        report.success = report.checks.every((entry) => entry.passed);
    } finally { if (b) b.close(); }
    check('QA did not modify the final HTML', hash(fs.readFileSync(html)) === report.htmlSha256);
    saveReport();
    console.log(JSON.stringify({ success: report.success, checks: report.checks.length, layoutCases: report.layoutCases, drawFlowCases: report.drawFlowCases, screenshots: report.screenshots.length, report: path.relative(root, path.join(out, 'report.json')) }));
}

main().catch((error) => {
    report.success = false;
    report.error = error.stack || String(error);
    saveReport();
    console.error(report.error);
    process.exitCode = 1;
});
