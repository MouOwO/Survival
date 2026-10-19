'use strict';

// Extract the approved HTML itself. This tool does not load production sources,
// connect to Panorama, edit the reference, or submit game/account requests.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { browser, sleep } = require('../lottery_emerald_game_20261019/browser.cjs');

const repo = path.resolve(__dirname, '../..');
const reference = path.join(repo, 'design_refs/lottery_emerald_buttons_20261019/round_5.html');
const output = path.join(repo, 'output/lottery_r5_parity_20261019');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const relative = file => path.relative(repo, file).replaceAll('\\', '/');

// This function executes inside the reference's browser context. Image URLs are
// represented by source IDs rather than duplicating the embedded bitmap data.
function inspectScene() {
    const api = window.lotteryDemoAPI;
    const scene = document.querySelector('#mainCanvas .lottery-scene');
    if (!api || !scene) throw Error('Approved R5 scene is not ready');
    const data = api.getData(), state = api.getState();
    const sceneBox = scene.getBoundingClientRect();
    const scaleX = sceneBox.width / 1672, scaleY = sceneBox.height / 941;
    const aliases = new Map(), assetRows = new Map();
    function register(url, row) {
        if (!url || typeof url !== 'string') return;
        if (!aliases.has(url)) aliases.set(url, row);
        if (!assetRows.has(row.key)) assetRows.set(row.key, row);
    }
    for (const scheme of data.schemes) {
        for (const [role, asset] of Object.entries(scheme.assets || {})) {
            if (asset) register(asset.preview, { key: 'official:' + asset.id, id: asset.id, role, sourcePath: asset.sourcePath, original: asset.original, width: asset.width, height: asset.height });
        }
    }
    for (const [role, asset] of Object.entries(data.controls || {})) {
        if (asset) register(asset.preview, { key: 'control:' + role, id: asset.id, role, sourcePath: asset.sourcePath, original: asset.original, width: asset.width, height: asset.height });
    }
    for (const pool of data.pools) {
        register(typeof pool.icon === 'string' ? pool.icon : pool.icon?.preview, { key: 'pool:' + pool.id + ':icon', poolId: pool.id, role: 'poolIcon' });
        register(pool.ticketIcon, { key: 'pool:' + pool.id + ':ticket', poolId: pool.id, role: 'ticketIcon', ticketKind: pool.ticketKind });
        for (const item of pool.rewards || []) register(item.image, { key: 'reward:' + item.id, itemId: item.id, name: item.name, role: 'rewardIcon' });
    }
    function imageSource(url) {
        if (!url) return null;
        return aliases.get(url) || (url.startsWith('data:') ? { key: 'unmapped-embedded-image', mime: url.slice(5, url.indexOf(';')), encodedCharacters: url.length } : { key: url });
    }
    function clean(value) {
        return String(value || '').replace(/url\((?:"([^"]*)"|'([^']*)'|([^)]*))\)/g, (_, a, b, c) => {
            const row = imageSource(a || b || c || '');
            return 'url("' + (row?.key || '') + '")';
        });
    }
    const fields = [
        'display', 'position', 'boxSizing', 'width', 'height', 'minWidth', 'minHeight', 'maxWidth', 'maxHeight',
        'fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'lineHeight', 'letterSpacing', 'color', 'textAlign', 'textShadow', 'webkitTextStroke', 'whiteSpace', 'textOverflow',
        'backgroundColor', 'backgroundImage', 'backgroundSize', 'backgroundPosition', 'backgroundRepeat', 'backgroundClip',
        'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth', 'borderTopStyle', 'borderTopColor', 'borderRightColor', 'borderBottomColor', 'borderLeftColor', 'borderRadius', 'boxShadow',
        'opacity', 'filter', 'transform', 'transformOrigin', 'outlineColor', 'outlineWidth', 'outlineStyle', 'outlineOffset',
        'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
        'alignItems', 'justifyContent', 'flexDirection', 'gap', 'rowGap', 'columnGap', 'overflow', 'zIndex', 'maskImage', 'mixBlendMode',
        'transitionProperty', 'transitionDuration', 'animationName', 'animationDuration'
    ];
    const round = n => Math.round(n * 10000) / 10000;
    function box(rect) {
        return { x: round((rect.left - sceneBox.left) / scaleX), y: round((rect.top - sceneBox.top) / scaleY), width: round(rect.width / scaleX), height: round(rect.height / scaleY), right: round((rect.right - sceneBox.left) / scaleX), bottom: round((rect.bottom - sceneBox.top) / scaleY) };
    }
    function css(element, pseudo) {
        const style = getComputedStyle(element, pseudo || null);
        return Object.fromEntries(fields.map(key => [key, clean(style[key])]));
    }
    function record(element, selector) {
        if (!element) return null;
        const bounds = element.getBoundingClientRect(), parent = element.parentElement?.getBoundingClientRect();
        return {
            selector, tag: element.tagName.toLowerCase(), classes: element.className?.baseVal ?? String(element.className || ''),
            text: String(element.textContent || '').replace(/\s+/g, ' ').trim(),
            box: box(bounds),
            localBox: parent ? { x: round((bounds.left - parent.left) / scaleX), y: round((bounds.top - parent.top) / scaleY), width: round(bounds.width / scaleX), height: round(bounds.height / scaleY) } : null,
            offsetBox: { x: element.offsetLeft, y: element.offsetTop, width: element.offsetWidth, height: element.offsetHeight },
            style: css(element),
            ...(element.tagName === 'IMG' ? { image: { ...imageSource(element.currentSrc || element.src), naturalWidth: element.naturalWidth, naturalHeight: element.naturalHeight, decoded: element.complete && element.naturalWidth > 0 } } : {}),
            ...('disabled' in element ? { disabled: element.disabled } : {})
        };
    }
    const one = selector => record(scene.querySelector(selector), selector);
    const child = (element, selector) => record(element.querySelector(selector), selector);
    const pseudo = (element, name) => ({ pseudo: name, style: css(element, name) });
    function draw(selector) {
        const button = scene.querySelector(selector);
        return { button: record(button, selector), label: child(button, '.draw-label'), cost: child(button, '.draw-cost'), ticket: child(button, '.draw-cost img'), amount: child(button, '.draw-cost > span'), pity: child(button, '.draw-pity'), surface: pseudo(button, '::before'), glass: child(button, '.button-glass'), glassSheen: pseudo(button.querySelector('.button-glass'), '::after') };
    }
    const components = Object.fromEntries(Object.entries({
        header: '.window-header', headerShade: '.header-shade', headerTitle: '.window-title', headerSubtitle: '.window-subtitle',
        sidebar: '.sidebar-panel', sidebarHeading: '.sidebar-top-label', sidebarEmblem: '.sidebar-emblem', sidebarNote: '.sidebar-bottom-note',
        mainPanel: '.main-panel', mainArt: '.main-art', mainReadability: '.main-readability', mainTexture: '.main-texture', mainTopLine: '.main-top-line',
        heroEyebrow: '.banner-eyebrow', heroHeading: '.banner-heading', heroDescription: '.banner-description', heroEmphasis: '.banner-description .emphasis', heroGuarantee: '.banner-meta', heroDivider: '.banner-rule', heroDividerImage: '.banner-rule img',
        previewHeading: '.reward-heading', previewRow: '.reward-showcase', drawArea: '.draw-area',
        footer: '.bottom-bar', skip: '.skip-control', skipInput: '.skip-control input', footerNote: '.footer-end',
        wallet: '.wallet', walletIcon: '.wallet-icon', walletCount: '.wallet-count', walletKind: '.wallet-kind', walletPlus: '.wallet-plus', walletPlusIcon: '.wallet-plus img', close: '.window-close', closeIcon: '.window-close img'
    }).map(([role, selector]) => [role, one(selector)]));
    const pool = data.pools.find(pool => pool.id === state.pool);
    return {
        state: { scheme: state.scheme, pool: state.pool, phase: state.phase, buttonPreview: window.emeraldReviewAPI.getButtonState(), fixtureBalance: state.balances[state.pool] },
        viewport: { width: innerWidth, height: innerHeight, devicePixelRatio },
        scene: { width: 1672, height: 941, scaleX: round(scaleX), scaleY: round(scaleY), screenBox: { x: sceneBox.x, y: sceneBox.y, width: sceneBox.width, height: sceneBox.height } },
        components,
        navigation: [...scene.querySelectorAll('.pool-choice')].map((button, index) => ({ poolId: button.dataset.pool, button: record(button, '.pool-choice:nth-child(' + (index + 1) + ')'), icon: child(button, 'img'), title: child(button, '.pool-name'), subtitle: child(button, '.pool-subtitle'), chevron: child(button, '.pool-chevron'), indicator: pseudo(button, '::after') })),
        preview: [...scene.querySelectorAll('.preview-reward')].map((card, index) => ({ itemId: pool.rewards[index]?.id, card: record(card, '.preview-reward:nth-child(' + (index + 1) + ')'), frame: child(card, '.reward-image-wrap'), icon: child(card, '.reward-image-wrap img'), rarity: child(card, '.reward-rarity'), name: child(card, '.preview-reward-name'), line: child(card, '.reward-line') })),
        draw: { single: draw('.draw-action.single'), ten: draw('.draw-action.ten') },
        footerActions: [...scene.querySelectorAll('.footer-action')].map((button, index) => ({ button: record(button, '.footer-action:nth-of-type(' + (index + 1) + ')'), icon: child(button, 'img'), action: button.dataset.modal })),
        surfaces: { sidebarShade: pseudo(scene.querySelector('.sidebar-panel'), '::before'), previewHeadingLine: pseudo(scene.querySelector('.reward-heading'), '::before'), dividerBefore: pseudo(scene.querySelector('.banner-rule'), '::before'), dividerAfter: pseudo(scene.querySelector('.banner-rule'), '::after') },
        assets: [...assetRows.values()]
    };
}

