'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto'),assert=require('assert');
const content=path.resolve('../../../content/dota_addons/Survival'),root='output/ui_20h/compile_20261007_172417';
const git=args=>cp.execFileSync('git',['-C',content,'-c','safe.directory='+content.replaceAll('\\','/'),...args],{maxBuffer:32*1024*1024});
const normalize=b=>b.toString().replaceAll('\r\n','\n');
const excluded=new Set(['panorama/layout/custom_game/archive.xml','panorama/layout/custom_game/survival_hud.xml','panorama/scripts/custom_game/production_progress.js','panorama/styles/custom_game/production_progress.css','panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.js']);
const baseline=JSON.parse(fs.readFileSync('design_refs/ui_20h/work/checkpoints/best/manifest.json','utf8'));
const items=[];
for(const file of git(['diff','--name-only','-z']).toString().split('\0').filter(Boolean)){
 if(excluded.has(file)||!file.startsWith('panorama/'))continue;
 const original=root+'/'+file.replace('panorama/',''),current=path.join(content,file),game=file.replace('panorama/','panorama/src/'),base=baseline.files.find(x=>x.path===game),head=git(['show','HEAD:'+file]);
 const originalMatchesHead=fs.existsSync(original)&&normalize(fs.readFileSync(original))===normalize(head);
 const currentMatchesGame=normalize(fs.readFileSync(current))===normalize(fs.readFileSync(game));
 const gameMatchesPreviousCheckpoint=base&&crypto.createHash('sha256').update(fs.readFileSync(game)).digest('hex')===base.sha256;
 const alreadyHead=normalize(fs.readFileSync(current))===normalize(head);
 assert(alreadyHead||(originalMatchesHead&&currentMatchesGame&&gameMatchesPreviousCheckpoint),'Unproven provenance '+file);
 items.push({file,alreadyHead,originalMatchesHead,currentMatchesGame,gameMatchesPreviousCheckpoint:!!gameMatchesPreviousCheckpoint,currentHash:crypto.createHash('sha256').update(fs.readFileSync(current)).digest('hex'),gameHash:crypto.createHash('sha256').update(fs.readFileSync(game)).digest('hex'),targetHeadHash:crypto.createHash('sha256').update(head).digest('hex')});
}
const plan={contentHead:git(['rev-parse','HEAD']).toString().trim(),proof:'Only copies made by this UI run: pre-copy source equals content HEAD and current equals original UI checkpoint. No intervening user edits.',excluded:[...excluded],items};
fs.writeFileSync('design_refs/ui_20h/work/feedback10/reconcile_plan.json',JSON.stringify(plan,null,2));
console.log('READ_ONLY_RECONCILIATION_PROVEN '+items.length+' named files');
