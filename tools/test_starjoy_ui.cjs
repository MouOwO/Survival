const fs=require('fs'),vm=require('vm'),assert=require('assert');
const harness=fs.readFileSync('tools/test_archive_compact.cjs','utf8').split('const data=')[0];
const test=`
env.Game={AddCommand(){}};env.$.Msg=()=>{};env.$.GetContextPanel=()=>root;
root.FindChildTraverse=panel;
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/archive_handoff_180de7e38b.js','utf8'),env);
const real=cfg.ArchiveHandoff;
env.A.Unlocked=real.Unlocked;
env.icon=(card,item)=>{
 const art=new Panel('Panel');art.AddClass('ArchiveArt');card.children.push(art);
 const image=new Panel('Image');image.AddClass('ArchiveRewardIcon');image.SetImage(item.icon);art.children.push(image);
 label(card,real.CardProgress(item,'starjoy_points'),'ArchiveCount');
};
env.current='starjoy_points';
const rows=JSON.parse(fs.readFileSync('output/starjoy_rewards_20261003/test_rows.json','utf8'));
rows.forEach((r,i)=>{r.completed=r.unlocked=i<4?1:0;r.count=800;});
const data={category_id:'starjoy_points',categories:[{id:'starjoy_points',name:'星悦积分',renderer:'achievements'}],rows,starjoy:{earned:800,balance:200,level:4}};
env.render(data);
assert.equal(Object.keys(env.rowCards).length,24);
assert.equal(panel('ArchiveFilterAllLabel').text,'全部（4/24）');
rows.forEach((r,i)=>{
 const c=env.rowCards['starjoy_points:'+i].panel;
 assert.equal(c.BHasClass('ArchiveContentLocked'),i>=4);
 const art=c.children.find(p=>p.BHasClass('ArchiveArt'));
 assert.equal(art.style.brightness,i>=4?'0.6':'1');
 assert.equal(art.children[0].image,'s2r://panorama/images/custom_game/starjoy_v1/starjoy.vtex');
 assert.equal(c.children.find(p=>p.BHasClass('ArchiveCount')).text,String(r.target));
 assert(real.Condition(r,'starjoy_points').includes(String(r.target)));
});
env.filterMode='unlocked';env.render(data);
assert.equal(Object.values(env.rowCards).filter(c=>c.panel.visible).length,4);
env.filterMode='locked';env.render(data);
assert.equal(Object.values(env.rowCards).filter(c=>c.panel.visible).length,20);
rows[4].unlocked=rows[4].completed=1;data.starjoy.level=5;data.starjoy.earned=1000;
env.filterMode='all';env.render(data);
assert.equal(panel('ArchiveFilterAllLabel').text,'全部（5/24）');
assert.equal(env.rowCards['starjoy_points:4'].panel.children.find(p=>p.BHasClass('ArchiveArt')).style.brightness,'1');
assert(panel('ArchiveCurrencySource').text.includes('1000'));
assert.equal(panel('ArchiveFilters').BHasClass('ArchiveHidden'),false);
console.log('PASS 24 starjoy cards: thresholds, lock/bright states, both filters, cached unlock refresh');
`;
// Execute the existing render harness and assertions within one lexical scope.
new Function('require',harness+test)(require);
