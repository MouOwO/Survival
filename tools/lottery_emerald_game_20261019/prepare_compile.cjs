'use strict';
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const files=['scripts/custom_game/lottery_gw2.js','styles/custom_game/lottery_gw2.css','scripts/custom_game/lottery_cinematic_v1.js','styles/custom_game/lottery_cinematic_v1.css','scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js'];
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const scope=JSON.parse(fs.readFileSync(path.join(__dirname,'scope.json'),'utf8'));
for(const [file,expected]of Object.entries(scope.cinematic)){
 const text=fs.readFileSync(path.join(root,'panorama/src',file),'utf8').replace(/\r\n/g,'\n');
 if(hash(text)!==expected)throw Error('The original cinematic has changed: '+file);
}
const records=files.map(file=>({path:file,sha256:hash(fs.readFileSync(path.join(root,'panorama/src',file)))}));
const out=path.join(root,'output/lottery_emerald_game_20261019');fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'compile_plan.json'),JSON.stringify({files:records},null,2)+'\n');
console.log('LOTTERY_EMERALD_GAME_COMPILE_PLAN_READY '+records.length+' sources; original cinematic unchanged');
