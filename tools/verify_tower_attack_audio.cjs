'use strict';
// Verify actual compiled event definitions, not compressed VPK byte matches.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/machine_gun_feedback');
fs.mkdirSync(out,{recursive:true});
const packs=['dota','core'].map(name=>new Vpk(path.resolve(root,'../../'+name+'/pak01_dir.vpk')));
function resourceBytes(resource){
  const key=resource+'_c',local=path.join(root,key);
  if(fs.existsSync(local))return fs.readFileSync(local);
  const pack=packs.find(v=>v.entries.has(key));assert(pack,'Missing resource: '+key);
  return pack.read(key);
}
const cache=new Map();
function inspect(resource){
  if(cache.has(resource))return cache.get(resource);
  const file=path.join(out,path.basename(resource)+'_c');fs.writeFileSync(file,resourceBytes(resource));
  const raw=cp.execFileSync(path.resolve(root,'../../bin/win64/resourceinfo.exe'),['-i',file,'-all'],{encoding:'utf8',windowsHide:true});
  assert(raw.includes(' block DATA'),'Missing decompressed DATA: '+resource);
  const text=raw.slice(raw.indexOf(' block DATA'));cache.set(resource,text);return text;
}
const lines=fs.readFileSync(path.join(root,'data/csv/建筑与工人系统/防御塔/tower_skill_sound_definitions.csv'),'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#'));
const headers=lines.shift().split(',');
const rows=lines.map(line=>Object.fromEntries(line.split(',').map((v,i)=>[headers[i],v]))).filter(r=>r.enabled==='1');
const records=[];
for(const row of rows){
  const text=inspect(row.sound_resource),event=row.sound_event.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  assert(new RegExp('(?:^|\\n)\\s*"?'+event+'"?\\s*=').test(text),'Undefined event: '+row.cue_id+' -> '+row.sound_event);
  records.push({cue:row.cue_id,event:row.sound_event,resource:row.sound_resource});
}
const coins=inspect('soundevents/survival_tower_feedback.vsndevts');
assert(/volume = 0\.22/.test(coins)&&coins.includes('sounds/ui/coins.vsnd'));
assert(coins.includes('limiter_max = 1.0')&&coins.includes('dota_src1_3d'));
resourceBytes('sounds/ui/coins.vsnd');
const coinParticle=inspect('particles/generic_gameplay/lasthit_coins.vpcf');
assert(coinParticle.includes('models/particle/coin.vmdl'));
resourceBytes('models/particle/coin.vmdl');
const report={status:'PASS',source:'installed Dota VPK and compiled addon sound event',enabled_cues:rows.length,
  coin_feedback:{event:'Survival.Tower.Coins',native_sample:'sounds/ui/coins.vsnd',volume:0.22,
    particle:'particles/generic_gameplay/lasthit_coins.vpcf',position:'tower head; CP0 and CP1',max_native_concurrent:1},
  in_game_audio_verified:false,records};
fs.writeFileSync(path.join(out,'audio_resources.json'),JSON.stringify(report,null,2)+'\n');
console.log('TOWER_ATTACK_AUDIO_RESOURCES_PASS cues='+rows.length+' native_coin_volume=0.22 compiled=true');
