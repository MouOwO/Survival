'use strict';

// Offline design-fixture QA only. Chrome uses a D: workspace profile through
// the existing helper. Nothing is sent to Panorama, Dota, accounts or payments.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const { browser, sleep } = require('../market_filter_20261017/browser.cjs');
const { fixture } = require('../lottery_gw2/fixture.cjs');
const root = path.resolve(__dirname, '../..');
const html = path.join(root, 'design_refs/lottery_emerald_buttons_20261019/幽林翡翠_按钮五轮优化.html');
const work = path.join(root, 'output/lottery_emerald_buttons_20261019');
const out = path.join(work, 'qa');
const hash = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const report = { success: false, kind: 'offline-design-fixture', nativeGameVerified: false, html, generatedAt: new Date().toISOString(), checks: [], screenshots: [] };
function check(name, passed, details) {
    report.checks.push({ name, passed: !!passed, ...(details === undefined ? {} : { details }) });
    if (!passed) throw new Error(name + ': ' + JSON.stringify(details));
}
function save() { fs.mkdirSync(out, { recursive: true }); fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2)); }

async function main() {
    fs.mkdirSync(out, { recursive: true });
    check('Final HTML and its fixture data exist', fs.existsSync(html) && fs.existsSync(path.join(work, 'data.json')));
    const data = JSON.parse(fs.readFileSync(path.join(work, 'data.json'), 'utf8'));
    const formal = fixture();
    report.htmlSha256 = hash(fs.readFileSync(html));
    report.htmlBytes = fs.statSync(html).size;
    report.rounds = data.schemes.map((s) => ({ id: s.id, name: s.name }));
    report.formalSources = formal.source;
    check('Five cumulative rounds and four formal pools exist', data.schemes.length === 5 && data.pools.length === 4 && data.schemes.at(-1).id === 'r5');
    check('Every round keeps the approved forest background and official buttons', data.schemes.every((s) => s.assets.background.sourcePath === data.schemes[0].assets.background.sourcePath && s.assets.hero.sourcePath === data.schemes[0].assets.hero.sourcePath && s.assets.button.id === 'UI01591' && s.assets.buttonSecondary.id === 'UI02980'));
    const poolAudit = data.pools.map((pool) => {
        const definition = formal.pools.find((row) => row.pool_id === pool.id);
        const pity = formal.pity.find((row) => row.pool_id === pool.id && row.trigger_mode === 'batch_only');
        return { id: pool.id, name: pool.name, singleCost: pool.singleCost, tenCost: pool.tenCost, pity: pool.pity, correct: !!definition && !!pity && pool.name === definition.display_name && pool.singleCost === Number(definition.single_cost) && pool.tenCost === Number(definition.ten_cost) && pool.pity === '十连保底 ' + pity.target_quality.toUpperCase() && pool.ticketKind === (definition.ticket_content_id === 'special_lottery_ticket' ? 'special' : 'normal') };
    });
    check('Names, fees, guarantee and normal/gold ticket types match CSV', poolAudit.every((row) => row.correct), poolAudit);

    let b;
    try {
        b = await browser();
        await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
        await b.go(html);
        check('Default view is final R5 with both fixture APIs', await b.run('Boolean(window.emeraldReviewAPI&&window.lotteryDemoAPI)&&lotteryDemoAPI.getState().scheme==="r5"'));
        const decode = await b.run(`(async function(){
            var set=new Set();function collect(v){if(typeof v==='string'&&v.startsWith('data:image/'))set.add(v);else if(Array.isArray(v))v.forEach(collect);else if(v&&typeof v==='object')Object.values(v).forEach(collect)}collect(lotteryDemoAPI.getData());var all=[...set],cursor=0,count=0,failed=[];
            await Promise.all(Array.from({length:16},async function(){while(cursor<all.length){var i=cursor++,img=new Image();try{img.src=all[i];await img.decode();if(!img.naturalWidth)throw Error('zero size');count++}catch(e){failed.push({index:i,error:String(e)})}finally{img.removeAttribute('src')}}}));return {unique:all.length,decoded:count,failed:failed};
        })()`);
        check('All embedded official and formal-item images decode', decode.unique > 20 && decode.unique === decode.decoded && !decode.failed.length, decode);
        async function screenshot(name, clip) {
            const result = await b.call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip });
            const file = path.join(out, 'browser', name + '.png');
            fs.mkdirSync(path.dirname(file), { recursive: true });
            fs.writeFileSync(file, Buffer.from(result.data, 'base64'));
            report.screenshots.push(path.relative(root, file).replaceAll('\\', '/'));
            return file;
        }
        async function capture(name, width, height, stageOnly) {
            await sleep(180);
            const clip = stageOnly ? await b.run('(function(){var r=document.getElementById("stageHost").getBoundingClientRect();return{x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height,scale:1}})()') : { x: 0, y: 0, width, height, scale: 1 };
            return screenshot(name, clip);
        }
        async function captureButtons(name) {
            await sleep(180);
            const clip = await b.run('(function(){var a=document.querySelector("#mainCanvas .draw-action.single").getBoundingClientRect(),b=document.querySelector("#mainCanvas .draw-action.ten").getBoundingClientRect(),x=Math.min(a.x,b.x)-16,y=Math.min(a.y,b.y)-42;return{x:x+scrollX,y:y+scrollY,width:Math.max(a.right,b.right)-x+16,height:Math.max(a.bottom,b.bottom)-y+16,scale:2}})()');
            return screenshot(name, clip);
        }
        async function click(selector) {
            const point = await b.run('(function(){var e=document.querySelector(' + JSON.stringify(selector) + ');e.scrollIntoView({block:"nearest"});var r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()');
            await b.call('Input.dispatchMouseEvent', { type: 'mousePressed', ...point, button: 'left', clickCount: 1 });
            await b.call('Input.dispatchMouseEvent', { type: 'mouseReleased', ...point, button: 'left', clickCount: 1 });
        }
        const layouts = [];
        for (const viewport of [{ width: 1920, height: 1080 }, { width: 1280, height: 720 }]) {
            await b.call('Emulation.setDeviceMetricsOverride', { ...viewport, deviceScaleFactor: 1, mobile: false });
            for (const round of data.schemes) {
                for (const pool of data.pools) {
                    await b.run('emeraldReviewAPI.setButtonState("normal");lotteryDemoAPI.setScheme(' + JSON.stringify(round.id) + ');lotteryDemoAPI.setPool(' + JSON.stringify(pool.id) + ');lotteryDemoAPI.resize()');
                    const result = await b.run(`(function(){
                        var api=lotteryDemoAPI,state=api.getState(),pool=api.getData().pools.find(p=>p.id===state.pool),root=document.getElementById('mainCanvas'),single=root.querySelector('.draw-action.single'),ten=root.querySelector('.draw-action.ten'),a=single.getBoundingClientRect(),b=ten.getBoundingClientRect(),rewards=root.querySelector('.reward-showcase').getBoundingClientRect(),host=document.getElementById('stageHost').getBoundingClientRect();
                        var positions=[['.window-header',35,45,1608,74],['.sidebar-panel',35,123,299,746],['.main-panel',334,123,1309,681],['.bottom-bar',334,804,1309,65]];
                        return {round:state.scheme,pool:state.pool,referenceGeometry:positions.every(function(p){var e=root.querySelector(p[0]);return e.offsetLeft===p[1]&&e.offsetTop===p[2]&&e.offsetWidth===p[3]&&e.offsetHeight===p[4]}),buttonSizes:single.offsetWidth===220&&ten.offsetWidth===244&&single.offsetHeight===84&&ten.offsetHeight===84,aligned:Math.abs(a.bottom-b.bottom)<1&&a.right<b.left,clearOfRewards:a.left>rewards.right,noOverflow:document.documentElement.scrollWidth<=innerWidth+1,stageVisible:host.left>=0&&host.right<=innerWidth+1&&host.top>=0&&host.bottom<=innerHeight+2,poolLabel:root.querySelector('.banner-heading').textContent===pool.name,activePool:root.querySelector('.pool-choice.active').dataset.pool===state.pool,costs:single.querySelector('.draw-cost').textContent.trim()==='× '+pool.singleCost&&ten.querySelector('.draw-cost').textContent.trim()==='× '+pool.tenCost,pity:ten.querySelector('.draw-pity').textContent===pool.pity,contentInside:[single,ten].every(function(e){var r=e.getBoundingClientRect();return [...e.querySelectorAll('.draw-label,.draw-cost')].every(function(c){var q=c.getBoundingClientRect();return q.left>=r.left&&q.right<=r.right&&q.top>=r.top&&q.bottom<=r.bottom})})};
                    })()`);
                    layouts.push({ width: viewport.width, ...result });
                    check(viewport.width + 'px ' + round.id + ' / ' + pool.id + ' geometry, costs and button alignment', Object.entries(result).filter(([key]) => !['round', 'pool'].includes(key)).every(([, value]) => value), result);
                    if (pool.id === data.pools[0].id) {
                        await capture(viewport.width + 'x' + viewport.height + '_' + round.id + '_stage', viewport.width, viewport.height, true);
                        if (viewport.width === 1920) await captureButtons(round.id + '_buttons');
                    }
                }
            }
        }
        report.layoutCases = layouts.length;
        await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
        await b.run('lotteryDemoAPI.setScheme("r5");lotteryDemoAPI.setPool(' + JSON.stringify(data.pools[0].id) + ');emeraldReviewAPI.setButtonState("normal");lotteryDemoAPI.reset()');
        const finalTokens = await b.run(`(function(){
            var r=document.getElementById('mainCanvas'),single=r.querySelector('.draw-action.single'),ten=r.querySelector('.draw-action.ten'),label=getComputedStyle(ten.querySelector('.draw-label')),fee=getComputedStyle(ten.querySelector('.draw-cost')),ticket=getComputedStyle(ten.querySelector('.draw-cost img')),close=r.querySelector('.window-close'),plus=r.querySelector('.wallet-plus');
            return {single:[single.offsetWidth,single.offsetHeight],ten:[ten.offsetWidth,ten.offsetHeight],title:[label.fontSize,label.lineHeight],fee:[fee.fontSize,fee.lineHeight],ticket:[ticket.width,ticket.height],close:[close.offsetWidth,close.offsetHeight],plus:[plus.offsetWidth,plus.offsetHeight],footer:[...r.querySelectorAll('.footer-action')].map(e=>e.offsetHeight)};
        })()`);
        check('R5 final typography, ticket and 44px small-button tokens', JSON.stringify(finalTokens) === JSON.stringify({ single: [220, 84], ten: [244, 84], title: ['28px', '32px'], fee: ['18px', '26px'], ticket: ['52px', '36px'], close: [44, 44], plus: [44, 44], footer: [44, 44, 44] }), finalTokens);
        const states = [];
        for (const name of ['normal', 'hover', 'pressed', 'focus', 'disabled', 'busy']) {
            await b.run('emeraldReviewAPI.setButtonState(' + JSON.stringify(name) + ')');
            await sleep(200);
            const visual = await b.run(`(function(){var e=document.querySelector('#mainCanvas .draw-action.ten'),s=getComputedStyle(e),p=getComputedStyle(e,'::before'),a=lotteryDemoAPI.getState();return {state:emeraldReviewAPI.getButtonState(),classes:e.className,disabled:e.disabled,busy:e.getAttribute('aria-busy'),label:e.querySelector('.draw-label').textContent,border:s.borderColor,shadow:s.boxShadow,outline:s.outline,outlineOffset:s.outlineOffset,transform:s.transform,surface:p.filter,opacity:s.opacity,balance:a.balances[a.pool],records:a.records.length}})()`);
            states.push(visual);
            check('R5 ' + name + ' preview class is applied', name === 'normal' || visual.classes.includes('preview-' + name), visual);
            if (name === 'disabled' || name === 'busy') {
                check('R5 ' + name + ' prevents activation and has correct label', visual.disabled && (name === 'busy' ? visual.busy === 'true' && visual.label.includes('开启中') : visual.label.includes('不足')), visual);
                await b.run('document.querySelector("#mainCanvas .draw-action.ten").click()');
                check('R5 ' + name + ' click does not consume local tickets', await b.run('(function(){var s=lotteryDemoAPI.getState();return s.balances[s.pool]===' + visual.balance + '&&s.records.length===' + visual.records + '})()'));
            } else check('R5 ' + name + ' button remains usable', !visual.disabled, visual);
            await captureButtons('r5_state_' + name + '_buttons');
        }
        report.buttonStates = states;
        const normal = states[0];
        check('Hover, pressed and focus each have an actual visible style difference', states.slice(1, 4).every((s) => ['border', 'shadow', 'outline', 'outlineOffset', 'transform', 'surface'].some((key) => s[key] !== normal[key])));

        const flows = [];
        for (const pool of data.pools) {
            await b.run('emeraldReviewAPI.setButtonState("normal");lotteryDemoAPI.setPool(' + JSON.stringify(pool.id) + ');lotteryDemoAPI.reset();lotteryDemoAPI.setSkipAnimation(true)');
            const flow = await b.run(`(function(){
                var api=lotteryDemoAPI,before=api.getState().balances[${JSON.stringify(pool.id)}];document.querySelector('#mainCanvas .draw-action.single').click();var a=api.getState(),single=a.phase==='results'&&a.results.length===1&&a.balances[a.pool]===before-${Number(pool.singleCost)};
                document.querySelector('[data-confirm-results]').click();var confirm=api.getState().phase==='idle';document.querySelector('#mainCanvas .draw-action.ten').click();var b=api.getState(),ten=b.phase==='results'&&b.results.length===10&&b.balances[b.pool]===before-${Number(pool.singleCost)}-${Number(pool.tenCost)};
                document.querySelector('.result-buttons [data-draw]').click();var c=api.getState(),again=c.phase==='results'&&c.results.length===10&&c.records.length===21&&c.balances[c.pool]===before-${Number(pool.singleCost)}-${2 * Number(pool.tenCost)};api.confirmResults();return {pool:api.getState().pool,single:single,confirm:confirm,ten:ten,again:again,idle:api.getState().phase==='idle'};
            })()`);
            flows.push(flow);
            check('R5 local single/confirm/ten/again chain ' + pool.id, Object.entries(flow).filter(([key]) => key !== 'pool').every(([, value]) => value), flow);
        }
        report.drawFlowCases = flows.length;
        await b.run('lotteryDemoAPI.setPool(' + JSON.stringify(data.pools[0].id) + ');lotteryDemoAPI.reset();lotteryDemoAPI.draw(1)');
        check('Normal draw enters animation and blocks a duplicate request', await b.run('(function(){var a=lotteryDemoAPI.getState(),balance=a.balances[a.pool],duplicate=lotteryDemoAPI.draw(10);return a.phase==="drawing"&&!duplicate&&balance===lotteryDemoAPI.getState().balances[a.pool]})()'));
        await sleep(1300);
        check('Opening animation completes after its local timer', await b.run('lotteryDemoAPI.getState().phase==="results"&&document.querySelectorAll("#mainCanvas .result-item").length===1'));
        await capture('r5_single_result', 1920, 1080, true);
        await b.run('lotteryDemoAPI.confirmResults();lotteryDemoAPI.draw(10);document.querySelector("[data-finish-animation]").click()');
        check('Animation skip reveals all ten rewards', await b.run('lotteryDemoAPI.getState().phase==="results"&&document.querySelectorAll("#mainCanvas .result-item").length===10'));
        await sleep(500);
        await capture('r5_ten_result', 1920, 1080, true);
        await b.run('lotteryDemoAPI.confirmResults()');
        for (const modal of ['preview', 'records', 'notice', 'topup']) {
            await click(modal === 'topup' ? '#mainCanvas .wallet-plus' : '#mainCanvas [data-modal="' + modal + '"]');
            check('R5 ' + modal + ' action opens the local popup', await b.run('lotteryDemoAPI.getState().modal===' + JSON.stringify(modal) + '&&Boolean(document.querySelector(".game-modal"))'));
            check('R5 ' + modal + ' popup receives keyboard focus', await b.run('document.querySelector(".game-modal").contains(document.activeElement)'));
            await b.run('document.querySelector(".game-modal button:not(:disabled)").focus()');
            await b.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, modifiers: 8 });
            await b.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, modifiers: 0 });
            check('R5 ' + modal + ' Shift+Tab stays in popup and wraps to last control', await b.run('(function(){var a=[...document.querySelectorAll(".game-modal button:not(:disabled),.game-modal input:not(:disabled),.game-modal [tabindex]")].filter(e=>e.tabIndex===0&&e.getClientRects().length);return document.activeElement===a[a.length-1]})()'));
            await b.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, modifiers: 0 });
            await b.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, modifiers: 0 });
            check('R5 ' + modal + ' Tab stays in popup and wraps to first control', await b.run('document.activeElement===document.querySelector(".game-modal button:not(:disabled)")'));
            if (modal === 'preview' || modal === 'records') await capture('r5_' + modal, 1920, 1080, true);
            await click('[data-close-modal]');
            check('R5 ' + modal + ' close preserves the idle scene', await b.run('lotteryDemoAPI.getState().modal===null&&lotteryDemoAPI.getState().phase==="idle"&&!document.querySelector(".game-modal-mask")'));
            check('R5 ' + modal + ' close restores focus to its opener', await b.run('document.activeElement.getAttribute("data-modal")===' + JSON.stringify(modal)));
        }
        await b.run('lotteryDemoAPI.openModal("notice")');
        await b.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
        check('Escape closes a local popup', await b.run('lotteryDemoAPI.getState().modal===null'));
        await b.run('lotteryDemoAPI.openModal("notice");document.querySelector("[data-modal-mask]").click()');
        check('Clicking the modal backdrop closes it', await b.run('lotteryDemoAPI.getState().modal===null'));
        await b.run('lotteryDemoAPI.reset();lotteryDemoAPI.setSkipAnimation(true);document.querySelector("#mainCanvas .draw-action.single").focus()');
        await b.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, text: '\r', unmodifiedText: '\r' });
        await b.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
        check('Keyboard Enter activates a focused normal draw button', await b.run('lotteryDemoAPI.getState().phase==="results"&&lotteryDemoAPI.getState().results.length===1'));
        await b.run('lotteryDemoAPI.confirmResults();lotteryDemoAPI.reset();lotteryDemoAPI.toggleCompare(true)');
        check('Comparison contains five complete reference canvases', await b.run('document.querySelectorAll("#compareView .lottery-scene").length===5&&[...document.querySelectorAll("#compareView .lottery-scene")].every(e=>e.offsetWidth===1672&&e.offsetHeight===941)'));
        await capture('1920_rounds_comparison', 1920, Math.min(await b.run('document.documentElement.scrollHeight'), 6500), false);
        await b.call('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: false });
        await b.run('lotteryDemoAPI.toggleCompare(false);lotteryDemoAPI.setScheme("r5");lotteryDemoAPI.resize()');
        check('390px final preview has no horizontal page overflow', await b.run('document.documentElement.scrollWidth<=innerWidth+1'));
        await capture('390x844_r5', 390, 844, false);
        const network = await b.run('performance.getEntriesByType("resource").map(e=>e.name).filter(u=>/^https?:/.test(u))');
        check('No HTTP or HTTPS resource request occurred', !network.length, network);
        check('Final HTML stayed unchanged during QA', hash(fs.readFileSync(html)) === report.htmlSha256);
    } finally { if (b) b.close(); }

    const python = path.join(process.env.LOCALAPPDATA || '', 'Programs/Python/Python314/python.exe');
    const montage = String.raw`from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import sys
base=Path(sys.argv[1]); rows=[]
labels=['R1  尺寸与官方原图比例','R2  文字与费用层次','R3  翡翠层次与克制高光','R4  悬停、按下与可用状态','R5  统一小按钮与完整交互']
fontfile=Path('C:/Windows/Fonts/msyh.ttc')
font=ImageFont.truetype(str(fontfile),24); small=ImageFont.truetype(str(fontfile),17)
for i,label in enumerate(labels,1):
    shot=Image.open(base/'browser'/('r%d_buttons.png'%i)).convert('RGB')
    rows.append((label,shot))
width=max(1040,max(s.width for _,s in rows)+64); height=112+sum(s.height+70 for _,s in rows)+25
canvas=Image.new('RGB',(width,height),'#111b17'); draw=ImageDraw.Draw(canvas)
draw.text((32,23),'幽林翡翠 · 五轮按钮对比',font=font,fill='#e9ead8')
draw.text((32,63),'同一官方素材与奖池 · 正常状态 · 截图保持比例',font=small,fill='#9dac9f')
y=112
for label,shot in rows:
    draw.line((32,y-8,width-32,y-8),fill='#34493b',width=1)
    draw.text((32,y+3),label,font=small,fill='#c1d3b3'); y+=42
    canvas.paste(shot,((width-shot.width)//2,y)); y+=shot.height+28
canvas.save(base/'五轮按钮对比.jpg',quality=94,subsampling=0,optimize=True)
`;
    const composite = cp.spawnSync(python, ['-c', montage, out], { windowsHide: true, encoding: 'utf8' });
    check('Five-round comparison JPEG is generated from QA screenshots only', composite.status === 0 && fs.existsSync(path.join(out, '五轮按钮对比.jpg')), { status: composite.status, stderr: composite.stderr || '' });
    report.comparison = path.relative(root, path.join(out, '五轮按钮对比.jpg')).replaceAll('\\', '/');
    report.success = report.checks.every((entry) => entry.passed);
    save();
    console.log(JSON.stringify({ success: report.success, checks: report.checks.length, layouts: report.layoutCases, flows: report.drawFlowCases, screenshots: report.screenshots.length, report: path.relative(root, path.join(out, 'report.json')) }));
}

main().catch((error) => { report.success = false; report.error = error.stack || String(error); save(); console.error(report.error); process.exitCode = 1; });