function validate(state, name) {
    const near = (actual, expected, label) => assert(Math.abs(actual - expected) < 0.03, label + ': ' + actual + ' vs ' + expected);
    const rect = (actual, expected, label) => ['x', 'y', 'width', 'height'].forEach((key, index) => near(actual[key], expected[index], label + '.' + key));
    assert.equal(state.state.scheme, 'r5');
    assert.equal(state.state.buttonPreview, name);
    rect(state.components.header.box, [35, 45, 1608, 74], 'header');
    rect(state.components.sidebar.box, [35, 123, 299, 746], 'sidebar');
    rect(state.components.mainPanel.box, [334, 123, 1309, 681], 'main');
    rect(state.components.footer.box, [334, 804, 1309, 65], 'footer');
    assert.equal(state.navigation.length, 4);
    assert.equal(state.preview.length, 4, 'Approved main-page selection has four cards; this is not the complete prize catalogue');
    rect(state.draw.single.button.box, [1115, 683, 220, 84], 'single');
    rect(state.draw.ten.button.box, [1355, 683, 244, 84], 'ten');
    for (const action of Object.values(state.draw)) {
        assert.equal(action.label.style.fontSize, '28px');
        assert.equal(action.label.style.lineHeight, '32px');
        assert.equal(action.cost.style.fontSize, '18px');
        assert.equal(action.cost.style.lineHeight, '26px');
        near(action.ticket.box.width, 52, 'ticket.width');
        near(action.ticket.box.height, 36, 'ticket.height');
        assert.equal(action.button.disabled, name === 'disabled');
        assert(!action.surface.style.backgroundImage.includes('data:'), 'Image data must be represented by a reference asset ID');
    }
    near(state.components.walletPlus.box.width, 44, 'plus.width');
    near(state.components.close.box.width, 44, 'close.width');
    assert(state.preview.every(card => card.icon.image.decoded));
}

