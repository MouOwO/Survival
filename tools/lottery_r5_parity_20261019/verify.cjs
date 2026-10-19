'use strict';

// Browser measurement of the actual production XML/JS/CSS, never a game test.
// No account, payment, real ticket or server connection is used by this tool.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const assert = require('node:assert/strict'), cp = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { browser, sleep } = require('../lottery_emerald_game_20261019/browser.cjs');
const { captureReference } = require('./reference.cjs');
const repo = path.resolve(__dirname, '../..'), out = path.join(repo, 'output/lottery_r5_parity_20261019');
const productionOut = path.join(out, 'production'), preview = path.join(productionOut, 'preview');
const captures = path.join(out, 'captures');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const relative = file => path.relative(repo, file).replaceAll('\\', '/');
const normalizedHash = file => hash(Buffer.from(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')));

// Browser transport only: preserve nested rgba() colors in authored Panorama
// linear gradients. The older reusable regex parser discarded those stops.
function panoramaLinearGradient(value) {
    const match = /^gradient\(linear,\s*([\d.]+)% ([\d.]+)%,\s*([\d.]+)% ([\d.]+)%,\s*([\s\S]+)\)$/.exec(String(value));
    if (!match) return value;
    function split(text) {
        const rows = []; let depth = 0, start = 0;
        for (let i = 0; i < text.length; i++) { const c = text[i]; if (c === '(') depth++; else if (c === ')') depth--; else if (c === ',' && depth === 0) { rows.push(text.slice(start, i).trim()); start = i + 1; } }
        rows.push(text.slice(start).trim()); return rows;
    }
    const angle = Math.atan2(Number(match[3]) - Number(match[1]), Number(match[2]) - Number(match[4])) * 180 / Math.PI;
    const stops = split(match[5]).map(stop => {
        const parts = /^(from|to|color-stop)\(([\s\S]*)\)$/.exec(stop);
        if (!parts) throw Error('Unsupported authored gradient stop: ' + stop);
        if (parts[1] === 'color-stop') { const args = split(parts[2]); return args.slice(1).join(',') + ' ' + Number(args[0]) * 100 + '%'; }
        return parts[2] + (parts[1] === 'from' ? ' 0%' : ' 100%');
    });
    return 'linear-gradient(' + angle + 'deg,' + stops.join(',') + ')';
}

function exportNative() {
    const { open } = require('../vpk_inspect.cjs');
    const vpk = open(path.resolve(repo, '../../dota/pak01_dir.vpk'));
    const sources = ['scripts/custom_game/lottery_gw2.js', 'styles/custom_game/lottery_gw2.css'].map(file => fs.readFileSync(path.join(repo, 'panorama/src', file), 'utf8')).join('\n');
    const uris = [...new Set([...sources.matchAll(/(?:file:\/\/\{images\}\/|s2r:\/\/panorama\/images\/)[^"'\s)]+?\.(?:png|svg|vtex)/g)].map(match => match[0]))].filter(uri => !uri.includes('/custom_game/'));
    const directory = path.join(productionOut, 'native_assets'), records = [], aliases = {};
    const viewer = process.env.SOURCE2VIEWER_CLI || path.join(repo, 'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
    fs.mkdirSync(directory, { recursive: true });
    for (const uri of uris) {
        const rel = uri.replace(/^file:\/\/\{images\}\//, '').replace(/^s2r:\/\/panorama\/images\//, '');
        const candidates = uri.startsWith('s2r:') ? ['panorama/images/' + rel + '_c'] : rel.endsWith('.svg') ? ['panorama/images/' + rel.replace(/\.svg$/, '.vsvg_c')] : ['panorama/images/' + rel.replace(/\.png$/, '_png.vtex_c'), 'panorama/images/' + rel + '.vtex_c'];
        const entry = candidates.map(candidate => vpk.entries.find(row => row.path === candidate)).find(Boolean);
        assert(entry, 'Installed official resource exists: ' + uri);
        const bytes = vpk.read(entry), digest = hash(bytes), svg = entry.path.endsWith('.vsvg_c');
        const name = path.basename(rel).replace(/\.[^.]+$/, '') + '_' + digest.slice(0, 12);
        const input = path.join(directory, name + path.extname(entry.path)), output = path.join(directory, name + (svg ? '.svg' : '.png'));
        // Every alias is regenerated from the current installed VPK. No earlier
        // QA manifest or output data is treated as an authoritative input.
        fs.writeFileSync(input, bytes);
        if (svg) {
            const start = bytes.indexOf('<svg'), end = bytes.indexOf('</svg>', start);
            assert(start >= 0 && end > start, 'Installed SVG payload: ' + uri);
            fs.writeFileSync(output, bytes.subarray(start, end + 6));
        } else {
            assert(fs.existsSync(viewer), 'Set SOURCE2VIEWER_CLI to the installed Source2Viewer CLI');
            cp.execFileSync(viewer, ['-i', input, '-o', output, '-d'], { windowsHide: true, stdio: 'pipe', env: process.env });
        }
        const alias = rel.startsWith('masks/') ? 'data:image/' + (svg ? 'svg+xml' : 'png') + ';base64,' + fs.readFileSync(output).toString('base64') : pathToFileURL(output).href;
        aliases[uri] = alias; aliases[rel] = alias;
        if (rel.endsWith('.png')) aliases['s2r://panorama/images/' + rel.replace(/\.png$/, '_png.vtex')] = alias;
        records.push({ uri, resource: entry.path, sourceSha256: digest, previewPath: relative(output), previewSha256: hash(fs.readFileSync(output)), method: svg ? 'Exact installed VSVG payload' : 'Installed VTEX decoded without editing' });
    }
    const manifest = { kind: 'exact_installed_valve_assets_browser_aliases', notGameCapture: true, records, aliases };
    fs.writeFileSync(path.join(directory, 'manifest.json'), JSON.stringify(manifest, null, 2));
    return manifest;
}

function assembleProduction(native) {
    const file = path.join(repo, 'tools/lottery_emerald_game_20261019/preview.cjs');
    const original = fs.readFileSync(file, 'utf8');
    let adapted = original.replaceAll('output/lottery_emerald_game_20261019/qa', 'output/lottery_r5_parity_20261019/production');
    assert.notEqual(original, adapted, 'Existing preview output is redirected into this task folder');
    // The generic builder normally imports historical native alias manifests.
    // Disable just that optional input in an in-memory copy; this acceptance
    // supplies its own newly decoded installed-VPK aliases instead.
    const genericFile = path.join(repo, 'tools/menus_v10/preview.cjs'), generic = fs.readFileSync(genericFile, 'utf8');
    const genericAdapted = generic.replace(/^const nativeTextureAliasManifests=.*$/m, 'const nativeTextureAliasManifests=[];').replace(/^function gradient\(value\)\{.*$/m, 'const gradient=' + panoramaLinearGradient.toString() + ';');
    assert.notEqual(genericAdapted, generic, 'Historical alias-manifest declaration is located');
    const genericRunner = 'const Module=require("node:module"),file=' + JSON.stringify(genericFile) + ';process.argv=[process.execPath,file,"--out",' + JSON.stringify(preview) + '];const m=new Module(file,module);m.filename=file;m.paths=Module._nodeModulePaths(require("node:path").dirname(file));m._compile(' + JSON.stringify(genericAdapted) + ',file);';
    const genericRunnerFile = path.join(productionOut, 'generic_builder_runner.cjs');
    fs.writeFileSync(genericRunnerFile, genericRunner);
    const childArgs = "['tools/menus_v10/preview.cjs','--out',out]";
    assert(adapted.includes(childArgs), 'Reusable generic builder invocation remains known');
    adapted = adapted.replace(childArgs, '[' + JSON.stringify(genericRunnerFile) + ']');
    const runner = 'const Module=require("node:module"),file=' + JSON.stringify(file) + ';const m=new Module(file,module);m.filename=file;m.paths=Module._nodeModulePaths(require("node:path").dirname(file));m._compile(' + JSON.stringify(adapted) + ',file);';
    const runnerFile = path.join(productionOut, 'production_builder_runner.cjs');
    fs.writeFileSync(runnerFile, runner);
    const run = cp.spawnSync(process.execPath, [runnerFile], { cwd: repo, encoding: 'utf8', windowsHide: true, env: process.env });
    if (run.stdout) process.stdout.write(run.stdout);
    assert.equal(run.status, 0, run.error?.stack || run.stderr || 'Actual production preview assembly failed');
    const entry = path.join(preview, 'index.html'), stylePath = path.join(preview, 'style.css');
    const adapterTag = '<script src="' + pathToFileURL(path.join(repo, 'tools/archive_v10/adapter.js')).href + '"></script>';
    let html = fs.readFileSync(entry, 'utf8'); assert(html.includes(adapterTag), 'Actual adapter loads before the transport patch');
    html = html.replace(adapterTag, adapterTag + '<script>gradient=' + panoramaLinearGradient.toString() + ';</script>');
    fs.writeFileSync(entry, html);
    let css = fs.readFileSync(stylePath, 'utf8');
    for (const record of native.records) {
        const rel = record.uri.replace(/^file:\/\/\{images\}\//, '').replace(/^s2r:\/\/panorama\/images\//, '');
        const wrong = pathToFileURL(path.join(repo, 'panorama/src/images', rel)).href;
        css = css.replaceAll(wrong, native.aliases[record.uri]).replaceAll(record.uri, native.aliases[record.uri]);
    }
    fs.writeFileSync(stylePath, css);
    const assembly = JSON.parse(fs.readFileSync(path.join(preview, 'assembly.json'), 'utf8'));
    assembly.parityBuilder = { path: relative(file), sha256: hash(Buffer.from(original)), genericBuilder: relative(genericFile), genericSha256: hash(Buffer.from(generic)), substitution: 'Output is redirected, optional historical aliases are disabled, and nested rgba linear-gradient transport uses balanced parentheses. All are offline in-memory changes; production scripts, styles and layout are unchanged.', rgbaGradientTransportSha256: hash(Buffer.from(panoramaLinearGradient.toString())) };
    fs.writeFileSync(path.join(preview, 'assembly.json'), JSON.stringify(assembly, null, 2));
    return { assembly, entry };
}

function checkFrozen(assembly) {
    const drift = assembly.sourceGraph.filter(row => normalizedHash(path.join(repo, 'panorama/src', row.path)) !== row.sha256).map(row => row.path);
    assert.deepEqual(drift, [], 'Production dependencies remain unchanged during acceptance');
}

function inspectProduction() {
    const round = n => Math.round(n * 10000) / 10000;
    const canvas = nodes.LotteryMainCanvas, origin = canvas.el.getBoundingClientRect(), scale = origin.width / 1672;
    function visible(panel) { for (let p = panel; p; p = p.GetParent()) { const s = getComputedStyle(p.el); if (!p.visible || s.display === 'none' || s.visibility === 'hidden') return false; } return !!panel && panel.el.getBoundingClientRect().width > 0; }
    function box(rect) { return { x: round((rect.x - origin.x) / scale), y: round((rect.y - origin.y) / scale), width: round(rect.width / scale), height: round(rect.height / scale), right: round((rect.right - origin.x) / scale), bottom: round((rect.bottom - origin.y) / scale) }; }
    function record(panel) {
        if (!panel) return null;
        const rect = panel.el.getBoundingClientRect(), s = getComputedStyle(panel.el);
        const images = [...(panel.el.tagName === 'IMG' ? [panel.el] : []), ...panel.el.querySelectorAll('img')].map(image => ({ src: image.currentSrc || image.src, decoded: image.complete && image.naturalWidth > 0, box: box(image.getBoundingClientRect()) }));
        return { id: panel.id, type: panel.paneltype, classes: panel.GetClasses(), text: String(panel.text || panel.el.textContent || '').replace(/\s+/g, ' ').trim(), box: box(rect), screenBox: rect.toJSON(), visible: visible(panel), enabled: panel.enabled, images, style: { fontSize: s.fontSize, fontFamily: s.fontFamily, fontWeight: s.fontWeight, lineHeight: s.lineHeight, letterSpacing: s.letterSpacing, color: s.color, background: s.backgroundColor, backgroundImage: s.backgroundImage, borderColor: s.borderTopColor, borderWidth: s.borderTopWidth, boxShadow: s.boxShadow, filter: s.filter, opacity: s.opacity, zIndex: s.zIndex, opacityMaskInput: panel.style.opacityMask || null, maskImage: s.maskImage, maskSize: s.maskSize, textAlign: s.textAlign, textDecoration: s.textDecorationLine, textOverflow: panel.style.textOverflow || s.textOverflow, transform: s.transform } };
    }
    function find(panel, cls) { if (!panel) return null; if (panel.BHasClass(cls)) return panel; for (const child of panel.Children()) { const found = find(child, cls); if (found) return found; } return null; }
    const nav = ['map', 'cultivation', 'dragon_knight', 'summer'].map(id => {
        const button = nodes['LotteryGW2Pool_' + id];
        const icon = find(button, 'LotteryGW2PoolIcon') || button?.Children().find(p => p.BHasClass('LotteryGW2NativeArt') || p.paneltype === 'Image');
        return { id, button: record(button), icon: record(icon), title: record(find(button, 'LotteryGW2PoolTitle')), subtitle: record(find(button, 'LotteryGW2PoolSubtitle') || find(button, 'LotteryGW2PoolTicket')), lock: record(find(button, 'LotteryGW2PoolLock')) };
    });
    function draw(kind) {
        const button = nodes['Lottery' + kind + 'Button'];
        return { button: record(button), title: record(nodes['Lottery' + kind + 'Text']), cost: record(nodes['Lottery' + kind + 'Cost']), ticket: record(find(button, 'LHDrawTicket')), content: record(find(button, 'ZXDrawContent')), costRow: record(find(button, 'ZXDrawCost')), surface: record(find(button, 'LotteryGW2ButtonSurface')), focus: record(find(button, 'LotteryGW2DrawFocus')) };
    }
    const preview = nodes.LotteryGW2PreviewItems.Children().map(card => {
        const name = find(card, 'LotteryGW2PreviewNameHost'), expected = $.CreatePanel('Panel', nodes.LotteryGW2Root, '');
        cfg.SurvivalItemResources.ApplyBackground(expected, card.__lotteryItem);
        const sharedBackground = getComputedStyle(expected.el).backgroundImage; expected.DeleteAsync(0);
        return { card: record(card), item: card.__lotteryItem, frame: record(find(card, 'LotteryGW2PreviewWell')), icon: record(find(card, 'LotteryGW2PreviewIcon')), name: record(name), caption: record(name?.Children().find(child => child.paneltype === 'Label')), rarity: record(find(card, 'LotteryGW2PreviewRarity')), sharedBackground };
    });
    const ids = ['LotteryGW2HeaderSkin', 'LotteryGW2SidebarSkin', 'LotteryGW2SidebarTexture', 'LotteryGW2SidebarHeading', 'LotteryGW2SidebarNote', 'LotteryGW2SidebarEmblem', 'LotteryGW2FooterSkin', 'LotteryGW2Content', 'LotteryTitle', 'LotteryTagline', 'LotteryGuaranteeValue', 'LHGuaranteeQuality', 'LotteryGW2ForestDivider', 'LotteryGW2Preview', 'LotteryGW2PreviewItems', 'LotteryGW2PreviewCaption', 'LotteryDrawPity', 'LotteryDrawPityCaption', 'LotterySkipAnimation', 'LotteryGW2TicketCurrency', 'LotteryGW2TicketIcon', 'LotteryGW2TicketBalance', 'LotteryTicketPurchase', 'LotteryGW2PurchasePlus', 'LotteryCloseButton', 'LotteryGW2CloseIcon', 'LotteryGW2SceneWash', 'LotteryGW2FloorWash'];
    const active = nodes['LotteryScenePage_' + cfg.SurvivalPurpleLottery.Inspect().selected];
    return { errors: previewErrors, scriptFailures: previewScriptResults.filter(row => !row.ok), api: cfg.SurvivalPurpleLottery.Inspect(), canvas: { screenBox: origin.toJSON(), scale }, nodes: Object.fromEntries(ids.map(id => [id, record(nodes[id])])), sceneLayers: { extension: record(find(active, 'LotteryGW2SceneExtension')), subject: record(find(active, 'LotteryGW2SceneSubject')) }, legacyGuaranteeLine: record(find(nodes.LotteryGuaranteeRow, 'LHGuaranteeLine')), navigation: nav, preview, draw: { single: draw('Single'), ten: draw('Ten') }, footerActions: ['LHDetails', 'LHHistory', 'LotteryAnnouncement'].map(id => ({ button: record(nodes[id]), captions: nodes[id].Children().filter(p => p.paneltype === 'Label').map(record) })), calls: previewCalls, t10: !!nodes.LotteryGW2Chest };
}

function inspectResult() {
    const canvas = nodes.LotteryGW2ResultCanvas, origin = canvas.el.getBoundingClientRect(), scale = origin.width / 1672;
    function visible(panel) { for (let p = panel; p; p = p.GetParent()) { const s = getComputedStyle(p.el); if (!p.visible || s.display === 'none' || s.visibility === 'hidden') return false; } return !!panel && panel.el.getBoundingClientRect().width > 0; }
    const record = panel => { if (!panel) return null; const r = panel.el.getBoundingClientRect(), s = getComputedStyle(panel.el); return { id: panel.id, text: panel.text, box: { x: (r.x - origin.x) / scale, y: (r.y - origin.y) / scale, width: r.width / scale, height: r.height / scale }, screenBox: r.toJSON(), fontSize: s.fontSize, style: { backgroundImage: s.backgroundImage, backgroundColor: s.backgroundColor, borderWidth: s.borderTopWidth, opacity: s.opacity, zIndex: s.zIndex, opacityMaskInput: panel.style.opacityMask || null, maskImage: s.maskImage, widthInput: panel.style.width || null, horizontalAlignInput: panel.style.horizontalAlign || null, overflow: s.overflow }, visible: visible(panel), enabled: panel.enabled, images: [...panel.el.querySelectorAll('img'), ...(panel.el.tagName === 'IMG' ? [panel.el] : [])].map(image => ({ decoded: image.complete && image.naturalWidth > 0, src: image.currentSrc || image.src })) }; };
    const cardRows = nodes.LotteryItemList.Children().map(card => { const cell = card.__lotteryGW2Cell; return { item: card.__lotteryItem, card: record(card), frame: record(cell?.well), icon: record(cell?.icon), name: record(cell?.name), nameRow: record(cell?.nameRow), nameHasDirectRowParent: !!cell?.name && cell.name.GetParent() === cell.nameRow }; });
    return { errors: previewErrors, scriptFailures: previewScriptResults.filter(row => !row.ok), viewport: { width: innerWidth, height: innerHeight }, canvas: record(canvas), fullscreen: record(nodes.LotteryGW2Fullscreen), shade: record(nodes.LotteryGW2ResultShade), list: record(nodes.LotteryItemList), cards: cardRows, confirm: record(nodes.LotteryConfirm), again: record(nodes.LotteryAgain), heading: record(nodes.LotteryResultHeading), api: cfg.SurvivalPurpleLottery.Inspect(), calls: previewCalls };
}

const near = (got, want, label, tolerance = 0.8) => assert(Math.abs(got - want) <= tolerance, label + ': measured ' + got + ', reference ' + want);
function rectangle(actual, expected, label, tolerance) { assert(actual, label + ' exists'); for (const key of ['x', 'y', 'width', 'height']) near(actual[key], expected[key], label + '.' + key, tolerance); }
function frameStyle(got, reference, label) { assert(got, label + ' exists'); assert.equal(got.style.fontSize, reference.style.fontSize, label + ' measured font size'); }
function checkMain(actual, reference, pool, zero = false) {
    assert.deepEqual(actual.errors, []); assert.deepEqual(actual.scriptFailures, []); assert.equal(actual.api.selected, pool); assert(!actual.t10);
    near(actual.canvas.screenBox.height, actual.canvas.scale * 941, 'Main canvas scales uniformly');
    rectangle(actual.nodes.LotteryGW2HeaderSkin.box, reference.components.header.box, 'header');
    rectangle(actual.nodes.LotteryGW2SidebarSkin.box, reference.components.sidebar.box, 'sidebar');
    rectangle(actual.nodes.LotteryGW2FooterSkin.box, reference.components.footer.box, 'footer');
    assert.equal(actual.nodes.LotteryGW2FooterSkin.style.background,'rgb(17, 31, 24)','The actual footer material is opaque over the pool scene');near(Number(actual.nodes.LotteryGW2FooterSkin.style.opacity),1,'Footer material opacity',0.001);
    for (const id of ['LotteryGW2SidebarHeading', 'LotteryGW2SidebarNote', 'LotteryGW2SidebarEmblem']) { assert(actual.nodes[id]?.visible, id + ' is visible'); assert(Number(actual.nodes[id].style.zIndex) >= 4, id + ' paints above the sidebar backing'); }
    near(Number(actual.nodes.LotteryGW2SidebarTexture.style.opacity), 0.25, 'Sidebar texture opacity', 0.001);
    near(Number(actual.sceneLayers.extension.style.opacity), 0.25, 'Scene extension opacity', 0.001);
    assert(actual.sceneLayers.subject.style.opacityMaskInput?.includes('scene_blend.svg'), 'Authored pool-scene mask stays active');
    assert(actual.sceneLayers.subject.style.maskImage.includes('data:image/svg+xml'), 'The browser renders the exact SVG mask bytes rather than ignoring a native property');
    assert.equal(actual.sceneLayers.subject.style.maskSize, '100% 100%');
    // Native Panorama needs stronger dimming than the approved HTML. Keep this
    // explicit compensation separate from geometric parity and native review.
    const colors = css => [...css.matchAll(/rgba?\(([^)]+)\)/g)].map(match => match[1].trim().split(/[,\s/]+/).map(Number));
    const floor = actual.nodes.LotteryGW2FloorWash.style.backgroundImage, gradient = /^linear-gradient\(([\s\S]*)\)$/.exec(floor);
    assert(gradient, 'Rendered FloorWash is a single linear gradient: ' + floor);
    const stops = [];let depth = 0, start = 0;for(let i = 0; i < gradient[1].length; i++){const ch = gradient[1][i];if(ch === '(')depth++;else if(ch === ')')depth--;else if(ch === ',' && depth === 0){stops.push(gradient[1].slice(start,i).trim());start = i + 1;}}stops.push(gradient[1].slice(start).trim());
    // CSSOM may omit the default 180deg direction. The equivalent 0deg form
    // must reverse both stop locations and their associated alpha values.
    let angle = 180;if(!/^rgba?\(/.test(stops[0])){const direction = stops.shift(), degrees = /^(-?[\d.]+)deg$/.exec(direction);assert(degrees || direction === 'to bottom' || direction === 'to top', 'FloorWash has a known vertical direction: ' + direction);angle = degrees ? ((Number(degrees[1]) % 360) + 360) % 360 : direction === 'to top' ? 0 : 180;}
    assert(angle === 0 || angle === 180, 'FloorWash darkens toward the bottom, not across the scene');assert.equal(stops.length,4,'FloorWash retains exactly four ordered stops');
    const expectedStops = angle === 180 ? [[0,0],[40,0],[82,0.94],[100,0.999]] : [[0,0.999],[18,0.94],[60,0],[100,0]];
    stops.forEach((stop,i)=>{const match = /^rgba?\(([^)]+)\)\s+(-?[\d.]+)%$/.exec(stop);assert(match,'FloorWash stop has an explicit color and position: '+stop);const color = match[1].trim().split(/[,\s/]+/).map(Number);assert.deepEqual(color.slice(0,3),[12,18,24],'FloorWash stop '+i+' color');near(Number(match[2]),expectedStops[i][0],'FloorWash ordered stop '+i+' position',0.001);near(color[3] ?? 1,expectedStops[i][1],'FloorWash ordered stop '+i+' alpha',0.002);});
    // CSSOM rounds 0.999 to opaque rgb(). The alpha tolerance is below one
    // 8-bit step; it cannot accept a misplaced stop or the previous 0.98 value.
    const scene = actual.nodes.LotteryGW2SceneWash.style.backgroundImage, sceneColors = colors(scene);
    assert(scene.includes('linear-gradient') && sceneColors.length === 3, 'Rendered SceneWash retains its three native compensation stops');
    near(sceneColors[0][3] ?? 1, 247 / 255, 'Native-compensated scene left alpha', 0.002);for (const color of sceneColors.slice(1)) near(color[3] ?? 1, 33 / 255, 'Native-compensated scene right alpha', 0.002);
    for (let i = 0; i < 4; i++) {
        const nav = actual.navigation[i], expected = reference.navigation[i];
        rectangle(nav.button.box, expected.button.box, 'nav ' + nav.id);
        rectangle(nav.icon?.box, expected.icon.box, 'nav icon ' + nav.id);
        frameStyle(nav.title, expected.title, 'nav title ' + nav.id);
        assert.equal(nav.title.style.textOverflow, 'clip', 'Native navigation has no glyph shrink');
    }
    frameStyle(actual.nodes.LotteryTitle, reference.components.heroHeading, 'hero title');
    frameStyle(actual.nodes.LotteryGuaranteeValue, reference.components.heroGuarantee, 'hero guarantee');
    assert.match(actual.nodes.LotteryGuaranteeValue.text, /保底.*奖励永久保留/, 'Hero metadata includes the complete authoritative guarantee and permanent-reward caption');
    assert(!actual.nodes.LHGuaranteeQuality?.visible, 'Retired large guarantee quality does not duplicate the single-line R5 metadata');
    assert(!actual.legacyGuaranteeLine?.visible, 'Retired guarantee underline does not remain below the R5 metadata');
    assert.equal(actual.preview.length, 4, 'Four featured previews retain the approved row');
    assert.equal(actual.nodes.LotteryGW2PreviewCaption.style.fontSize, '18px', 'The requested preview heading is 18px');
    actual.preview.forEach((card, i) => {
        const target = reference.preview[i];
        // The approved row moved up 2px to give the larger natural captions
        // room. The historical HTML reference itself remains unchanged.
        rectangle(card.card.box, { ...target.card.box, y: target.card.box.y - 2, height: 150 }, 'preview card ' + i);
        rectangle(card.frame?.box, { ...target.frame.box, y: target.frame.box.y - 2 }, 'preview quality plate ' + i);
        rectangle(card.icon?.box, { ...target.icon.box, y: target.icon.box.y - 2 }, 'preview icon ' + i);
        assert(card.item && card.item.id, 'Preview retains an authoritative reward identity');
        assert(card.icon.images.length && card.icon.images.every(image => image.decoded), 'Real preview art decodes');
        assert.equal(card.frame.style.backgroundImage, card.sharedBackground, 'The independent plate uses the shared authoritative quality background');
        assert.equal(card.frame.style.borderWidth, '0px', 'The quality plate adds no decorative frame');
        assert.equal(card.frame.style.boxShadow, 'none', 'The quality plate adds no shadow border');
        assert.equal(card.icon.style.backgroundImage, 'none', 'Preview art stays transparent over its independent quality plate');
        assert.equal(card.icon.style.borderWidth, '0px', 'The image has no duplicate inner quality frame');
        assert(!card.rarity?.visible, 'The main showcase has no rarity corner badge');
        assert.equal(card.caption.style.fontSize, '19.5px', 'The requested natural item name is 19.5px');
        assert.equal(card.caption.style.textDecoration, 'none', 'The item name has no underline');
        near(card.name.box.height, 30, 'Preview caption row height ' + i);
        near(card.caption.box.x + card.caption.box.width / 2, card.frame.box.x + card.frame.box.width / 2, 'Preview caption center ' + i);
        assert(card.caption.box.x >= card.card.box.x - .8 && card.caption.box.right <= card.card.box.right + .8, 'The larger natural caption remains inside its card');
    });
    for (const [kind, action] of Object.entries(actual.draw)) {
        const target = reference.draw[kind], buttonBox = kind === 'single' ? { x: 1091, y: 683, width: 244, height: 84 } : target.button.box;
        rectangle(action.button.box, buttonBox, kind + ' button');
        assert.equal(action.button.enabled, !zero, kind + ' uses real fixture balance');
        frameStyle(action.title, target.label, kind + ' title'); frameStyle(action.cost, target.cost, kind + ' cost');
        near(action.title.box.x + action.title.box.width / 2, action.button.box.x + action.button.box.width / 2, kind + ' title horizontal center');
        near(action.title.box.y, action.button.box.y + 7, kind + ' paid title top');
        near(action.ticket.box.width, 52, kind + ' ticket width'); near(action.ticket.box.height, 36, kind + ' ticket height');
        near(action.costRow.box.x + action.costRow.box.width / 2, action.button.box.x + action.button.box.width / 2, kind + ' cost center');
        assert.match(action.cost.text, /×\s*\d/, kind + ' price displays a multiplication prefix');
        assert.equal(action.title.style.textOverflow, 'clip'); assert.equal(action.cost.style.textOverflow, 'clip');
        assert(action.surface.style.backgroundImage.includes(kind === 'ten' ? 'relic_agi_button' : 'buyback_button'), 'Correct installed official button artwork');
        if (kind === 'single') {
            assert.equal(action.button.style.borderWidth, '0px', 'Single draw adds no independent outer frame');
            assert.equal(action.surface.style.borderWidth, '0px', 'Single draw native texture adds no authored border');
            assert.equal(action.surface.style.boxShadow, 'none', 'Single draw has no extra frame shadow');
            assert(!action.focus?.visible, 'Single draw has no focus frame');
        }
    }
    const pity = actual.nodes.LotteryDrawPityCaption;
    assert(pity.visible && pity.box.bottom <= actual.draw.ten.button.box.y - 9, 'Measured pity clears the button above it');
    rectangle(actual.nodes.LotterySkipAnimation.box, reference.components.skip.box, 'skip control');
    const specialTicket = pool === 'dragon_knight' || pool === 'summer';
    assert.equal(actual.nodes.LotteryTicketPurchase.visible, specialTicket, 'Only special tickets expose the purchase action');
    assert.equal(actual.nodes.LotteryGW2PurchasePlus.visible, specialTicket, 'Normal ticket balance has no purchase plus');
    if (specialTicket) { near(actual.nodes.LotteryTicketPurchase.box.width, 44, 'wallet plus hit width'); near(actual.nodes.LotteryTicketPurchase.box.height, 44, 'wallet plus hit height'); }
    near(actual.nodes.LotteryCloseButton.box.width, 44, 'close hit width'); near(actual.nodes.LotteryCloseButton.box.height, 44, 'close hit height');
    near(actual.nodes.LotteryGW2CloseIcon.box.width, 32, 'close glyph width'); near(actual.nodes.LotteryGW2CloseIcon.box.height, 32, 'close glyph height');
    actual.footerActions.forEach((row, i) => { near(row.button.box.height, 44, 'footer action height'); assert(row.captions.length); for (const label of row.captions) { assert.equal(label.style.fontSize, reference.footerActions[i].button.style.fontSize); assert.equal(label.style.textOverflow, 'clip'); } });
}

function checkResult(actual, count) {
    assert.deepEqual(actual.errors, []); assert.deepEqual(actual.scriptFailures, []); assert.equal(actual.cards.length, count);
    near(actual.canvas.box.width, 1672, 'Result logical canvas width'); near(actual.canvas.box.height, 941, 'Result canvas scales uniformly');
    assert.equal(actual.shade.style.backgroundColor, 'rgb(2, 8, 6)', 'Actual result shade uses the authored opaque color'); near(Number(actual.shade.style.opacity), 0.995, 'Native-compensated result shade opacity', 0.001); assert(Number(actual.canvas.style.zIndex) > Number(actual.shade.style.zIndex), 'Result controls paint above the dimming layer');
    const full = actual.fullscreen.screenBox;
    near(full.x, 0, 'Result fullscreen left'); near(full.y, 0, 'Result fullscreen top'); near(full.width, actual.viewport.width, 'Result fullscreen width'); near(full.height, actual.viewport.height, 'Result fullscreen height');
    const single = count === 1;
    near(actual.list.box.width, single ? 242 : 920, 'Result centered grid width'); near(actual.list.box.x + actual.list.box.width / 2, 836, 'Result grid horizontal center');
    const inside = (panel, label) => { assert(panel?.visible, label + ' is visible through its full ancestry'); const b = panel.box; assert(b.width > 0 && b.height > 0 && b.x >= -0.8 && b.y >= -0.8 && b.x + b.width <= 1672.8 && b.y + b.height <= 941.8, label + ' stays inside the fitted logical canvas'); };
    inside(actual.list, 'Result grid'); inside(actual.confirm, 'Confirm'); inside(actual.again, 'Again'); inside(actual.heading, 'Result heading');
    rectangle(actual.heading.box,{x:75,y:55,width:1200,height:58},'Result heading');rectangle(actual.confirm.box,{x:594,y:770,width:220,height:84},'Confirm action');rectangle(actual.again.box,{x:834,y:770,width:244,height:84},'Again action');
    actual.cards.forEach((card,index)=>assert.equal(card.nameHasDirectRowParent,true,'Result '+index+' reuses the exact fixed name row as its direct parent'));
    actual.cards.forEach((card, index) => { assert(card.item && card.item.id); for (const role of ['card', 'frame', 'icon', 'name', 'nameRow']) inside(card[role], 'Result ' + index + ' ' + role); near(card.frame.box.width, single ? 232 : 154, 'Result frame ' + index); near(card.frame.box.height, single ? 232 : 154, 'Result frame height ' + index); near(card.icon.box.width, single ? 198 : 129, 'Result image ' + index); near(card.icon.box.height, single ? 198 : 129, 'Result image height ' + index); assert(card.icon.images.length && card.icon.images.every(image => image.decoded), 'Every authoritative result image decodes'); assert.equal(card.icon.style.backgroundImage, 'none', 'Transparent R5 result art has no shared grade gradient'); assert.equal(card.icon.style.borderWidth, '0px', 'Result images do not add a duplicate inner grade frame'); near(card.nameRow.box.width, card.card.box.width, 'Result caption row width ' + index); near(card.nameRow.box.x + card.nameRow.box.width / 2, card.frame.box.x + card.frame.box.width / 2, 'Result caption row aligns with art ' + index); near(card.name.box.x + card.name.box.width / 2, card.nameRow.box.x + card.nameRow.box.width / 2, 'Actual natural caption box is centered ' + index); assert(card.name.box.width <= card.nameRow.box.width + 0.8, 'Caption glyph box stays within its fixed row'); assert.equal(card.name.style.widthInput, 'fit-children'); assert.equal(card.name.style.horizontalAlignInput, 'center'); assert.equal(card.nameRow.style.overflow, 'hidden'); });
    for (let i = 0; i < actual.cards.length; i++) for (let j = i + 1; j < actual.cards.length; j++) { const a = actual.cards[i].card.box, b = actual.cards[j].card.box; assert(a.x + a.width <= b.x + 0.8 || b.x + b.width <= a.x + 0.8 || a.y + a.height <= b.y + 0.8 || b.y + b.height <= a.y + 0.8, 'Result cards ' + i + '/' + j + ' never overlap'); }
    near(actual.confirm.box.width, 220, 'Confirm width'); near(actual.confirm.box.height, 84, 'Confirm height'); near(actual.again.box.width, 244, 'Again width'); near(actual.again.box.height, 84, 'Again height'); assert(actual.confirm.enabled && actual.again.enabled);
}

async function captureCanvas(b, file, screenBox) {
    const shot = await b.call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: screenBox.x, y: screenBox.y, width: screenBox.width, height: screenBox.height, scale: 1672 / screenBox.width } });
    const bytes = Buffer.from(shot.data, 'base64'); fs.writeFileSync(file, bytes); return file;
}

async function sideBySide(b, left, right, output, labels) {
    const data = file => 'data:image/png;base64,' + fs.readFileSync(file).toString('base64');
    const result = await b.run('(async()=>{const urls=' + JSON.stringify([data(left), data(right)]) + ',labels=' + JSON.stringify(labels) + ';const images=await Promise.all(urls.map(async src=>{const image=new Image();image.src=src;await image.decode();return image;}));const canvas=document.createElement("canvas");canvas.width=3344;canvas.height=981;const c=canvas.getContext("2d");c.fillStyle="#101918";c.fillRect(0,0,3344,981);c.fillStyle="#e8eadc";c.font="22px Arial";labels.forEach((label,i)=>{c.fillText(label,18+i*1672,28);c.drawImage(images[i],i*1672,40,1672,941);});return canvas.toDataURL("image/png");})()');
    fs.writeFileSync(output, Buffer.from(result.split(',')[1], 'base64'));
}

async function backgroundStats(b, file) {
    const image = 'data:image/png;base64,' + fs.readFileSync(file).toString('base64');
    return b.run('(async()=>{const image=new Image();image.src=' + JSON.stringify(image) + ';await image.decode();const canvas=document.createElement("canvas");canvas.width=image.width;canvas.height=image.height;const c=canvas.getContext("2d");c.drawImage(image,0,0);return [[32,180,180,480],[1460,180,180,480]].map(([x,y,width,height])=>{const pixels=c.getImageData(x,y,width,height).data,values=[];for(let i=0;i<pixels.length;i+=4)values.push(.2126*pixels[i]+.7152*pixels[i+1]+.0722*pixels[i+2]);values.sort((a,b)=>a-b);return{region:{x,y,width,height},mean:values.reduce((a,b)=>a+b,0)/values.length,p95:values[Math.floor(values.length*.95)],max:values.at(-1)};});})()');
}

async function run() {
    process.chdir(repo); fs.mkdirSync(out, { recursive: true }); fs.mkdirSync(captures, { recursive: true });
    const temp = path.join(out, 'tmp'); fs.mkdirSync(temp, { recursive: true }); process.env.TEMP = temp; process.env.TMP = temp;
    const reference = await captureReference(), native = exportNative(), built = assembleProduction(native);
    checkFrozen(built.assembly);
    const report = { kind: 'r5_actual_production_browser_parity', gameVerified: false, networkBlocked: true, generatedAt: new Date().toISOString(), referenceSource: reference.source, sourceGraph: built.assembly.sourceGraph, nativeResources: native.records, nativeCompositingCompensation: { resultShadeOpacity: 0.995, sceneWashAlpha: { left: '#f7', right: '#21' }, floorWashAlpha: [0, 0, 0.94, 0.999], footerSkin: { rgba: '#111f18ff', computedRGB: 'rgb(17, 31, 24)', opacity: 1 }, purpose: 'Production-specific dimming and the opaque footer compensate for the brighter Source 2 scene composition. This deliberately differs from the reference HTML alpha values; browser checks only confirm transport and geometry, not native darkness or color parity.', nativeVerifiedByThisTool: false }, cases: [], states: [], results: [], screenshots: [], limitations: ['Actual production code and CSV fixture run in a browser Panorama adapter. Native font rasterization/compositing is not verified.', 'Original per-pool backgrounds and original cinematic remain intentional differences from the approved HTML forest scene.', 'Native scene/result dimming and the opaque footer use explicit compensation values rather than matching the historical HTML alpha; native screenshots must establish the final appearance.', 'All ticket balances/results are explicit local fixture data; outbound game events remain an in-memory journal.', 'Geometry assertions use actual DOM bounding rectangles normalized to the 1672x941 control canvas, not inline style intentions.'] };
    const b = await browser(); let viewport = [1920, 1080];
    try {
        await b.call('Network.setBlockedURLs', { urls: ['http://*', 'https://*', 'ws://*', 'wss://*'] });
        for (const size of [[1920, 1080], [1280, 720]]) {
            viewport = size; await b.call('Emulation.setDeviceMetricsOverride', { width: size[0], height: size[1], deviceScaleFactor: 1, mobile: false }); await b.go(built.entry); assert(await b.run('previewReady'));
            for (const pool of ['map', 'cultivation', 'dragon_knight', 'summer']) {
                await b.run('lotteryPreviewSelect(' + JSON.stringify(pool) + ',20)'); await sleep(180);
                const state = await b.run('(' + inspectProduction.toString() + ')()'); checkMain(state, reference.geometry, pool);
                const file = path.join(captures, size[0] + '_' + pool + '_normal.png'); await captureCanvas(b, file, state.canvas.screenBox);
                report.cases.push({ viewport: size, pool, state }); report.screenshots.push(relative(file));
                if (size[0] === 1920 && pool === 'map') { const comparison = path.join(captures, 'comparison_map_normal.png'); await sideBySide(b, path.join(out, 'reference_stage.png'), file, comparison, ['Approved R5 reference', 'Actual production / original pool scene retained']); report.screenshots.push(relative(comparison)); }
            }
            await b.run('lotteryPreviewSelect("map",0)'); await sleep(150);
            const zero = await b.run('(' + inspectProduction.toString() + ')()'); checkMain(zero, reference.states.disabled, 'map', true);
            const zeroFile = path.join(captures, size[0] + '_map_zero_tickets.png'); await captureCanvas(b, zeroFile, zero.canvas.screenBox); report.states.push({ viewport: size, name: 'zero-tickets', state: zero }); report.screenshots.push(relative(zeroFile));
            if (size[0] === 1920) { const comparison = path.join(captures, 'comparison_map_disabled.png'); await sideBySide(b, path.join(out, 'reference_stage_disabled.png'), zeroFile, comparison, ['Approved R5 disabled reference', 'Actual production / zero tickets']); report.screenshots.push(relative(comparison)); }
            const before = await b.run('previewCalls.filter(row=>row.name==="ui_lottery_draw_request").length');
            await b.run('nodes.LotterySingleButton.events.onactivate();nodes.LotteryTenButton.events.onactivate();syncLayout();true');
            assert.equal(await b.run('previewCalls.filter(row=>row.name==="ui_lottery_draw_request").length'), before, 'Zero-ticket callbacks never submit a draw');
            checkMain(await b.run('(' + inspectProduction.toString() + ')()'), reference.states.disabled, 'map', true);
            checkFrozen(built.assembly);
        }
        viewport = [1920, 1080]; await b.call('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false }); await b.go(built.entry); assert(await b.run('previewReady'));
        await b.run('lotteryPreviewSelect("map",20)');
        for (const id of ['LotterySingleButton', 'LotteryTenButton']) {
            await b.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 1, y: 1 }); await sleep(180); await b.run('syncLayout();true');
            const baseline = await b.run('(' + inspectProduction.toString() + ')()');
            const point = await b.run('(()=>{const r=nodes[' + JSON.stringify(id) + '].el.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()');
            await b.call('Input.dispatchMouseEvent', { type: 'mouseMoved', ...point }); await sleep(180); await b.run('syncLayout();true');
            const state = await b.run('(' + inspectProduction.toString() + ')()'); checkMain(state, reference.geometry, 'map'); report.states.push({ name: 'hover', target: id, state });
            const key = id.includes('Single') ? 'single' : 'ten', filter = state.draw[key].surface.style.filter;
            assert.notEqual(filter, baseline.draw[key].surface.style.filter, 'Moving onto the actual button changes its surface rather than accepting a fixed hover-looking style');
            assert(filter.includes('0.933') || filter.includes('0.975'), 'Hover visibly changes the actual official surface filter: ' + filter);
            const hoverFile = path.join(captures, 'map_hover_' + key + '.png'); await captureCanvas(b, hoverFile, state.canvas.screenBox); report.screenshots.push(relative(hoverFile));
            const comparison = path.join(captures, 'comparison_map_hover_' + key + '.png'); await sideBySide(b, path.join(out, 'reference_stage_hover.png'), hoverFile, comparison, ['Approved R5 hover reference (both)', 'Actual production / ' + key + ' hovered']); report.screenshots.push(relative(comparison));
        }
        await b.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 1, y: 1 });
        for (const count of [1, 10]) {
            const draw = await b.run('(()=>{cfg.SurvivalLottery.CloseResult();lotteryPreviewSend("map",100);nodes.LotterySkipAnimation.checked=true;cfg.SurvivalLottery.SetSkipAnimation();const before=previewCalls.filter(row=>row.name==="ui_lottery_draw_request").length;cfg.SurvivalLottery.' + (count === 10 ? 'DrawTen' : 'DrawSingle') + '();const requests=previewCalls.filter(row=>row.name==="ui_lottery_draw_request"),request=requests.at(-1);if(requests.length!==before+1)throw Error("Expected exactly one draw request");const snapshot=lotteryPreviewSnapshot("map",100-' + count + '),results=snapshot.items.slice(0,' + count + ').map(item=>({...item,count:1}));emit("ui_lottery_result",{ok:1,request_id:request.payload.request_id,pool_id:"map",count:' + count + ',results,snapshot});syncLayout();return{request:request.payload,itemIds:results.map(item=>item.id)};})()');
            await sleep(220); const state = await b.run('(' + inspectResult.toString() + ')()'); checkResult(state, count);
            assert.deepEqual(state.cards.map(card => card.item.id), draw.itemIds, 'Result cards are the actual callback items');
            const file = path.join(captures, 'result_' + count + '.png'); await captureCanvas(b, file, state.canvas.screenBox);
            const background = await backgroundStats(b, file); assert(background.every(sample => sample.mean < 30 && sample.p95 < 35), 'Actual captured result background is near black outside the reward grid: ' + JSON.stringify(background));
            report.results.push({ count, draw, state, backgroundPixelSamples: background }); report.screenshots.push(relative(file));
            await b.run('nodes.LotteryConfirm.events.onactivate();syncLayout();true');
            assert(await b.run('!nodes.LotteryWindow.BHasClass("LotteryResultsShown")'), 'Original confirmation callback closes results');
        }
        checkFrozen(built.assembly); report.status = 'PASS';
    } catch (error) {
        report.status = 'FAIL'; report.failure = error.stack || String(error);
        try { report.failureState = await b.run('(' + inspectProduction.toString() + ')()'); await b.shot(path.join(captures, 'failure.png'), viewport[0], viewport[1]); } catch {}
        throw error;
    } finally {
        fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2) + '\n'); b.close();
    }
    console.log('LOTTERY_R5_PRODUCTION_PARITY_PASS ' + relative(path.join(out, 'report.json')));
    return report;
}

module.exports = { run, inspectProduction, inspectResult, checkMain, checkResult, exportNative, assembleProduction, panoramaLinearGradient };
if (require.main === module) {
    if (!process.argv.includes('--run')) console.log('Prepared only. Run with --run after the production owner declares the source ready.');
    else run().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
}
