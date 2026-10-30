// Real HUD routines against the native failures observed during offline QA.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
function between(a,b){return source.slice(source.indexOf(a),source.indexOf(b,source.indexOf(a)));}
let writes=0,notices=0;
const env={valid:p=>!!p&&p.alive!==false,$:{Msg:()=>notices++},sameStyleValue:(p,k,a,b)=>a===b};
vm.createContext(env);vm.runInContext(between('    function style(p,','    function cssNumber('),env);
function panel(id){return {id,values:{},GetChildCount(){return this.children.length},GetChild(i){return this.children[i]},children:[],BHasClass:k=>k==='LevelPanel'};}
function native(p){p.style=new Proxy(p.values,{get(o,k){if(k==='backgroundImage'&&p.failRead)throw Error('Failed to parse style value for backgroundImage');return o[k];},set(o,k,v){assert(v!==''&&v!==undefined&&v!=='null','native enum/dimension must be concrete: '+k);o[k]=v;writes++;return true;}});return p;}
const image=native(panel('NativeImage'));image.failRead=true;
env.style(image,{backgroundImage:'none'});const first=writes;
env.style(image,{backgroundImage:'none'});assert.equal(writes,first);assert.equal(notices,1);
const container=native(panel('AbilityLevelContainer'));
container.children=[native(panel('Level0')),native(panel('Level1'))];
Object.assign(env,{cssNumber:String,place:(p,x,y,w,h)=>env.style(p,{position:x+'px '+y+'px 0px',width:w+'px',height:h+'px'})});
vm.runInContext(between('    function styleAbilityLevelPips(','    function child('),env);
env.styleAbilityLevelPips(container);assert(container.__handoffLevelPips);
container.__handoffLevelPips.original.horizontalAlign=''; // Native state retained across a Tools/UI reload.
container.children[1].visible=false;
assert.doesNotThrow(()=>env.styleAbilityLevelPips(container));assert.equal(container.__handoffLevelPips,null);
assert.equal(container.values.horizontalAlign,'left');assert.equal(container.values.transitionDuration,'0s');
// One failing decoration cannot prevent trailing keys from being cleared.
const slot=panel('Ability0'),nodes={HandoffKey_0Bounds:{visible:true},HandoffKey_1Bounds:{visible:true},HandoffKey_2Bounds:{visible:true}};
const mirror={cfg:{},bottom:{},selectedUnit:()=>7,geometry:{heroWidth:473,scale:1},layoutRevision:1,
 skillPanels:[slot],keyBindings:{Ability0:{slot,text:'Q',unit:7,ability:100}},currentEntries:[{ability:100}],
 nodes,valid:env.valid,Date:{now:()=>1000},centered:()=>{throw Error('native decoration failure')},style:()=>{},actionOffset:()=>483};
vm.createContext(mirror);vm.runInContext(between('    function mirrorKeys(){','    function styleAbilityLevelPips('),mirror);
assert.throws(()=>mirror.mirrorKeys(),/decoration failure/);
assert.equal(nodes.HandoffKey_1Bounds.visible,false);assert.equal(nodes.HandoffKey_2Bounds.visible,false);
console.log('PORTRAIT_HUD_RESTORE_PASS: native background getter failure, valid single-level restoration, cleanup survives an earlier decoration failure');
