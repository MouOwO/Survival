'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {createHarness} = require('./fixtures/menus_v10_harness.cjs');
const {fixture} = require('../daily_gw2/fixture.cjs');
const project = path.resolve(__dirname, '../..');

// Real renderer, art registry, icon resolver, ModalShell/Fit and layer manager.
// Native Panel geometry is simulated: this verifies authored layout and resize
// behavior, not Panorama rasterization, font metrics or an actual Dota capture.
function descendants(panel) {
    return panel.Children().flatMap(child => [child, ...descendants(child)]);
}
function tagged(panel, cls) { return descendants(panel).filter(child => child.BHasClass(cls)); }
function quantities(panel) { return tagged(panel, 'DailyGW2Quantity').map(child => child.text); }
function auditAssets(data) {
    const audit = JSON.parse(fs.readFileSync(path.join(project,
        'design_refs/daily_stargold_integration_20261019/assets_fonts_audit.json'), 'utf8'));
    const verified = new Map(audit.assets.map(asset => [asset.uri, asset]));
    const hash = value => crypto.createHash('sha256').update(value).digest('hex');
    assert(verified.size >= 11, 'Installed official component sources have independent VPK hash evidence');
    for (const [key, asset] of Object.entries(data.assets)) {
        const original = verified.get(asset.file);
        assert(original, 'R5 uses a reviewed original official resource: ' + key);
        assert.equal(original.verifiedInstalledVPK, true);
        assert.equal(original.newTextureCompilationRequired, false);
        assert.match(original.sourceSha256, /^[a-f0-9]{64}$/);
        assert.deepEqual(Array.from(asset.size), [original.dimensions.width, original.dimensions.height]);
    }
    assert.equal(data.assets.reward_frame.file,
        's2r://panorama/images/events/international_2026/artwork/cell_border_png.vtex');
    assert.equal(data.assets.button.file, 's2r://panorama/images/dota_plus/relic_rare_button_psd.vtex',
        'Both daily actions use the newly selected official relic button family');
    assert.equal(data.assets.window_background, undefined, 'The external starfield is absent from the daily asset configuration');
    assert.equal(data.assets.button_fill, undefined, 'The superseded outlined monthly button fill is removed');
    assert.equal(data.assets.button_border, undefined, 'The superseded outlined monthly button border is removed');
    assert.equal(audit.fonts.length, 3);
    for (const font of audit.fonts) {
        assert.equal(hash(fs.readFileSync(path.join(project, font.path))), font.sha256,
            'The declared real font face matches its audited bytes: ' + font.path);
        assert([400, 500, 700].includes(font.weight));
    }
}
function box(panel, canvas) {
    const at = panel.GetPositionWithinWindow(), origin = canvas.GetPositionWithinWindow();
    return [at.x - origin.x, at.y - origin.y, parseFloat(panel.style.width), parseFloat(panel.style.height)];
}
function snapshot() {
    const official = fixture();
    const calendar28 = Array.from({length: 28}, (_, index) => ({
        day: index + 1, absolute_count: index + 1, is_today: index === 3 ? 1 : 0,
        status: index < 3 ? 'claimed' : index === 3 ? 'claimable' : 'not_open',
        rewards: official.rewards[index % 7].rewards.map(item => ({...item}))
    }));
    return {ok: true, sequence: 1, today: 25004, period_id: '0', count: 3,
        ordinary_status: 'claimable', pending: 0, has_pass: 0, purchase_enabled: 1,
        price: '20元', duration_days: 30, makeup_days: 30, missed: [25002],
        calendar28, calendar_current_day: 4, calendar_start_count: 0,
        cycle: calendar28.slice(0, 7), specials: official.specials.map(item => ({...item})),
        premium: {status: 'unconfigured'}, rule_text: '以正式配置及服务端快照为准'};
}

