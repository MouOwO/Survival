const fs=require('fs'),vm=require('vm'),path=require('path');
const base=fs.readFileSync('tools/test_archive_compact.cjs','utf8').split('const data=')[0];
const checks=`
Panel.prototype.SetScaling=function(v){this.scaling=v;};
cfg.ArchiveHandoff={Icon(){},Init(){},Observe(){},CardProgress(){return '0 / 1';}};
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/reward_presentation.js','utf8'),env);
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js','utf8'),env);
for(const q of ['n','r','sr','ssr','ur']){
 const card=new Panel('Panel');card.AddClass('ArchiveCard');card.AddClass('ArchiveContentLocked');card.AddClass('ArchiveArtAlwaysBright');
 cfg.ArchiveHandoff.Icon(card,{id:'lottery_nature_crystal',quality:q},'points',{});
 const art=card.children.find(p=>p.BHasClass('ArchiveArt'));
 const badge=art.children.find(p=>p.BHasClass('ArchiveRarityBadge'));
 assert(badge,'real points icon must include badge');assert.equal(badge.text,q.toUpperCase());
 cfg.ArchiveTheme.Apply(card);assert.equal(badge.style.color,cfg.SurvivalRewardPresentation.BadgeColor(q));assert.equal(badge.style.opacity,'1');
}
console.log('ARCHIVE_RARITY_PASS: all five authoritative tiers on production icons survive locked-card palette refresh');
`;
vm.runInNewContext(base+checks,{require,console});