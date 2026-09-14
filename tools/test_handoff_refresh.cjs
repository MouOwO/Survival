const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
const code=source.slice(source.indexOf('    function refreshNow()'),source.indexOf('    function tick()'));
const warnings=[];let revealed=0,calls=0;const geometry={scale:.5};
const env={valid:p=>!!p,ctx:{},cfg:{HandoffGeneration:1},generation:1,ready:true,geometry,
 layout:()=>{},refreshInventoryPresentation:()=>{},native:()=>null,
 fitNativeSkills:g=>{assert.strictEqual(g,geometry);assert.equal(g.scale,.5);calls++;},
 mirror:()=>{},mirrorKeys:()=>{},revealWhenStable:()=>revealed++,$:{Warning:m=>warnings.push(m)}};
vm.runInNewContext(code,env);env.refreshNow();env.refreshNow();
assert.equal(warnings.length,0);assert.equal(calls,2);assert.equal(revealed,2,'HUD reveal must be reached on each refresh');
const fit=source.slice(source.indexOf('    function fitNativeSkills('),source.indexOf('    function canvas('));
vm.runInNewContext(fit,{geometry:undefined,native:()=>{throw Error('unready layout should return before accessing native HUD')}});
const early={geometry:undefined};vm.createContext(early);vm.runInContext(fit,early);early.fitNativeSkills();
console.log('HANDOFF_REFRESH_PASS: initial and periodic refresh keep geometry and reach HUD reveal; unready geometry is safe');
