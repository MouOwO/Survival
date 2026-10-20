'use strict';
// Read-only formal reward extraction for five local, account-free design previews.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {open}=require('./vpk_inspect.cjs');
const repo=path.resolve(__dirname,'..'),base=path.join(repo,'design_refs/daily_official_five_20261019');
const sourceFiles={items:'data/csv/存档系统/archive_daily_items.csv',schedule:'data/csv/存档系统/archive_daily_schedule.csv',rules:'data/csv/存档系统/archive_daily_rules.csv',registry:'data/ui/item_resources.json',generatedSchedule:'scripts/vscripts/config/generated/archive_daily_schedule.lua',dailyLogic:'scripts/vscripts/systems/archive_daily_rewards.lua'};
const sha=raw=>crypto.createHash('sha256').update(raw).digest('hex');
function csv(file){
 const rows=[];let fields=[],value='',quote=false;
 for(const char of fs.readFileSync(path.join(repo,file),'utf8').replace(/^\uFEFF/,'')){
  if(char==='"'){quote=!quote;continue;}
  if(char===','&&!quote){fields.push(value);value='';continue;}
  if(char==='\n'&&!quote){fields.push(value.replace(/\r$/,''));if(fields.some(x=>x.length))rows.push(fields);fields=[];value='';continue;}
  value+=char;
 }
 if(fields.length||value){fields.push(value.replace(/\r$/,''));rows.push(fields);}
 const headers=rows.shift();return rows.filter(row=>!row[0].startsWith('#')).map(row=>Object.fromEntries(headers.map((key,index)=>[key,row[index]||''])));
}
const definitions=csv(sourceFiles.items).filter(row=>row.enabled==='1'),schedule=csv(sourceFiles.schedule).filter(row=>row.enabled==='1'),rule=csv(sourceFiles.rules)[0];
assert.equal(definitions.length,12);assert.equal(schedule.length,7);
const registry=JSON.parse(fs.readFileSync(path.join(repo,sourceFiles.registry),'utf8'));
const catalogBase=path.join(repo,'design_refs/official_ui_catalog_20261019'),catalog=JSON.parse(fs.readFileSync(path.join(catalogBase,'catalog.json'),'utf8'));
const archive=path.resolve(repo,'../../dota/pak01_dir.vpk'),vpk=open(archive),vpkIndex=new Map(vpk.entries.map(row=>[row.path,row]));
fs.mkdirSync(path.join(base,'rewards'),{recursive:true});
const items={};
for(const definition of definitions){
 const presentation=registry.items.find(row=>row.id===definition.item_id);assert(presentation,'Maintained resource identity '+definition.item_id);
 assert.equal(presentation.native_type,'item');
 const originalResource='panorama/images/items/'+presentation.native_name+'_png.vtex_c',entry=vpkIndex.get(originalResource);assert(entry,'Installed Valve resource '+originalResource);
 const record=catalog.assets.find(row=>row.sourcePath===originalResource);assert(record,'Exact original decoded PNG '+originalResource);
 const sourceSha256=sha(vpk.read(entry));assert.equal(sourceSha256,record.sourceSha256);
 const originalPng=path.join(catalogBase,record.original),png=fs.readFileSync(originalPng);assert.equal(sha(png),record.originalSha256);
 const width=png.readUInt32BE(16),height=png.readUInt32BE(20);assert.equal(width,record.width);assert.equal(height,record.height);
 const previewLocal='rewards/'+definition.item_id+'.png';fs.copyFileSync(originalPng,path.join(base,previewLocal));
 const buffLines=definition.description.split(/[；;\r\n]+/).filter(Boolean);
 items[definition.item_id]={id:definition.item_id,name:definition.display_name,quality:definition.quality,description:buffLines.join('\n'),buffLines,
  sourceMaxOwned:Number(definition.max_owned),previewMaxOwned:1,
  icon:{originalURI:'file://{images}/items/'+presentation.native_name+'.png',registryURI:presentation.uri,originalResource,previewLocal,width,height,sha256:sha(png),sourceSha256,
   sourceArchive:archive,originalDecodedPng:path.relative(repo,originalPng).replaceAll('\\','/'),method:'Exact pre-existing Source2Viewer decode, verified against installed Valve VPK and original PNG hashes; no artwork edits'}};
}
function reward(id,count){const item=items[id];assert(item);return {id,name:item.name,count:Number(count),quality:item.quality,description:item.description,buffLines:item.buffLines,icon:item.icon.previewLocal};}
const fixture={claimedDays:8,todayDay:9,monthlyPassActive:false,serverRequests:0,accountDataUsed:false};
const days=Array.from({length:28},(_,index)=>{
 const row=schedule.find(row=>Number(row.day_id)===index%7+1),ids=row.item_ids.split('|'),counts=row.item_counts.split('|');assert.equal(ids.length,counts.length);
 return {day:index+1,week:Math.floor(index/7)+1,cycleDay:index%7+1,state:index<fixture.claimedDays?'claimed':index===fixture.todayDay-1?'available':'future',rewards:ids.map((id,i)=>reward(id,counts[i]))};
});
const milestoneDays=rule.pass_milestones.split('|').map(Number),milestoneItems=rule.pass_item_ids.split('|');assert.equal(milestoneDays.length,milestoneItems.length);
const monthly=milestoneDays.map((day,index)=>({day,state:'locked',...reward(milestoneItems[index],1)}));
const payload={meta:{kind:'official_dota_daily_rewards_design_fixture',title:'每日奖励 · 官方组件设计预览',previewOnly:true,productionFilesChanged:false,
 layout:'7 columns by 4 rows on the left; 7/14/21 cumulative-sign-in monthly rewards on the right',
 iconPolicy:'Use maintained daily item identities and their explicit native_name mappings for this official-only design preview. registryURI is recorded separately; no production registry changes.',
 ownershipPolicy:'User-requested unique ownership (maximum one); displayed schedule quantity 3 is reward amount, not saved ownership quantity.',
 configurationNote:'Local source CSV still contains historical max_owned=999999 for nine daily entries. This design fixture does not migrate data or edit production configuration.'},fixture,items,days,monthly,
 rules:{durationDays:Number(rule.duration_days),priceText:rule.price_text,purchaseEnabled:rule.purchase_enabled==='1',makeupDays:Number(rule.makeup_days),timezoneHours:Number(rule.timezone_hours),passSku:rule.pass_sku,
  refreshText:'每日零点刷新',calendarText:'每日签到 · 七日循环',progressText:'累计签到 8 天',reminderText:'断签不重置累计进度',monthlyText:'月卡奖励按累计签到次数发放',
  monthlyMilestones:milestoneDays},
 sourceRefs:Object.entries(sourceFiles).map(([role,file])=>({role,path:file,sha256:sha(fs.readFileSync(path.join(repo,file)))}))};
fs.writeFileSync(path.join(base,'rewards.json'),JSON.stringify(payload,null,2)+'\n');
assert.equal(days.length,28);assert.equal(monthly.length,3);assert.equal(Object.keys(items).length,12);
assert.equal(days.filter(day=>day.state==='claimed').length,8);assert.equal(days.filter(day=>day.state==='available').length,1);
assert(days.every(day=>day.rewards.every(row=>row.count===3)));assert(monthly.every(row=>row.count===1));
console.log(JSON.stringify({status:'PASS',days:days.length,monthly:monthly.length,exactValveIcons:Object.keys(items).length,fixture,output:path.relative(repo,path.join(base,'rewards.json'))}));
