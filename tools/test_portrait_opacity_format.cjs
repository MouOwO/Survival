const fs = require('fs'), vm = require('vm'), assert = require('assert');
const file = process.argv[2] || 'panorama/src/scripts/custom_game/portrait_presentation.js';
const source = fs.readFileSync(file, 'utf8');

function fixture(code, color) {
    let now = 0;
    const cfg = {SurvivalPortraitPalette:{defaultColor:color}}, writes = [];
    class Panel {
        constructor(id, parent) {
            this.id=id;this.parent=parent;this.children=[];
            if (parent) parent.children.push(this);
            this.style=new Proxy({}, {set:(target,key,value)=>{
                if (key==='opacity') {
                    assert(/^(?:0|1)(?:\.\d+)?$/.test(value), 'Panorama opacity rejects exponent notation: '+value);
                    assert(Number.isFinite(Number(value)) && Number(value)>=0 && Number(value)<=1);
                    writes.push({panel:this,value});
                }
                target[key]=value;return true;
            }});
        }
        IsValid(){return !this.deleted;}
        GetParent(){return this.parent;}
        FindChildTraverse(id){
            if(this.id===id&&!this.deleted)return this;
            for(const child of this.children){const found=child.FindChildTraverse(id);if(found)return found;}
            return null;
        }
        DeleteAsync(){this.deleted=true;}
        MoveChildBefore(){}
    }
    const block=new Panel('center_block'), group=new Panel('PortraitGroup',block);
    const container=new Panel('PortraitContainer',group), native=new Panel('portraitHUD',container);
    const custom=new Panel('SurvivalTowerPortraitOverlay',container);
    new Panel('SurvivalTowerPortraitScene',custom);
    custom.style.visibility='collapse';
    vm.runInNewContext(code,{GameUI:{CustomUIConfig:()=>cfg},
        Players:{GetLocalPlayerPortraitUnit:()=>7},Entities:{GetUnitName:()=>''},
        Date:{now:()=>now},$:{CreatePanel:(_,parent,id)=>new Panel(id,parent)}});
    return {cfg,container,custom,writes,refresh(time){now=time;cfg.SurvivalPortraitPresentation.Refresh(group);},
        motes(){return container.FindChildTraverse('SurvivalPortraitMotes').__motes;}};
}

// Execute the actual Refresh -> animation -> style setter path, including the
// tiny positive value that previously reached the native setter as 6.6e-8.
const fire=fixture(source,'#943d20');
fire.refresh(0.0001013275573);
assert.equal(fire.motes()[0].style.opacity,'0.000000');
fire.refresh(1152);
assert.equal(Number(fire.motes()[0].style.opacity),0.48,'keep the original fire fade peak');
fire.refresh(2303.99999999);
assert.equal(Number(fire.motes()[0].style.opacity),0,'fade endpoint rounds below visible precision');
for (const time of [0,2304,4800,1791479845572,1791480345095,1791479846400]) fire.refresh(time);
const blue=fixture(source,'#29424b');
blue.refresh(1560);
assert.equal(Number(blue.motes()[0].style.opacity),0.25,'keep the original blue fade peak');
for(const mote of blue.motes())assert(!/[eE]/.test(mote.style.opacity));

// Selected custom portraits use the same safe animation path, and hiding it
// still collapses the existing layer rather than recreating particles.
const nativeLayer=fire.container.children.find(child=>child.id==='SurvivalPortraitMotes');
fire.custom.style.visibility='visible';fire.refresh(0.0001013275573);
assert.equal(nativeLayer.style.visibility,'collapse');
const customLayer=fire.custom.FindChildTraverse('SurvivalPortraitMotes');
assert.equal(customLayer.__motes[0].style.opacity,'0.000000');
fire.refresh(1152);assert.strictEqual(fire.custom.FindChildTraverse('SurvivalPortraitMotes'),customLayer);

const start=source.indexOf('    function opacityCSS('), end=source.indexOf('    function updateBackdropMotes(',start);
assert(start>=0&&end>start);
const format=vm.runInNewContext(source.slice(start,end)+'\nopacityCSS');
for(const input of [NaN,Infinity,-Infinity,undefined,'bad',-0.5,-1e300])assert.equal(format(input),'0.000000');
for(const input of [1.5,1e300])assert.equal(format(input),'1.000000');
for(const input of [0,1,0.12345678,6.631895291550715e-8]){
    const output=format(input);assert(!/[eE]/.test(output));assert(Math.abs(Number(output)-input)<=0.0000005);
}
const before='output/extreme_perf_20261008/opacity_worldbar_game_before/panorama/scripts/custom_game/portrait_presentation.js';
if(fs.existsSync(before)){
    const old=fixture(fs.readFileSync(before,'utf8'),'#943d20');
    assert.throws(()=>old.refresh(0.0001013275573),/Panorama opacity rejects exponent notation/,
        'original production animation reproduces the native opacity rejection');
}
console.log('PORTRAIT_OPACITY_FORMAT_PASS: actual native/custom animation path, tiny endpoints, finite/clamped decimal output, unchanged fade peaks');
