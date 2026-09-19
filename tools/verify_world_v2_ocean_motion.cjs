const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert/strict');
const out=path.resolve(__dirname,'../output/survival_world_v2');
const dir='D:/steam/steamapps/common/dota 2 beta/game/dota/screenshots';
const shots=['a','b'].map(s=>fs.readdirSync(dir).filter(n=>n.startsWith('world_v2_ocean_motion_'+s+'_')&&n.endsWith('.tga')).map(n=>({name:n,time:fs.statSync(path.join(dir,n)).mtimeMs})).sort((a,b)=>b.time-a.time)[0]);
const built=fs.statSync(path.resolve(__dirname,'../maps/survival_world_v2.vpk')).mtimeMs;
assert(shots.every(s=>s&&s.time>built),'Need two fresh same-camera ocean captures');
assert(shots[1].time-shots[0].time>=4000,'Capture interval too short');
const images=shots.map(s=>{const b=fs.readFileSync(path.join(dir,s.name));return{b,w:b.readUInt16LE(12),h:b.readUInt16LE(14),channels:b[16]/8,offset:18+b[0],top:!!(b[17]&32)};});
assert(images[0].w===images[1].w&&images[0].h===images[1].h);
// The chosen camera aims at open sea between the north and east islands.
// Crop away HUD, cursor, shoreline, trees and time-dependent unit effects.
const crop={x:600,y:330,width:400,height:300};let changed=0,total=0,sum=0,max=0;
for(let y=crop.y;y<crop.y+crop.height;y++)for(let x=crop.x;x<crop.x+crop.width;x++){
 let delta=0;for(let c=0;c<3;c++){const p=images.map(im=>im.b[im.offset+((im.top?y:im.h-1-y)*im.w+x)*im.channels+c]);delta+=Math.abs(p[0]-p[1]);}delta/=3;
 if(delta>2)changed++;sum+=delta;max=Math.max(max,delta);total++;
}
const report={shots,intervalSeconds:(shots[1].time-shots[0].time)/1000,crop,meanAbsoluteRgbDifference:sum/total,changedPixelFraction:changed/total,maxRgbDifference:max,visualMotionDetected:changed/total>.01,limitation:'Verifies rendered texture/normal motion only, not physical wave displacement.'};
assert(report.visualMotionDetected,'No meaningful ocean surface animation detected');
for(let i=0;i<2;i++)cp.execFileSync(process.execPath,[path.join(__dirname,'capture_dota_image.cjs'),shots[i].name,path.join(out,'ocean_motion_'+['a','b'][i]+'.png')]);
fs.writeFileSync(path.join(out,'round_motion_validation.json'),JSON.stringify(report,null,2));console.log(report);
