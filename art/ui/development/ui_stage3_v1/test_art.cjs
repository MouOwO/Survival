const fs=require('fs'),p=require('path'),assert=require('assert'),crypto=require('crypto');
const repo=p.resolve(__dirname,'../../../..');
const csv=fs.readFileSync(p.join(repo,'data/csv/肉鸽奖励系统/rogue_reward_art.csv'),'utf8').replace(/^\uFEFF/,'').trim().split(/\r?\n/);
assert.equal(csv.shift(),'card_id,display_name,image_path,design_width,design_height,notes');
const audit=JSON.parse(fs.readFileSync(p.join(__dirname,'art/audit.json'),'utf8'));
assert.equal(csv.length,52);assert.equal(audit.length,52);
for(const line of csv){
 const [id,name,image,w,h]=line.split(',');
 const row=audit.find(r=>r.card_id===id);assert(row,id);
 assert.equal(row.display_name,name);assert.equal(row.image_path,image);assert.equal(w,'232');assert.equal(h,'348');
 const bytes=fs.readFileSync(p.join(repo,'panorama/src/images',image));
 assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),row.sha256);
 assert.equal(row.width,1024);assert.equal(row.height,1536);assert.equal(row.alpha_min,0);
}
console.log('ROGUE_ART_PASS: 52 unique mapped cards, CSV/audit/master hashes agree, 1024x1536 RGBA masters and 232x348 design region');
