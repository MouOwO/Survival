'use strict';
// Exercise the real native error/tooltip lease against separate HUD ancestors.
const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const source = fs.readFileSync('panorama/src/scripts/custom_game/tooltip_position.js', 'utf8');
const layersSource = fs.readFileSync('panorama/src/scripts/custom_game/ui_layers.js', 'utf8');
function fixture({lazy = false} = {}) {
    let now = 0, serial = 0, native = null;
    const cfg = {}, calls = [], jobs = new Map(), writes = [];
    class Panel {
        constructor(id, parent, type = 'Panel', z = '') {
            this.id = id; this.parent = parent; this.paneltype = type; this.children = [];
            this.classes = new Set(); this.alive = true;
            this.style = new Proxy({zIndex:z}, {set:(target,key,value) => {
                writes.push({panel:this,key}); target[key] = value; return true;
            }});
            if (parent) parent.children.push(this);
        }
        GetParent() { return this.parent; }
        Children() { return this.children.filter(child => child.alive); }
        IsValid() { return this.alive; }
        BHasClass(name) { assert(this.alive, 'Do not inspect a deleted native panel'); return this.classes.has(name); }
        SetFocus() {}
        SetAcceptsFocus() {}
        FindChildTraverse(id) {
            return this.Children().find(child => child.id === id)
                || this.Children().map(child => child.FindChildTraverse(id)).find(Boolean);
        }
        SetParent() { throw Error('Native panels must not be reparented'); }
    }
    const root = new Panel('Root'), hud = new Panel('Hud', root, 'DOTAHud', '10');
    const custom = new Panel('CustomUI', root, 'Panel', '20'), context = new Panel('Payment', custom, 'Panel', '4');
    const tooltip = new Panel('Tooltips', hud, 'Panel', '12'), owner = new Panel('Hover', context);
    const modal = new Panel('Market', custom, 'Panel', '21');
    function createNative() { native = new Panel('', hud, 'DOTAErrorMsg', '13'); new Panel('ErrorMsg', native, 'Label', ''); return native; }
    if (!lazy) createNative();
    const env = {$: {GetContextPanel:() => context, DispatchEvent(){},
        Schedule(delay,fn) { const id = ++serial; jobs.set(id,{id,at:now+delay,fn}); return id; },
        CancelScheduled(id) { jobs.delete(id); }},
        GameUI:{CustomUIConfig:() => cfg}, GameEvents:{SendEventClientSide(name,payload) {
            calls.push({name,payload}); if (native && native.alive) native.classes.add('ShowErrorMsg');
        }}};
    vm.createContext(env); vm.runInContext(source,env); vm.runInContext(layersSource,env);
    function advance(seconds) { const end=now+seconds; let guard=0;
        for (;;) { const job=[...jobs.values()].filter(job=>job.at<=end).sort((a,b)=>a.at-b.at||a.id-b.id)[0];
            if (!job) break; assert(++guard<1000,'No unbounded native polling'); jobs.delete(job.id); now=job.at; job.fn(); }
        now=end;
    }
    return {cfg,calls,jobs,writes,root,hud,custom,context,modal,tooltip,owner,createNative,advance,
        get native(){return native;}, get api(){return cfg.SurvivalTooltipPosition;},
        reload(){vm.runInContext(source,env);}};
}
function nativeFront(f) {
    assert(Number(f.native.style.zIndex)>Number(f.modal.style.zIndex));
    assert(Number(f.hud.style.zIndex)>Number(f.custom.style.zIndex));
    assert(Number(f.root.style.zIndex||0)<2100000000,'The native lease never raises the global root');
    assert(Math.fround(Number(f.native.style.zIndex))>Math.fround(Number(f.tooltip.style.zIndex)),
        'Native error priority remains distinct from tooltip priority through float32');
    assert(f.writes.every(write=>write.key==='zIndex'),'The native widget retains all visual/input/position styles');
}
function restored(f) {
    assert.equal(f.hud.style.zIndex,'10'); assert.equal(f.custom.style.zIndex,'20');
    assert.equal(f.tooltip.style.zIndex,'12'); assert.equal(f.native.style.zIndex,'13');
    assert.equal(f.api.InspectNativeErrorLayer().raised,0); assert.equal(f.jobs.size,0);
}
{
    const f=fixture(); f.cfg.SurvivalUILayers.Open('market',f.modal,()=>{});
    f.api.ShowNativeError(f.context,'您的积分不足'); f.advance(0); nativeFront(f);
    assert.deepEqual(JSON.parse(JSON.stringify(f.calls)),[{name:'dota_hud_error_message',payload:{reason:80,message:'您的积分不足'}}]);
    f.native.classes.delete('ShowErrorMsg'); f.advance(.7);
    assert.equal(f.api.InspectNativeErrorLayer().raised,0); assert.equal(f.jobs.size,0,'No timer survives the native message');
    f.cfg.SurvivalUILayers.Close('market'); restored(f);
}
for (const textFirst of [true,false]) for (const modalFirst of [true,false]) for (const textEndsFirst of [true,false]) {
    const f=fixture(), layers=f.cfg.SurvivalUILayers;
    if(modalFirst)layers.Open('market',f.modal,()=>{});
    if(textFirst)f.api.ShowText(f.owner,'tooltip');
    f.api.ShowNativeError(f.context,'您的积分不足');
    if(!textFirst)f.api.ShowText(f.owner,'tooltip');
    if(!modalFirst)layers.Open('market',f.modal,()=>{});
    f.advance(0); nativeFront(f);
    assert(Number(f.native.style.zIndex)>Number(f.tooltip.style.zIndex),'Error remains above a concurrent native tooltip');
    if(textEndsFirst)f.api.HideText(f.owner);
    layers.Close('market'); nativeFront(f);
    f.native.classes.delete('ShowErrorMsg'); f.advance(.7);
    if(!textEndsFirst)f.api.HideText(f.owner);
    restored(f);
}
{
    const f=fixture({lazy:true}); f.api.ShowNativeError(f.context,'您的积分不足');
    f.createNative().classes.add('ShowErrorMsg'); f.advance(0); nativeFront(f);
    const old=[...f.jobs.values()][0].fn; f.api.ShowNativeError(f.context,'您的积分不足');
    old(); assert(f.api.InspectNativeErrorLayer().pending,'A stale callback cannot erase the current timer');
    f.native.classes.delete('ShowErrorMsg'); f.advance(.7); restored(f); assert.equal(f.calls.length,2);
}
{
    const f=fixture(); f.api.ShowNativeError(f.context,'您的积分不足'); f.advance(0);
    f.native.alive=false; f.native.children.forEach(child=>child.alive=false);
    const replacement=f.createNative(); replacement.classes.add('ShowErrorMsg'); f.advance(.11); nativeFront(f);
    replacement.classes.delete('ShowErrorMsg'); f.advance(.7); restored(f);
}
{
    const f=fixture(); f.api.ShowNativeError(f.context,'您的积分不足'); f.reload(); f.advance(8); restored(f);
}
{
    const f=fixture(); f.api.ShowNativeError(f.context,'您的积分不足'); f.context.alive=false; f.advance(.2); restored(f);
}
{
    const f=fixture(); f.api.ShowNativeError(f.context,'您的积分不足'); f.advance(7); restored(f);
}
console.log('NATIVE_ERROR_LAYER_PASS: authentic event/host, modal and tooltip coexistence, visible-only lease, lazy host, renewal, replacement, reload, deletion and bounded recovery');