function dailyAccepted() {
    const h = createHarness(), {cfg, nodes} = h;
    for (const source of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js']) h.load(source);
    // The committed art catalog and the pending unified registry are both real
    // production resolvers. Do not require an unrelated registry migration.
    const itemResources = 'common/item_resources.js';
    if (fs.existsSync(path.join(project, 'panorama/src/scripts/custom_game', itemResources))) h.load(itemResources);
    for (const source of ['archive_theme_tokens.js', 'archive_parchment_data.js',
        'archive_handoff_180de7e38b.js', 'archive_v10_semantics.js', 'common/archive_tooltip.js',
        'reward_presentation.js', 'item_art_remaining_5d5c1152eb.js',
        'daily_gw2_data.js', 'daily_remaining_5d5c1152eb.js']) h.load(source);
    auditAssets(cfg.DailyGW2Data);
    // A formal reward falling back to the old generic crystal fails immediately.
    cfg.RemainingHandoff.DailyImage = () => assert.fail('A real daily reward must use the existing item art resolver');
    function standardScrim() {
        assert.equal(nodes.DailyScrim.style.backgroundColor, '#0000008c', 'Daily rewards use the standard translucent black modal scrim');
        assert.equal(nodes.DailyScrim.style.backgroundImage, 'none');
        assert.equal(descendants(h.root).filter(node => /^Daily.*(?:Scene|Dimmer)/i.test(node.id)).length, 0,
            'No separate starfield scene or dimmer is created outside the daily window');
    }
    standardScrim();
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'Initial loading does not automatically open daily rewards');
    cfg.SurvivalDaily.Open(false);
    assert.equal(nodes.DailyScrim.visible, true, 'Opening daily rewards shows the shared modal scrim');
    assert.equal(cfg.SurvivalDailyStargoldOpen, true);
    const canvas = nodes.DailyGW2Canvas;
    const dailyClose = nodes.DailyGW2Close;
    assert.deepEqual(box(dailyClose, canvas).slice(2), [30, 30], 'The close button keeps its compact square footprint');
    assert.equal(dailyClose.style.border, '1px solid #8c8c8c');
    assert.match(dailyClose.style.backgroundColor, /#737373.*#444444/, 'The close button uses its grey square backing');
    const dailyCloseIcon = dailyClose.Children().find(node => node.BHasClass('DailyGW2Art'));
    assert(dailyCloseIcon, 'The close button contains its official white cross');
    assert.equal(dailyCloseIcon.style.backgroundImage, 'url("s2r://panorama/images/control_icons/close_png.vtex")');
    assert.deepEqual(box(dailyCloseIcon, dailyClose), [5, 5, 20, 20], 'The cross is centered inside the square button');
    assert.equal(Number(dailyCloseIcon.style.opacity), 1, 'The close cross stays fully opaque');
    assert.equal(dailyClose.hittestchildren, false, 'The cross cannot intercept close-button activation');
    assert.deepEqual([parseFloat(canvas.style.width), parseFloat(canvas.style.height)], [1360, 844]);
    assert.equal(nodes.DailyGW2Title.text, '每日登录奖励');
    assert.deepEqual(Array.from({length: 7}, (_, index) => nodes['DailyGW2Weekday_' + index].text),
        ['Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ', 'Ⅵ', 'Ⅶ']);
    assert.equal(nodes.DailyCards.GetChildCount(), 28);
    assert.equal(nodes.DailySpecials.GetChildCount(), 0, 'Loading does not draw unconfigured monthly reward frames');
    assert.equal(tagged(nodes.DailyCards, 'DailyGW2ItemArt').length, 0, 'Loading does not invent rewards');

    function textQuality() {
        assert.equal(nodes.DailyGW2Title.style.fontFamily, '"Source Han Sans SC"');
        assert.equal(nodes.DailyGW2Title.style.fontWeight, 'medium',
            'The title selects the native-reviewed bundled Medium face instead of synthesizing a missing weight');
        for (const text of tagged(canvas, 'DailyGW2Text')) {
            assert(parseFloat(text.style.fontSize) >= 18, 'Meaningful Chinese text stays at the native-reviewed minimum authored size of 18px');
            if (!text.BHasClass('DailyGW2DateNumber'))
                assert.equal(text.style.textShadow, 'none', 'Ordinary daily text is rendered without a diffuse shadow');
            assert.notEqual(text.style.textOverflow, 'shrink', 'Fitting a label cannot silently reduce its authored font size');
        }
        const stylesheet = fs.readFileSync(path.join(project, 'panorama/src/styles/custom_game/daily_gw2.css'), 'utf8');
        for (const rule of stylesheet.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
            for (const declaration of rule[2].matchAll(/text-shadow\s*:\s*([^;}]+)/g)) {
                if (declaration[1].trim() === 'none') continue;
                assert(rule[1].split(',').every(selector => selector.includes('.DailyGW2DateNumber')),
                    'Only the dedicated date-number class may have a black text edge');
            }
        }
    }

    function noEmptyMonthlySlots() {
        assert(!nodes.DailyGW2SpecialEmpty_4, 'No fourth empty frame is generated');
        assert.equal(tagged(nodes.DailySpecials, 'DailyGW2SpecialEmpty').length, 0,
            'Every visible monthly frame represents a configured reward');
    }
    function geometry() {
        const columns = [46, 189, 331, 474, 616, 759, 901], rows = [193, 329, 465, 600];
        const overlaps = (a, b) => a[0] < b[0] + b[2] && b[0] < a[0] + a[2] &&
            a[1] < b[1] + b[3] && b[1] < a[1] + a[3];
        for (let column = 0; column < 7; column++) {
            const heading = nodes['DailyGW2Weekday_' + column], headingBounds = box(heading, canvas);
            assert.equal(parseFloat(heading.style.fontSize), 54, 'Roman column headings are three times their original 18px size');
            assert(headingBounds[3] >= 54 && headingBounds[2] >= 54, 'The heading box accommodates the enlarged glyph without shrinking');
            const firstFrame = tagged(nodes['DailyGW2Day_' + (column + 1)], 'DailyGW2RewardFrame')[0];
            assert(headingBounds[1] + headingBounds[3] <= box(firstFrame, canvas)[1],
                'Enlarged Roman headings stop above the first row of visible reward frames');
            for (const id of ['DailyGW2CalendarHeader', 'DailyCount']) {
                const label = nodes[id];
                if (label.visible !== false && label.text) assert(!overlaps(headingBounds, box(label, canvas)),
                    'Enlarged Roman headings do not overlap the daily heading or progress caption');
            }
        }
        for (let index = 0; index < 28; index++) {
            const day = nodes['DailyGW2Day_' + (index + 1)];
            assert.deepEqual(box(day, canvas), [columns[index % 7], rows[Math.floor(index / 7)], 131, 124]);
            const frame = tagged(day, 'DailyGW2RewardFrame')[0];
            assert.equal(frame.style.backgroundImage, 'none',
                'Ordinary reward frames have no clipped corner artwork');
            assert.equal(frame.style.border, '0px', 'Ordinary reward frames have no extra outer outline, including today');
            assert.equal(frame.style.backgroundColor, 'transparent', 'Ordinary reward frames do not add a backing plate');
            assert.equal(frame.style.boxShadow, 'none', 'Ordinary reward frames have no outer shadow');
            assert.deepEqual(box(frame, day), [0, 23, 131, 101]);
            const dateNumbers = tagged(day, 'DailyGW2DateNumber');
            assert.equal(dateNumbers.length, 1, 'Every daily card has one dedicated Arabic date number');
            const date = dateNumbers[0];
            assert.equal(date.text, String(index + 1), 'Daily dates contain only the Arabic numbers 1–28');
            assert(parseFloat(date.style.fontSize) >= 24, 'The date number is visibly larger than ordinary captions');
            assert(['medium', 'bold'].includes(date.style.fontWeight), 'Date numbers use a real emphasized font face');
            const dateBounds = box(date, frame), frameBounds = box(frame, day);
            assert(dateBounds[0] >= 1 && dateBounds[1] >= 1 &&
                dateBounds[0] <= 20 && dateBounds[1] <= 20 &&
                dateBounds[0] + dateBounds[2] <= frameBounds[2] &&
                dateBounds[1] + dateBounds[3] <= frameBounds[3],
                'The large Arabic date sits inside the reward icon upper-left corner rather than above its frame');
            const edge = date.style.textShadow && date.style.textShadow !== 'none' ? date.style.textShadow : date.style.textOutline;
            assert.match(edge, /(?:#000000(?:[0-9a-f]{2})?|#000|\bblack\b)(?=\s|$)/i,
                'The date number has a black outline or sharp black text shadow');
            const edgePixels = [...edge.matchAll(/(-?\d+(?:\.\d+)?)px/g)].map(match => Number(match[1]));
            if (edge === date.style.textShadow) {
                assert(edgePixels.length >= 3 && edgePixels[2] >= 0 && edgePixels[2] <= 1,
                    'The date edge stays sharp instead of using a diffuse glow');
            }
            assert(descendants(day).filter(node => node.paneltype === 'Label').every(label => !/第|天|今日/.test(label.text)),
                'The old 第X天 and 今日 captions are absent from the reward card');
            for (const reward of tagged(day, 'DailyGW2Reward')) {
                const slot = box(reward, day);
                assert.deepEqual(slot, [2, 25, 127, 97], 'The quality background fills the complete gold frame interior');
            }
            for (const mark of [...tagged(day, 'DailyGW2Lock'), ...tagged(day, 'DailyGW2Check')]) {
                assert.equal(mark.GetParent(), day, 'Ordinary daily marks keep their existing parent');
                assert.deepEqual(box(mark, day), [106, 30, 15, 15], 'Moving monthly marks does not change ordinary daily positions');
            }
        }
        const monthCount = nodes.DailySpecials.GetChildCount();
        nodes.DailySpecials.Children().forEach((special, index) => {
            const bounds = box(special, canvas);
            assert.equal(bounds[0], 1082);
            assert.equal(bounds[2], 222);
            if (monthCount <= 3) assert.deepEqual(bounds, [1082, [193, 374, 555][index], 222, 169]);
            else {
                assert(bounds[1] >= 193 && bounds[1] + bounds[3] <= 724,
                    'A real fourth milestone is fitted into the configured monthly reward region');
                if (index) {
                    const previous = box(nodes.DailySpecials.Children()[index - 1], canvas);
                    assert(previous[1] + previous[3] <= bounds[1], 'Real monthly entries never overlap');
                }
            }
            const iconFrame = tagged(special, 'DailyGW2MonthlyIconFrame');
            assert.equal(iconFrame.length, 1, 'Monthly cards have one dedicated image frame separate from their text');
            const iconSize = Math.min(100, bounds[3] - 70);
            assert.deepEqual(box(iconFrame[0], special), [Math.round((222 - iconSize) / 2), 35, iconSize, iconSize]);
            const frames = tagged(special, 'DailyGW2SpecialFrame');
            assert.equal(frames.length, 1, 'Each monthly item has one decorative icon frame');
            const frame = frames[0];
            assert.equal(frame.GetParent(), iconFrame[0], 'The decorative corners belong to the item icon rather than the surrounding text card');
            assert.deepEqual(box(frame, iconFrame[0]), [0, 0, iconSize, iconSize]);
            assert.deepEqual(box(frame, special), box(iconFrame[0], special),
                'All four decorative corners align with the actual icon at three and four milestone sizes');
            assert.equal(special.Children().filter(node => node.BHasClass('DailyGW2SpecialFrame')).length, 0,
                'The full 222px monthly text card has no stretched decorative frame');
            assert(frame.style.backgroundImage.includes(cfg.DailyGW2Data.assets.premium_frame.file));
            assert.match(frame.style.border, /^1px solid /);
            assert.equal(frame.style.backgroundColor, 'transparent', 'The foreground corner decoration has no opaque plate hiding the item');
            assert.equal(Number(frame.style.zIndex), 2, 'The corner decoration is a foreground layer above the item slot');
            assert.equal(frame.hittest, false, 'Foreground corner decorations cannot swallow item hover');
            assert.equal(iconFrame[0].style.border, '0px', 'Only the aligned decorative frame draws the icon outer border');
            const imageSlot = tagged(special, 'DailyGW2PassReward');
            assert.equal(imageSlot.length, 1);
            assert.deepEqual(box(imageSlot[0], iconFrame[0]), [1, 1, iconSize - 2, iconSize - 2],
                'Monthly artwork fills only its image frame, leaving the eligibility and item name visible');
            if (index === 0) {
                const stylesheet = fs.readFileSync(path.join(project, 'panorama/src/styles/custom_game/daily_gw2.css'), 'utf8');
                assert.match(stylesheet, /\.DailyGW2PassReward\s*\{[^}]*z-index\s*:\s*1\s*;/,
                    'The full quality-and-art slot remains below its foreground decorative corners');
            }
            for (const mark of [...tagged(special, 'DailyGW2Lock'), ...tagged(special, 'DailyGW2Check')]) {
                assert.equal(mark.GetParent(), iconFrame[0], 'Monthly locks and ownership marks stay attached to the icon');
                const markBounds = box(mark, iconFrame[0]);
                assert.equal(markBounds[0] + markBounds[2], iconSize - 8, 'The marker keeps an eight-pixel inset from the icon right edge');
                assert.equal(markBounds[1], 8, 'The marker sits at the icon upper-right corner');
                assert(markBounds[0] >= 0 && markBounds[1] + markBounds[3] <= iconSize,
                    'Locks and ownership marks stay within both large and compact monthly icons');
            }
            const captions = special.Children().filter(node => node.paneltype === 'Label');
            assert.equal(captions.length, 2, 'Eligibility and item-name captions remain outside the icon container');
            assert(box(captions[0], special)[1] + box(captions[0], special)[3] <= 35,
                'The eligibility caption stays above the icon corners');
            assert(box(captions[1], special)[1] >= 35 + iconSize,
                'The item name stays below the icon corners');
        });
        const purchase = box(nodes.PassPurchase, canvas);
        assert.deepEqual(purchase, [1081, 736, 224, 52]);
        assert.deepEqual(box(nodes.DailyClaim, canvas), [411, 730, 256, 64]);
        for (const button of [nodes.DailyClaim, nodes.PassPurchase]) {
            assert(button.style.backgroundImage.includes(cfg.DailyGW2Data.assets.button.file));
            assert.equal(button.style.backgroundSize, 'cover', 'Both main actions use the same filled official gold button family');
            for (const label of button.Children().filter(node => node.paneltype === 'Label')) {
                assert(parseFloat(label.style.fontSize) >= 18);
                assert.equal(label.style.textShadow, 'none');
                assert.notEqual(label.style.textOverflow, 'shrink');
                if (button.enabled !== false) assert.equal(label.style.color, '#241b0c', 'Enabled gold actions use legible dark text');
            }
        }
        assert.equal(411 + 256 / 2, (columns[0] + columns[6] + 131) / 2,
            'The primary claim button stays independently centered below the calendar');
        assert(purchase[1] + purchase[3] <= 844, 'Purchase button remains inside the canvas');
        assert.equal(nodes.DailySubtitle.visible, false);
        assert.equal(nodes.DailySubtitle.style.visibility, 'collapse');
        assert.equal(nodes.DailySubtitle.text, '');
        assert.equal(nodes.DailySubtitle.style.height, '0px');
        assert(!nodes.DailyWindow.style.opacity || Number(nodes.DailyWindow.style.opacity) === 1,
            'Background transparency cannot fade all text, icons and states');
        noEmptyMonthlySlots();
        textQuality();
        standardScrim();
        for (const card of [...nodes.DailyCards.Children(), ...nodes.DailySpecials.Children()]) {
            const slots = [...tagged(card, 'DailyGW2Reward'), ...tagged(card, 'DailyGW2PassReward')];
            if (!slots.length) continue;
            assert.equal(slots.length, 1, 'Each reward card has one representative image even when the server awards multiple items');
            for (let i = 0; i < slots.length; i++) {
                const icon = tagged(slots[i], 'DailyGW2ItemArt')[0];
                assert(icon, 'Every configured reward card has one actual shared item image');
                const slot = slots[i], slotBounds = box(slot, card), artBounds = box(icon, slot);
                if (card.BHasClass('DailyGW2Day')) assert.deepEqual(slotBounds, [2, 25, 127, 97],
                    'The daily quality background fills the gold frame interior');
                else {
                    const size = Math.min(100, parseFloat(card.style.height) - 70);
                    assert.deepEqual(slotBounds, [Math.round((222 - size) / 2) + 1, 36, size - 2, size - 2],
                        'The monthly quality background fills its square frame without covering surrounding text');
                }
                assert.match(slot.style.backgroundImage, /econ\/tools\/ti10_seasonal_item_background\.png/,
                    'The full slot uses the same official quality backdrop as the shared item catalog');
                assert.equal(slot.style.backgroundSize, '100% 100%');
                assert.match(slot.style.backgroundColor, /^gradient\(/, 'The background retains an actual server-item quality tint');
                assert(slot.__survivalItemGrade, 'The quality is applied to the full-size slot rather than the smaller picture');
                assert(artBounds[0] >= 4 && artBounds[1] >= 4 &&
                    artBounds[0] + artBounds[2] <= slotBounds[2] - 4 &&
                    artBounds[1] + artBounds[3] <= slotBounds[3] - 4,
                    'The smaller item body leaves visible quality background on every side');
                assert(artBounds[2] * artBounds[3] < slotBounds[2] * slotBounds[3] * .9,
                    'The item body remains visibly smaller than its full-size quality backdrop');
                assert.equal(icon.scaling, 'stretch-to-fit-preserve-aspect',
                    'The separate item body stays complete without cover cropping');
                assert.equal(icon.style.backgroundImage, 'none', 'A shared FillIcon call cannot reattach a second backdrop to the item body');
                assert.equal(icon.style.backgroundColor, 'transparent');
                assert.equal(icon.style.border, '0px');
            }
        }
    }
    geometry();

    let current = snapshot();
    function send(changes = {}) {
        current = {...current, ...changes, sequence: current.sequence + 1};
        h.emit('survival_daily_snapshot', current);
    }
    send();
    assert.equal(nodes.DailySpecials.GetChildCount(), 3, 'The formal three milestones produce exactly three frames');
    assert.equal(cfg.SurvivalDaily.Inspect().monthlySlots, 3);
    geometry();
    function realIcon(parent, id) {
        const expected = cfg.SurvivalItemResources ? cfg.SurvivalItemResources.Lookup({id}) : cfg.SurvivalItemArt.Lookup({id});
        const uri = expected && (expected.uri || expected.runtime_uri || (expected.icon_path && 'file://{images}/' + expected.icon_path));
        assert(uri, 'Formal CSV reward has an actual shared image resource: ' + id);
        assert(tagged(parent, 'DailyGW2ItemArt').some(icon => icon.image === uri),
            'Rendered image follows the shared reward ID, not the concept artwork: ' + id);
    }
    for (let index = 0; index < 28; index++) {
        const day = nodes['DailyGW2Day_' + (index + 1)];
        const rewards = current.calendar28[index].rewards;
        assert.equal(tagged(day, 'DailyGW2Reward').length, rewards.length ? 1 : 0);
        assert.equal(tagged(day, 'DailyGW2ItemArt').length, rewards.length ? 1 : 0,
            'A multi-item server reward still displays only its first item image');
        if (rewards.length) {
            realIcon(day, rewards[0].id);
            assert.equal(tagged(day, 'DailyGW2Reward')[0].__survivalItemGrade,
                cfg.SurvivalItemResources.Grade(rewards[0]), 'The full slot uses its representative server item quality');
        }
        tagged(day, 'DailyGW2Reward').forEach(slot => assert.equal(slot.hittest, false,
            'The whole day owns the complete tooltip instead of an individual item swallowing hover'));
        assert.equal(tagged(day, 'DailyGW2RewardKinds').length, 0, 'Reward-kind badges never cover the reward art');
        rewards.forEach(reward => {
            assert(day.__dailyGW2Tooltip.body.includes(reward.name + ' ×' + reward.count), 'Full reward name and quantity remain available');
            assert(day.__dailyGW2Tooltip.body.includes(reward.description), 'The second reward effect is retained');
        });
    }
    current.specials.forEach(item => {
        const card = nodes['DailyGW2Special_' + item.id];
        realIcon(card, item.id);
        assert.equal(tagged(card, 'DailyGW2PassReward')[0].__survivalItemGrade,
            cfg.SurvivalItemResources.Grade(item), 'Monthly slot quality follows the shared item registry');
        assert.deepEqual(quantities(card), [], 'Missing monthly count is not replaced with 1');
        assert.equal(tagged(card, 'DailyGW2Lock').length, 1);
    });
    assert.equal(tagged(nodes.DailyCards, 'DailyGW2Check').length, 3);

    const formalSpecials = current.specials.slice(), unchangedMonthlyCards = nodes.DailySpecials.Children().slice();
    send();
    assert.deepEqual(nodes.DailySpecials.Children(), unchangedMonthlyCards, 'Unchanged three-reward snapshots reuse monthly cards');
    // Branch fixture only: a future server may schedule this existing formal
    // daily resource as a fourth milestone. No CSV or production reward changes.
    const fourth = {...current.calendar28[0].rewards[0], day: 28, owned: 0};
    send({specials: formalSpecials.concat(fourth)});
    assert.equal(nodes.DailySpecials.GetChildCount(), 4, 'A real fourth server item appears instead of being discarded');
    assert.equal(cfg.SurvivalDaily.Inspect().monthlySlots, 4);
    const fourthCard = nodes['DailyGW2Special_' + fourth.id];
    realIcon(fourthCard, fourth.id);
    assert(fourthCard.BHasClass('DailyGW2Locked'));
    fourthCard.events.onmouseover();
    h.flushFinite();
    assert(nodes.DailyGW2Tooltip.visible);
    assert.equal(nodes.DailyGW2TooltipTitle.text, fourth.name);
    const fourthText = nodes.DailyGW2TooltipEffect.text.replace(/<br\s*\/?\s*>/gi, '\n').replace(/<[^>]*>/g, '');
    assert(fourthText.includes(fourth.description));
    assert(fourthText.includes('累计签到28次'));
    geometry();
    send();
    assert.equal(nodes['DailyGW2Special_' + fourth.id], fourthCard, 'Unchanged four-reward snapshots reuse the fourth card');
    send({specials: formalSpecials});
    assert.equal(nodes.DailySpecials.GetChildCount(), 3, 'Removing the fourth server item removes its frame');
    assert(!fourthCard.IsValid());
    assert(!nodes.DailyGW2Tooltip.visible, 'Removing a hovered fourth item retires its description');
    assert.equal(cfg.SurvivalDaily.Inspect().monthlySlots, 3);
    const restoredMonthlyCards = nodes.DailySpecials.Children().slice();
    send();
    assert.deepEqual(nodes.DailySpecials.Children(), restoredMonthlyCards, 'The restored three-reward state remains cached');
    assert(restoredMonthlyCards.every(card => card.BHasClass('DailyGW2Locked')));
    geometry();

    const ordinaryDays = current.calendar28, oldQualityCard = nodes.DailyGW2Day_1;
    const oldQualitySlot = tagged(oldQualityCard, 'DailyGW2Reward')[0];
    const oldColor = oldQualitySlot.style.backgroundColor;
    const oldImage = tagged(oldQualityCard, 'DailyGW2ItemArt')[0].image;
    const newQualityDays = ordinaryDays.map(day => ({...day, rewards:day.rewards.map(item => ({...item}))}));
    newQualityDays[0].rewards[0].quality = 'UR';
    send({calendar28:newQualityDays});
    const newQualitySlot = tagged(nodes.DailyGW2Day_1, 'DailyGW2Reward')[0];
    assert.equal(newQualitySlot.__survivalItemGrade, 'UR', 'A changed authoritative rarity updates the full background');
    assert.notEqual(newQualitySlot.style.backgroundColor, oldColor);
    assert.equal(tagged(nodes.DailyGW2Day_1, 'DailyGW2ItemArt')[0].image, oldImage,
        'Changing rarity keeps the same shared item picture and changes only its backdrop');
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), [String(newQualityDays[0].rewards[0].count)]);
    geometry();
    send({calendar28:ordinaryDays});
    assert.equal(tagged(nodes.DailyGW2Day_1, 'DailyGW2Reward')[0].__survivalItemGrade, 'R');

    const changedDays = current.calendar28.map(day => ({...day, rewards: day.rewards.map(item => ({...item}))}));
    changedDays[0].rewards[0].count = 17;
    changedDays[4].rewards[0].count = 17;
    changedDays[4].rewards[1].count = 123;
    changedDays[3].status = 'claimed';
    const changedSpecials = current.specials.map((item, index) => ({...item, owned: index === 0 ? 9 : 0}));
    send({calendar28: changedDays, specials: changedSpecials, count: 4, ordinary_status: 'claimed', has_pass: 1});
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), ['17']);
    assert.deepEqual(quantities(nodes.DailyGW2Day_5), ['17'], 'The icon count belongs only to the visible representative item');
    assert(nodes.DailyGW2Day_5.__dailyGW2Tooltip.body.includes(changedDays[4].rewards[0].name + ' ×17'));
    assert(nodes.DailyGW2Day_5.__dailyGW2Tooltip.body.includes(changedDays[4].rewards[1].name + ' ×123'), 'Unequal second-item quantities are not hidden, summed or replaced');
    assert.equal(tagged(nodes.DailyCards, 'DailyGW2Check').length, 4);
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Lock').length, 0);
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Check').length, 1);
    assert.deepEqual(quantities(nodes.DailyGW2Special_daily_wealth_talisman), [], 'Owned 9 is not an award quantity');
    geometry();

    const finalDays = changedDays.map(day => ({...day, rewards: day.rewards.map(item => ({...item}))}));
    const replacement = {...finalDays[1].rewards[0], count: 123};
    finalDays[0].rewards = [replacement];
    send({calendar28: finalDays, has_pass: 0,
        specials: changedSpecials.map((item, index) => index === 1 ? {...item, count: 7} : item)});
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), ['123']);
    realIcon(nodes.DailyGW2Day_1, replacement.id);
    assert.deepEqual(quantities(nodes.DailyGW2Special_daily_ancient_tree), ['7'], 'An explicit server quantity is shown');
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Lock').length, 2, 'Expired pass relocks only unowned formal rewards');
    assert.equal(tagged(nodes.DailySpecials, 'DailyGW2Check').length, 1);
    geometry();

    send({pending: 1, ordinary_status: 'claimable', has_pass: 1});
    const pendingRequests = h.sent.length;
    for (const id of ['DailyClaim', 'DailyMakeup', 'PassPurchase']) {
        assert.equal(nodes[id].enabled, false, 'Server pending disables ' + id);
        nodes[id].events.onactivate();
    }
    assert.equal(h.sent.length, pendingRequests, 'Server pending blocks claim, makeup and purchase callbacks');
    send({pending: 0, ordinary_status: 'claimed'});

    const before = h.sent.length;
    const originalCards = nodes.DailyCards.Children().slice();
    // Exercise the actual shared Fit and its scheduled open-window resize path.
    for (const [width, height] of [[1280, 720], [1600, 1000], [2560, 1080]]) {
        h.root.style.width = width + 'px'; h.root.style.height = height + 'px';
        h.flushFinite();
        const transform = nodes.DailyWindow.style.transform;
        const scale = transform === 'none' ? 1 : Number(transform.match(/^scale3d\(([^,]+)/)?.[1]);
        assert(scale > 0 && scale * 1360 <= width + 0.01 && scale * 844 <= height + 0.01,
            'Shared resize keeps the authored canvas inside the simulated viewport');
        if (width >= 1600 && height >= 900) assert.equal(transform, 'none',
            'A viewport large enough for the design does not resample all text with an unnecessary transform');
        assert.deepEqual(nodes.DailyCards.Children(), originalCards, 'Resize does not rebuild reward content');
        geometry();
    }
    assert.equal(h.sent.length, before, 'Resize does not submit rewards or purchases');
    assert.equal(cfg.SurvivalUILayers.Top(), 'daily_rewards');
    nodes.DailyWindow.handlers.Cancelled();
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'Real layer-manager Escape path closes the page');
    assert.equal(nodes.DailyScrim.visible, false, 'Escape also hides the shared scrim');
    assert.equal(cfg.SurvivalDailyStargoldOpen, false);
    cfg.SurvivalDaily.Open(false);
    assert.equal(nodes.DailyScrim.visible, true, 'Reopening restores the shared translucent scrim');
    geometry();
    assert.deepEqual(quantities(nodes.DailyGW2Day_1), ['123'], 'Reopening retains the latest real snapshot values');
    nodes.DailyScrim.events.onactivate();
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'Real shared outside-click path still closes');
    assert.equal(nodes.DailyScrim.visible, false, 'Closing by the shared outside-click path hides the scrim');
    assert(!h.sent.some(row => /claim|purchase|payment/.test(row.name)), 'This visual regression sends only view requests');
    cfg.SurvivalDaily.Dispose();
    assert.equal(nodes.DailyGW2SceneBackdrop, undefined);
    assert.equal(nodes.DailyScrim.visible, false, 'Dispose leaves the shared scrim hidden');
    assert.equal(cfg.SurvivalDailyStargoldOpen, false);
    console.log('DAILY_ACCEPTED_LAYOUT_PASS: real JS/shared UI in simulated Panorama, 28 daily slots, configured 0/3/4 monthly frames, real fourth-item icon/tooltip, 4-to-3 retirement/cache, dynamic counts/states, resize and reopen; native rendering unverified');
}

