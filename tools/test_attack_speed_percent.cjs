const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const scripts=path.resolve(process.argv[2]||'panorama/src/scripts/custom_game');
const src=fs.readFileSync(path.join(scripts,'topnav_remaining_5d5c1152eb.js'),'utf8').replace(/\r\n/g,'\n');
const start=src.indexOf('        stats.forEach(function(a,i){\n            var visible=shown.lumberjack');
const end=src.indexOf('        Object.keys(topButtons)',start);
assert(start>=0&&end>start);
const nodes={},stats=[['attack','CombatAttackValue'],['armor','CombatArmorValue'],['attack_speed','CombatAttackSpeedValue'],['strength','CombatStrengthValue'],['agility','CombatAgilityValue'],['intelligence','CombatIntellectValue']];
for(const [key] of stats)['HandoffStatIcon_','HandoffStatName_','HandoffStat_','HandoffStatBonus_','HandoffStatPercent_'].forEach(p=>nodes[p+key]={style:{}});
let snapshot={attack_max:1087.8,armor:-2,attack_speed:1.6,attack_speed_percentage:160,display_attack_speed_bonus:.9333,display_attack_speed_pct:60,
 strength:4528.2,agility:4528.2,intellect:4528.2,display_attack_bonus:1599.3,display_armor_bonus:-.1,display_strength_bonus:14000};
const env={stats,nodes,snapshot,unit:1,repaint:true,shown:{combat:true,attributes:true},multi:false,style:(p,s)=>Object.assign(p.style,s),text:(id,t)=>nodes[id].text=t,ctx:{FindChildTraverse:id=>({text:id==='CombatAttackSpeedValue'?'160%':'999'})},cfg:{HandoffCombat:{Snapshot:()=>snapshot}},selectedUnit:()=>1,compact:String};
env.findCached=(parent,id)=>parent.FindChildTraverse(id);
const formatterStart=src.indexOf('    function attackFrequencyText(');
const formatterEnd=src.indexOf('    ["HandoffStatName_attack_speed"',formatterStart);
assert(formatterStart>=0&&formatterEnd>formatterStart);
vm.createContext(env);vm.runInContext(src.slice(formatterStart,formatterEnd),env);vm.runInContext(src.slice(start,end),env);
assert.equal(nodes.HandoffStat_attack_speed.text,'1.6','final HUD uses authoritative frequency without adding legacy bonuses');
assert.equal(nodes.HandoffStat_attack.text,'1087.8','final damage includes every fixed and percentage bonus');
assert.equal(nodes.HandoffStat_armor.text,'-2','negative final armor remains signed');
for(const key of ['strength','agility','intelligence'])assert.equal(nodes['HandoffStat_'+key].text,'4528.2');
for(const [key] of stats)for(const prefix of ['HandoffStatBonus_','HandoffStatPercent_'])assert.equal(nodes[prefix+key].style.visibility,'collapse','only final totals are visible');
for(const [frequency,expected] of [[2/3,'0.7'],[1.65,'1.7'],[1.66,'1.7'],[0,'0.0'],[100.04,'100.0']]){
 env.snapshot={attack_speed:frequency,attack_speed_percentage:100};vm.runInContext(src.slice(start,end),env);assert.equal(nodes.HandoffStat_attack_speed.text,expected);
}
for(const snapshot of [null,{}, {attack_speed:null},{attack_speed:-1},{attack_speed:'bad'},{attack_speed:Infinity},{attack_speed:Number.MAX_VALUE},{attack_speed_percentage:95}]){
 env.snapshot=snapshot;vm.runInContext(src.slice(start,end),env);
 assert.equal(nodes.HandoffStat_attack_speed.text,'…','missing/invalid frequency never reuses a stale value or treats legacy percentage as frequency');
 assert.equal(nodes.HandoffStat_attack.text,'999','other stats retain the native fallback while their snapshot loads');
}
const tooltipStart=formatterStart;
const tooltipEnd=src.indexOf('    function layoutStats(',tooltipStart);
let tooltipFrequency=2/3;
const tooltips={};const tooltipEnv={nodes,tooltip:(panel,value)=>tooltips[stats.find(([key])=>nodes['HandoffStat_'+key]===panel)?.[0]||'attack_speed']=value,selectedSnapshot:()=>({attack_speed:tooltipFrequency,stat_tooltips:{attack_speed:{percentage:95,base_interval:1.5,attack_interval:1.5,interval_reductions:{},speed_bonuses:{}}}})};
vm.createContext(tooltipEnv);vm.runInContext(src.slice(tooltipStart,tooltipEnd),tooltipEnv);
assert(tooltips.attack_speed().startsWith('当前攻速：0.7 刀/秒<br>攻速倍率：95%'),'tooltip begins with the same frequency and unit, then separately explains its percentage');
for(const [frequency,expected] of [[1.65,'1.7'],[null,'…'],[undefined,'…'],[-1,'…'],[Infinity,'…'],[Number.MAX_VALUE,'…'],[0,'0.0']]){
 tooltipFrequency=frequency;env.snapshot={attack_speed:frequency};vm.runInContext(src.slice(start,end),env);
 assert.equal(nodes.HandoffStat_attack_speed.text,expected);
 assert(tooltips.attack_speed().startsWith('当前攻速：'+expected+' 刀/秒'),'tooltip shares the HUD rounding and missing-value rules');
}
console.log('ATTACK_SPEED_FREQUENCY_PASS: final six stats, negative armor, ordinary/fused/zero rates, one decimal, missing snapshot and invalid reset, no stale percentage, hidden bonus rows, tooltip frequency unit');
