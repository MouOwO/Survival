'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto'),assert=require('assert'),cp=require('child_process');
const game=path.resolve(__dirname,'../..'),content='D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival';
const record=JSON.parse(fs.readFileSync(path.join(game,'output/content_merge_sync.json'),'utf8').replace(/^\uFEFF/,''));
const hash=b=>crypto.createHash('sha256').update(b).digest('hex').toUpperCase();
for(const [p,h] of Object.entries(record.files)){
 const original=fs.readFileSync(path.join(game,p.replace(/^panorama\//,'panorama/src/'))),target=path.join(content,p),restored=fs.readFileSync(target);
 assert.equal(hash(original),h,'canonical byte mismatch: '+p);
 assert.equal(original.toString().replace(/\r\n/g,'\n'),restored.toString().replace(/\r\n/g,'\n'),'substantive mismatch: '+p);
 fs.writeFileSync(target,original);assert.equal(hash(fs.readFileSync(target)),h);
}
const stashes=cp.execFileSync('git',['stash','list','--format=%H'],{cwd:content,encoding:'utf8'}).trim().split(/\r?\n/);assert.deepEqual(stashes,record.original_stashes);
console.log('CONTENT_UI_BYTES_AND_ORIGINAL_STASHES_VERIFIED');