async function captureReference() {
    process.chdir(repo);
    fs.mkdirSync(output, { recursive: true });
    const temp = path.join(output, 'tmp');
    fs.mkdirSync(temp, { recursive: true });
    process.env.TEMP = temp;
    process.env.TMP = temp;
    const original = fs.readFileSync(reference), sourceSha256 = sha(original);
    const report = {
        schemaVersion: 1, kind: 'approved_r5_html_reference', nativeGameVerified: false,
        generatedAt: new Date().toISOString(),
        source: { path: relative(reference), sha256: sourceSha256, bytes: original.length },
        coordinateSpace: { width: 1672, height: 941, origin: '#mainCanvas .lottery-scene top-left', unit: 'logical px; client rectangles divided by the rendered scene scale' },
        notes: [
            'Original approved HTML is opened directly and never rewritten.',
            'This document measures the approved reference, including its parked forest scene and removed T10 art; these are not instructions to reactivate either asset.',
            'Four main-page preview cards are a featured selection; complete prize details are independent.',
            'Hover and disabled are the approved emeraldReviewAPI preview states, not changes to a real game balance or controller.',
            'Embedded image bytes are represented by source IDs; no old output manifest is required.'
        ], states: {}, screenshots: []
    };
    let b;
    try {
        b = await browser();
        // This viewport accommodates the page's stage padding, border and
        // scrollbar at exactly 1:1, avoiding resampling in the reference PNG.
        await b.call('Emulation.setDeviceMetricsOverride', { width: 1725, height: 1200, deviceScaleFactor: 1, mobile: false });
        await b.go(reference, '?scheme=r5');
        assert(await b.run('Boolean(window.lotteryDemoAPI&&window.emeraldReviewAPI)'), 'Approved reference APIs are available');
        await b.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 1, y: 1 });
        for (const name of ['normal', 'hover', 'disabled']) {
            await b.run('lotteryDemoAPI.setScheme("r5");lotteryDemoAPI.setPool("map");emeraldReviewAPI.setButtonState(' + JSON.stringify(name) + ');lotteryDemoAPI.resize()');
            await b.run('document.fonts.ready.then(()=>Promise.all([...document.querySelectorAll("#mainCanvas img")].map(image=>image.decode().catch(()=>false)))).then(()=>true)');
            await sleep(220);
            const state = await b.run('(' + inspectScene.toString() + ')()');
            validate(state, name);
            assert.equal(state.scene.scaleX, 1, 'The approved page naturally renders at one logical pixel per browser pixel');
            report.states[name] = state;
            const bounds = state.scene.screenBox, file = path.join(output, name === 'normal' ? 'reference_stage.png' : 'reference_stage_' + name + '.png');
            const shot = await b.call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true, clip: { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height, scale: 1672 / bounds.width } });
            const png = Buffer.from(shot.data, 'base64');
            assert.equal(png.readUInt32BE(16), 1672, 'Reference capture is exported at the logical canvas width');
            assert.equal(png.readUInt32BE(20), 941, 'Reference capture is exported at the logical canvas height');
            fs.writeFileSync(file, png);
            report.screenshots.push({ state: name, path: relative(file), width: 1672, height: 941, sha256: sha(png) });
        }
        assert.equal(sha(fs.readFileSync(reference)), sourceSha256, 'Approved reference file remains unchanged');
        assert.notEqual(report.states.normal.draw.ten.surface.style.filter, report.states.hover.draw.ten.surface.style.filter, 'Hover changes the approved button material');
        assert.notEqual(report.states.normal.draw.ten.surface.style.filter, report.states.disabled.draw.ten.surface.style.filter, 'Disabled changes the approved button material');
        report.geometry = report.states.normal;
        report.success = true;
        fs.writeFileSync(path.join(output, 'reference_geometry.json'), JSON.stringify(report, null, 2) + '\n');
        return report;
    } finally {
        if (b) b.close();
    }
}

module.exports = { captureReference, inspectScene, validate };
if (require.main === module) {
    if (!process.argv.includes('--run')) {
        process.stdout.write('Usage: node tools/lottery_r5_parity_20261019/reference.cjs --run\n');
    } else {
        captureReference().then(report => {
            console.log('LOTTERY_R5_REFERENCE_PASS ' + JSON.stringify({ source: report.source.path, sourceSha256: report.source.sha256, coordinateSpace: [1672, 941], states: Object.keys(report.states), cards: report.geometry.preview.length, output: relative(path.join(output, 'reference_geometry.json')), screenshots: report.screenshots.map(row => row.path) }));
        }).catch(error => { console.error(error.stack || error); process.exitCode = 1; });
    }
}