function dailyStargoldReload() {
    const h = createHarness(), {cfg, nodes} = h;
    for (const source of ['common/ui_registry.js', 'common/ui_components.js', 'ui_layers.js',
        'archive_theme_tokens.js', 'archive_parchment_data.js', 'archive_handoff_180de7e38b.js',
        'archive_v10_semantics.js', 'common/archive_tooltip.js', 'daily_gw2_data.js',
        'daily_remaining_5d5c1152eb.js']) h.load(source);
    const independentSceneCount = () => descendants(h.root).filter(node => /^Daily.*(?:Scene|Dimmer)/i.test(node.id)).length;
    const scrim = nodes.DailyScrim;
    h.flushFinite();
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'A cold include cannot reopen a page the user never opened');
    assert.equal(independentSceneCount(), 0, 'A cold include creates no independent external starfield');
    assert.equal(scrim.style.backgroundColor, '#0000008c');

    cfg.SurvivalDaily.Open(false);
    assert.equal(scrim.visible, true);
    const retired = cfg.SurvivalDaily;
    h.load('daily_remaining_5d5c1152eb.js');
    const replacement = cfg.SurvivalDaily;
    assert.notEqual(replacement, retired);
    assert.equal(nodes.DailyScrim, scrim, 'Hot reload retains the shared XML modal scrim');
    assert.equal(independentSceneCount(), 0, 'Hot reload cannot leave or recreate an external scene backdrop');
    h.flushFinite();
    assert.equal(replacement.Inspect().open, true, 'Hot reload restores a page the user had opened');
    assert.equal(scrim.visible, true);
    assert.equal(scrim.style.backgroundColor, '#0000008c');
    assert.equal(cfg.SurvivalDailyStargoldOpen, true);
    assert.equal(cfg.SurvivalUILayers.Top(), 'daily_rewards');

    const requestCount = h.sent.length;
    retired.Close(); retired.Open(true); retired.Dispose();
    assert.equal(h.sent.length, requestCount, 'Retired lifecycle callbacks send no new view or transaction request');
    assert.equal(replacement.Inspect().open, true);
    assert.equal(scrim.visible, true);
    assert.equal(cfg.SurvivalDailyStargoldOpen, true, 'A retired controller cannot erase the current open-state marker');

    replacement.Close();
    assert.equal(scrim.visible, false);
    assert.equal(cfg.SurvivalDailyStargoldOpen, false);
    h.load('daily_remaining_5d5c1152eb.js');
    h.flushFinite();
    assert.equal(independentSceneCount(), 0);
    assert.equal(cfg.SurvivalDaily.Inspect().open, false, 'Reloading after an explicit close leaves daily rewards closed');
    assert.equal(scrim.visible, false);
    cfg.SurvivalDaily.Open(false);
    cfg.SurvivalDaily.Dispose();
    assert.equal(scrim.visible, false, 'Disposing while open hides the shared scrim');
    assert.equal(independentSceneCount(), 0);
    assert.equal(cfg.SurvivalDailyStargoldOpen, false);
    assert(!h.sent.some(row => /claim|purchase|payment/.test(row.name)), 'Lifecycle restoration cannot grant or buy rewards');
    console.log('DAILY_STARGOLD_RELOAD_PASS: cold include stays closed; standard translucent scrim with no external starfield; open reload and retired callbacks preserve state; explicit close survives reload; Dispose hides scrim');
}

module.exports = {dailyAccepted, dailyStargoldReload};
if (require.main === module) { dailyAccepted(); dailyStargoldReload(); }
