'use strict';

const assert = require('node:assert/strict');
const {harness} = require('./treasure_compact.test.cjs');

// Use the actual treasure controller, XML, ModalShell, layer manager and native
// tooltip positioner together. Only the engine-created tooltip branch is a stub.
function fixture() {
    let nativeBranch, nativeContainer, nativeTooltip, otherOwner;
    const h = harness(({root, Panel}) => {
        nativeBranch = new Panel('Panel', root.GetParent(), 'NativeHudBranch');
        nativeBranch.style.zIndex = '7';
        nativeContainer = new Panel('Panel', nativeBranch, 'NativeTooltipContainer');
        nativeContainer.style.zIndex = '11';
        nativeTooltip = new Panel('Panel', nativeContainer, 'Tooltips');
        nativeTooltip.style.zIndex = '13';
        otherOwner = new Panel('Panel', root.GetParent(), 'OtherTooltipOwner');
    });
    const ui = h.cfg.SurvivalTreasure;
    h.net('0', {history: [
        {name: '宝物甲', description: '攻击提高', quantity: 3},
        {name: '宝物乙', description: '护甲提高'},
    ]});
    ui.Open();
    // SurvivalHUD owns this script in the game. Load it after treasure opens to
    // verify the controller resolves the shared API when the hover actually runs.
    h.load('tooltip_position.js');
    const api = h.cfg.SurvivalTooltipPosition;
    function cards() { return h.nodes.TreasureCards.Children(); }
    function front(source) {
        const state = api.InspectTextLayer();
        assert.equal(state.source, source.id);
        assert.equal(state.host, 'Tooltips');
        assert.equal(state.raised, 3, 'the complete separate native branch is leased');
        for (const panel of [nativeTooltip, nativeContainer, nativeBranch]) {
            assert(Number(panel.style.zIndex) > Number(h.nodes.TreasureWindow.style.zIndex),
                panel.id + ' must overtake the treasure window');
            if (ui.IsOpen()) assert(Number(panel.style.zIndex) > Number(h.root.style.zIndex),
                panel.id + ' must overtake the modal ancestor, not merely its leaf');
        }
        assert.strictEqual(nativeTooltip.GetParent(), nativeContainer);
        assert.strictEqual(nativeContainer.GetParent(), nativeBranch);
        assert.strictEqual(nativeBranch.GetParent(), h.hud, 'native hierarchy is retained');
    }
    function restored() {
        assert.equal(api.InspectTextLayer().source, '');
        assert.equal(api.InspectTextLayer().raised, 0);
        assert.equal(nativeBranch.style.zIndex, '7');
        assert.equal(nativeContainer.style.zIndex, '11');
        assert.equal(nativeTooltip.style.zIndex, '13');
    }
    return {...h, ui, api, otherOwner, cards, front, restored};
}

function treasureTooltipLayer() {
    {
        const h = fixture(), [first, second] = h.cards();
        first.events.onmouseover(); h.front(first);
        assert.equal(h.dispatched.at(-1)[0], 'DOTAShowTextTooltip');
        assert.strictEqual(h.dispatched.at(-1)[1], first, 'the real item remains the native anchor');
        assert.equal(h.dispatched.at(-1)[2], '宝物甲\n攻击提高\n拥有数量：3');

        // Both hovers happen before the engine's next-frame tooltip attachment.
        second.events.onmouseover(); h.front(second);
        const dispatches = h.dispatched.length;
        first.events.onmouseout();
        assert.equal(h.dispatched.length, dispatches, 'a delayed leave cannot dismiss the new item');
        h.advance(0); h.front(second);
        assert(second.BHasClass('TreasureHovered'));
        assert(!first.BHasClass('TreasureHovered'));
        second.events.onmouseout(); h.restored();
        assert.equal(h.dispatched.at(-1)[0], 'DOTAHideTextTooltip');
        assert(h.ui.IsOpen(), 'tooltip dismissal leaves the treasure drawer open');

        first.events.onmouseover(); h.front(first);
        h.net('0', {history: [{name: '新宝物', description: '生命提高'}]});
        h.restored();
        assert(!first.IsValid(), 'a local snapshot rebuild retires the previous anchor');
        const current = h.cards()[0]; current.events.onmouseover();
        first.events.onmouseout(); h.advance(0); h.front(current);
        h.ui.Close(); h.restored(); h.advance(0); h.restored();
        assert.equal(h.cfg.SurvivalUILayers.Top(), null);
        assert.equal(h.root.style.zIndex, '0', 'closing restores the actual modal ancestor baseline');

        h.ui.Open(); h.cards()[0].events.onmouseover(); h.front(h.cards()[0]);
        h.ui.Dispose(); h.restored(); h.advance(0); h.restored();
        assert.equal(h.listeners.size, 0);
        assert.equal(h.timers.size, 0, 'close/disposal leaves no delayed tooltip resurrection');
    }

    {
        const h = fixture(), first = h.cards()[0];
        first.events.onmouseover();
        h.api.ShowText(h.otherOwner, '其他界面的提示'); h.front(h.otherOwner);
        first.events.onmouseout(); h.advance(0); h.front(h.otherOwner);
        assert.equal(h.dispatched.at(-1)[2], '其他界面的提示',
            'treasure leave cannot issue a global native hide for a different owner');

        first.events.onmouseover(); h.front(first);
        h.api.ShowText(h.otherOwner, '保留其他提示');
        h.ui.Close(); h.advance(0); h.front(h.otherOwner);
        assert.equal(h.dispatched.at(-1)[2], '保留其他提示',
            'closing the drawer preserves a replacement tooltip owned elsewhere');
        h.api.HideText(h.otherOwner); h.restored();
        h.ui.Dispose(); h.advance(0);
        assert.equal(h.timers.size, 0);
        assert.equal(h.sent.length, 0, 'read-only treasure inspection never submits rewards');
    }

    console.log('TREASURE_TOOLTIP_LAYER_PASS: real controller/XML/ModalShell/positioner, complete native ancestor lease, rapid source changes, snapshot/close/disposal restoration and independent tooltip ownership');
}

module.exports = {treasureTooltipLayer};
if (require.main === module) treasureTooltipLayer();
