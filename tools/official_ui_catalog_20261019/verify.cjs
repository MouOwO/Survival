'use strict';

// Isolated file:// browser checks. This does not start Dota, execute Panorama,
// mutate account state, or write production assets.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { browser, sleep } = require('../market_filter_20261017/browser.cjs');

const root = path.resolve(__dirname, '../..');
const catalogRoot = path.join(root, 'design_refs/official_ui_catalog_20261019');
const html = path.join(catalogRoot, '官方UI图册.html');
const manifestFile = path.join(catalogRoot, 'catalog.json');
const out = path.join(root, 'output/official_ui_catalog_20261019/qa');
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const report = {
    success: false,
    kind: 'offline-browser-only',
    nativeGameVerified: false,
    html,
    generatedAt: new Date().toISOString(),
    checks: [],
    screenshots: [],
};

function check(name, passed, details) {
    const record = { name, passed: !!passed, ...(details === undefined ? {} : { details }) };
    report.checks.push(record);
    if (!passed) throw new Error(name + ': ' + JSON.stringify(details));
}

function writeReport() {
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
}

async function main() {
    fs.mkdirSync(out, { recursive: true });
    check('Built HTML and manifest exist', fs.existsSync(html) && fs.existsSync(manifestFile));
    const htmlBytes = fs.readFileSync(html);
    const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
    report.htmlSha256 = sha(htmlBytes);
    report.htmlBytes = htmlBytes.length;
    report.previewCount = manifest.assets.length;
    report.indexedCount = manifest.index.length;
    report.componentCount = manifest.components.length;
    check('Substantial official asset and component inventory', manifest.assets.length > 1000 && manifest.index.length > manifest.assets.length && manifest.components.length >= 10, {
        previews: manifest.assets.length, indexed: manifest.index.length, components: manifest.components.length,
    });
    check('Asset and index IDs are unique', new Set(manifest.assets.map((row) => row.id)).size === manifest.assets.length && new Set(manifest.index.map((row) => row.id)).size === manifest.index.length);
    const missingOriginals = [];
    const escapedPaths = [];
    let originalBytes = 0;
    for (const item of manifest.assets) {
        const resolved = path.resolve(catalogRoot, item.original || '');
        const relative = path.relative(catalogRoot, resolved);
        if (relative.startsWith('..') || path.isAbsolute(relative)) escapedPaths.push(item.id);
        else if (!item.original || !fs.existsSync(resolved)) missingOriginals.push({ id: item.id, original: item.original });
        else originalBytes += fs.statSync(resolved).size;
    }
    check('Every exported original exists inside the catalog directory', !missingOriginals.length && !escapedPaths.length, { checked: manifest.assets.length, originalBytes, missingOriginals, escapedPaths });
    check('Official source paths and resource URI are recorded', manifest.assets.every((row) => row.sourcePath.startsWith('panorama/images/') && /^(s2r:\/\/panorama\/images\/|file:\/\/\{images\}\/)/.test(row.uri) && /^[a-f0-9]{64}$/.test(row.sourceSha256)));
    const componentSourceFile = path.join(catalogRoot, 'reference/panorama/styles/dotastyles.css');
    const officialCss = fs.readFileSync(componentSourceFile, 'utf8').replace(/\r\n/g, '\n');
    check('Component CSS snippets come from decoded official stylesheet', manifest.components.every((row) => row.officialSource.startsWith('panorama/styles/dotastyles.css:') && row.css && row.xml && row.css.split(/\n\s*\n/).every((snippet) => officialCss.includes(snippet.trim()))));

    let b;
    try {
        b = await browser();
        await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
        await b.go(html);
        check('File page initialized with browser QA API', await b.run('Boolean(window.catalogAPI && window.catalogAPI.version === 1)'));
        check('Initial view renders exactly one 60-item page', await b.run('document.querySelectorAll(".asset-card").length===60 && window.catalogAPI.getState().page===1 && window.catalogAPI.getState().filteredCount===window.catalogAPI.getData().assets.length'));
        const remoteScriptOrStyle = await b.run('[...document.querySelectorAll("script[src],link[rel=stylesheet]")].map(x=>x.src||x.href).filter(x=>/^https?:/.test(x))');
        check('No external script or stylesheet dependencies', !remoteScriptOrStyle.length, remoteScriptOrStyle);
        const resources = await b.run('performance.getEntriesByType("resource").map(x=>x.name).filter(x=>/^https?:/.test(x))');
        check('Offline initial render issues no web resource requests', !resources.length, resources);

        // All embedded previews are decoded in a 16-worker pool. Images are
        // detached and released; the gallery never creates 5,000 image nodes.
        const decode = await b.run(`(async function(){
            var all=window.catalogAPI.getData().assets,cursor=0,decoded=0,failed=[],started=performance.now();
            await Promise.all(Array.from({length:16},async function(){
                while(cursor<all.length){
                    var item=all[cursor++],img=new Image();
                    try{img.src=item.preview;await img.decode();if(!img.naturalWidth||!img.naturalHeight)throw Error('zero natural size');decoded++;}
                    catch(error){failed.push({id:item.id,path:item.sourcePath,error:String(error)})}
                    finally{img.removeAttribute('src');img=null;}
                }
            }));
            return {checked:all.length,decoded:decoded,failed:failed,milliseconds:Math.round(performance.now()-started),domImages:document.images.length};
        })()`);
        check('Every embedded official preview decodes', decode.failed.length === 0 && decode.decoded === manifest.assets.length && decode.domImages <= 60, decode);

        async function shot(name, width, height) {
            const dest = path.join(out, 'browser', name + '.png');
            await b.shot(dest, width, height);
            report.screenshots.push(path.relative(root, dest).replaceAll('\\', '/'));
        }
        async function decodeCurrent() {
            return b.run('Promise.all([...document.querySelectorAll("#catalogContent img")].map(async function(img){try{img.loading="eager";await img.decode();return !!img.naturalWidth}catch(e){return false}})).then(x=>x.every(Boolean))');
        }
        async function click(selector) {
            const rect = await b.run('(function(){var r=document.querySelector(' + JSON.stringify(selector) + ').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()');
            await b.call('Input.dispatchMouseEvent', { type: 'mousePressed', x: rect.x, y: rect.y, button: 'left', clickCount: 1 });
            await b.call('Input.dispatchMouseEvent', { type: 'mouseReleased', x: rect.x, y: rect.y, button: 'left', clickCount: 1 });
        }

        for (const viewport of [{ width: 1920, height: 1080 }, { width: 1280, height: 720 }, { width: 390, height: 844 }]) {
            const { width, height } = viewport;
            await b.call('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
            await b.run('catalogAPI.closeDetail();catalogAPI.search("");catalogAPI.setView("assets","all");');
            check(width + 'px initial page images decode', await decodeCurrent());
            check(width + 'px no horizontal page overflow', await b.run('document.documentElement.scrollWidth<=window.innerWidth+1'), await b.run('({width:innerWidth,scroll:document.documentElement.scrollWidth})'));
            check(width + 'px grid cards stay inside viewport', await b.run('[...document.querySelectorAll(".asset-card")].every(x=>{var r=x.getBoundingClientRect();return r.left>=-1&&r.right<=innerWidth+1})'));
            await shot(width + 'x' + height + '_all', width, height);
            await b.run('catalogAPI.setView("components","all")');
            check(width + 'px native components visible without horizontal overflow', await b.run('document.querySelectorAll(".component-card").length===catalogAPI.getData().components.length&&document.documentElement.scrollWidth<=innerWidth+1'));
            await shot(width + 'x' + height + '_components', width, height);
            await b.run('catalogAPI.setView("assets","all");catalogAPI.openDetail(catalogAPI.getData().assets[0].id)');
            check(width + 'px detail original image decodes', await b.run('(async function(){var i=document.getElementById("detailImage");try{await i.decode();return !!i.naturalWidth}catch(e){return false}})()'));
            check(width + 'px detail remains within viewport', await b.run('(function(){var r=document.querySelector(".dialog").getBoundingClientRect();return r.left>=0&&r.right<=innerWidth+1&&r.top>=0&&r.bottom<=innerHeight+1})()'));
            await shot(width + 'x' + height + '_detail', width, height);
            await b.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
            check(width + 'px Escape closes detail', await b.run('document.getElementById("detailOverlay").hidden && catalogAPI.getState().detailId===null'));
        }

        await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
        await b.run('catalogAPI.setView("assets","all");catalogAPI.search("")');
        const firstPage = await b.run('[...document.querySelectorAll(".asset-card")].map(x=>x.dataset.openId)');
        await click('#nextPage');
        const secondPage = await b.run('[...document.querySelectorAll(".asset-card")].map(x=>x.dataset.openId)');
        check('Next page displays a disjoint 60-item page', secondPage.length === 60 && !secondPage.some((id) => firstPage.includes(id)) && (await b.run('catalogAPI.getState().page')) === 2);
        await click('#previousPage');
        check('Previous page restores original first-page IDs', JSON.stringify(await b.run('[...document.querySelectorAll(".asset-card")].map(x=>x.dataset.openId)')) === JSON.stringify(firstPage));

        const categoryChecks = await b.run('(function(){var results=[];catalogAPI.getData().categories.filter(c=>c.count>0).forEach(function(c){catalogAPI.setView("assets",c.id);var s=catalogAPI.getState();results.push({id:c.id,count:s.filteredCount,expected:c.count,cards:document.querySelectorAll(".asset-card").length,correct:[...document.querySelectorAll(".asset-card")].every(n=>catalogAPI.getData().assets.find(a=>a.id===n.dataset.openId).category===c.id)})});return results})()');
        check('Every nonempty category filters to the declared inventory', categoryChecks.every((row) => row.correct && row.count === row.expected && row.cards === Math.min(60, row.expected)), categoryChecks);
        await b.run('catalogAPI.setView("assets","all");catalogAPI.search("按钮")');
        check('Chinese purpose-tag search returns official assets', await b.run('catalogAPI.getState().filteredCount>0&&[...document.querySelectorAll(".asset-card")].every(n=>catalogAPI.getData().assets.find(a=>a.id===n.dataset.openId).tags.join(" ").includes("按钮"))'));
        await shot('1920x1080_chinese_search', 1920, 1080);
        const sample = manifest.assets.find((row) => row.sourcePath.includes('control_icons/')) || manifest.assets[0];
        await b.run('catalogAPI.search(' + JSON.stringify(sample.sourcePath) + ')');
        check('Exact official path search finds the correct preview', await b.run('document.querySelectorAll(".asset-card").length===1&&document.querySelector(".asset-card").dataset.openId===' + JSON.stringify(sample.id)));
        await b.run('catalogAPI.search("没有此素材__qa__no_match_20261019")');
        check('Empty query result shows reset action and disabled pagination', await b.run('catalogAPI.getState().filteredCount===0&&Boolean(document.getElementById("emptyReset"))&&document.getElementById("nextPage").disabled&&document.getElementById("previousPage").disabled'));
        await click('#emptyReset');
        check('Empty-result reset restores all assets', await b.run('catalogAPI.getState().filteredCount===catalogAPI.getData().assets.length&&document.getElementById("catalogSearch").value===""'));

        await b.run('catalogAPI.openDetail(' + JSON.stringify(sample.id) + ')');
        check('Detail has exact official URI and reusable XML', await b.run('document.getElementById("assetUri").value===' + JSON.stringify(sample.uri) + '&&document.getElementById("assetXml").value.includes(' + JSON.stringify(sample.uri) + ')&&document.getElementById("openOriginal").getAttribute("href")===' + JSON.stringify(sample.original)));
        await click('[data-copy-target="assetUri"]');
        await sleep(150);
        const copyNotice = await b.run('document.getElementById("toast").textContent');
        check('Copy URI reports success or explicit manual-copy fallback', /已复制|手动复制/.test(copyNotice), copyNotice);
        await click('[data-copy-target="assetXml"]');
        await sleep(150);
        check('Copy XML reports success or explicit manual-copy fallback', await b.run('/已复制|手动复制/.test(document.getElementById("toast").textContent)'));
        await click('#detailSelect');
        check('Detail selection button adds the item', await b.run('catalogAPI.getState().selected.includes(' + JSON.stringify(sample.id) + ')&&document.getElementById("detailSelect").textContent.includes("已加入")'));
        await b.run('catalogAPI.closeDetail();catalogAPI.setView("assets","all");catalogAPI.setPage(2)');
        const page2Id = await b.run('document.querySelector(".asset-card").dataset.openId');
        await click('.asset-select');
        check('Selections survive pagination', await b.run('catalogAPI.getState().selected.includes(' + JSON.stringify(sample.id) + ')&&catalogAPI.getState().selected.includes(' + JSON.stringify(page2Id) + ')'));
        await b.go(html);
        check('Selections persist after reopening file through localStorage', await b.run('catalogAPI.getState().selected.includes(' + JSON.stringify(sample.id) + ')&&catalogAPI.getState().selected.includes(' + JSON.stringify(page2Id) + ')'));
        await b.run('catalogAPI.setView("selected","all")');
        check('Selected list displays both remembered assets', await b.run('document.querySelectorAll(".asset-card").length===2&&catalogAPI.selectedManifest().selection.length===2'));
        await shot('1920x1080_selected', 1920, 1080);
        await click('#copySelection');
        await sleep(150);
        check('Copy selected IDs reports success or manual-copy fallback', await b.run('/已复制|手动复制/.test(document.getElementById("toast").textContent)'));
        const downloadDir = path.join(out, 'downloads');
        fs.mkdirSync(downloadDir, { recursive: true });
        await b.call('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloadDir });
        await click('#exportSelection');
        const download = path.join(downloadDir, 'dota2-official-ui-selection.json');
        for (let attempt = 0; attempt < 60 && !fs.existsSync(download); attempt++) await sleep(100);
        check('Export selection downloads the actual manifest', fs.existsSync(download));
        const downloadedSelection = JSON.parse(fs.readFileSync(download, 'utf8'));
        check('Downloaded manifest preserves IDs, URI and official paths', downloadedSelection.selection.length === 2 && downloadedSelection.selection.some((item) => item.id === sample.id && item.uri === sample.uri && item.sourcePath === sample.sourcePath));

        await b.run('catalogAPI.setView("index","all");catalogAPI.search("panorama/images/control_icons/")');
        check('Complete official path index is searchable and paginated', await b.run('catalogAPI.getState().filteredCount>0&&document.querySelectorAll(".index-table tbody tr").length<=60&&[...document.querySelectorAll(".index-table .path-cell")].every(n=>n.textContent.includes("panorama/images/control_icons/"))'));
        await shot('1920x1080_index', 1920, 1080);
        const previewedIndex = manifest.index.find((row) => row.previewId === sample.id);
        await b.run('catalogAPI.search(' + JSON.stringify(previewedIndex.sourcePath) + ')');
        check('Indexed preview is labeled as available', await b.run('document.querySelector(".index-table tbody tr").textContent.includes("可预览")'));
        await click('.index-table tbody tr');
        check('An indexed resource opens the corresponding exported original', await b.run('Boolean(document.getElementById("detailImage"))&&document.getElementById("assetUri").value===' + JSON.stringify(sample.uri)));
        await b.run('catalogAPI.closeDetail()');
        const unpreviewed = manifest.index.find((row) => !row.previewed);
        await b.run('catalogAPI.search(' + JSON.stringify(unpreviewed.sourcePath) + ')');
        check('An official resource outside visual subset remains discoverable', await b.run('catalogAPI.getState().filteredCount===1&&document.querySelector(".index-table .path-cell").textContent===' + JSON.stringify(unpreviewed.sourcePath)));
        await click('.index-table tbody tr');
        check('Unpreviewed index item exposes URI and reusable XML', await b.run('document.getElementById("assetUri").value===' + JSON.stringify(unpreviewed.uri) + '&&document.getElementById("detailBody").textContent.includes("暂未导出预览")'));
        await b.run('catalogAPI.closeDetail();catalogAPI.search("");catalogAPI.setView("components","all")');

        const componentInteractions = await b.run(`(function(){
            var root=document.getElementById('catalogContent'),result={};
            var button=root.querySelector('.demo button:not(:disabled)');button.click();result.buttonFeedback=button.classList.contains('pulse');
            var checkbox=root.querySelector('.demo input[type=checkbox]'),before=checkbox.checked;checkbox.click();result.checkbox=checkbox.checked!==before;
            var radios=root.querySelectorAll('.demo input[type=radio]');radios[1].click();result.radio=radios[1].checked&&!radios[0].checked;
            var dropdown=root.querySelector('.demo select');dropdown.selectedIndex=1;dropdown.dispatchEvent(new Event('change',{bubbles:true}));result.dropdown=dropdown.selectedIndex===1;
            var text=root.querySelector('.demo input[type=text]');text.value='官方 UI 测试';text.dispatchEvent(new Event('input',{bubbles:true}));result.textEntry=text.value==='官方 UI 测试';
            var slider=root.querySelector('.demo input[type=range]');slider.value='77';slider.dispatchEvent(new Event('input',{bubbles:true}));result.slider=slider.value==='77';
            var viewports=[...root.querySelectorAll('.demo .viewport')];result.verticalScroll=false;result.horizontalScroll=false;
            viewports.forEach(function(v){if(v.scrollHeight>v.clientHeight){v.scrollTop=40;result.verticalScroll=v.scrollTop>0}if(v.scrollWidth>v.clientWidth){v.scrollLeft=40;result.horizontalScroll=v.scrollLeft>0}});
            result.disabledButtons=[...root.querySelectorAll('.demo button:disabled')].length>0;
            return result;
        })()`);
        check('Native component browser demonstrations are interactive', Object.values(componentInteractions).every(Boolean), componentInteractions);
        await click('.component-card [data-open-id]');
        check('Component detail exposes decoded official CSS and reusable XML', await b.run('document.getElementById("componentCss").value.length>100&&document.getElementById("componentXml").value.includes("ButtonBevel")'));
        await shot('1920x1080_component_code', 1920, 1080);
        await b.run('catalogAPI.closeDetail();catalogAPI.setView("selected","all")');
        await click('#clearSelection');
        check('Clear selection resets list and action availability', await b.run('catalogAPI.getState().selected.length===0&&document.querySelector(".empty-state")&&document.getElementById("copySelection").disabled&&JSON.parse(localStorage.getItem("dota2-official-ui-catalog-selection-v1")).length===0'));
        await b.run('catalogAPI.setView("assets","all");document.querySelector("[data-background=light]").click();document.getElementById("actualSize").click()');
        check('Backdrop and 1:1 toggle change actual gallery state', await b.run('document.body.dataset.bg==="light"&&document.body.classList.contains("one-to-one")&&catalogAPI.getState().actualSize'));
        await b.run('document.querySelector("[data-background=checker]").click()');
        check('Checkerboard backdrop is selectable', await b.run('document.body.dataset.bg==="checker"'));
        await shot('1920x1080_checker_actual', 1920, 1080);
        report.success = report.checks.every((row) => row.passed);
    } finally {
        if (b) b.close();
    }
    check('QA did not alter the built gallery', sha(fs.readFileSync(html)) === report.htmlSha256);
    writeReport();
    console.log(JSON.stringify({ success: report.success, checks: report.checks.length, previews: report.previewCount, indexed: report.indexedCount, screenshots: report.screenshots.length, report: path.relative(root, path.join(out, 'report.json')) }));
}

main().catch((error) => {
    report.success = false;
    report.error = error.stack || String(error);
    writeReport();
    console.error(report.error);
    process.exitCode = 1;
});
