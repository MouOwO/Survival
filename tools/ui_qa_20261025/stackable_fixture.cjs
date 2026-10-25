'use strict';
// Explicit synthetic authoritative-style rows for current production archive
// components. Metadata comes from the snapshot's real project catalogues. No
// purchase, account mutation, remote request, or gameplay save is performed.
function seedStackableArchive(values, sequence) {
    const data=PREVIEW_FIXTURE,byContent=id=>data.content.find(x=>x.content_id===id);
    const ember=byContent('lottery_ember_of_legacy'),zongzi=byContent('welfare_zongzi');
    const daily=data.dailyData.items.find(x=>x.item_id==='daily_growth_gem');
    if(!ember||!zongzi||!daily)throw Error('Actual stackable/daily catalogue metadata is missing');
    const rows=[
        {id:values.legacyAlias?'video_p103':'lottery_ember_of_legacy',resource_id:'lottery_ember_of_legacy',name:ember.name,description:ember.description,icon_type:'item',icon:ember.icon,quality:'ur',count:values.ember,max_owned:0,item_type:'积分道具',source_kind:'benefit',duplicate_points:0},
        {id:'welfare_zongzi',name:zongzi.name,description:zongzi.description,icon_type:'custom',icon_style:'seal',quality:'r',count:values.zongzi,max_owned:150,target:150,item_type:'积分道具',source_kind:'benefit'},
        {id:'daily_growth_gem',name:daily.display_name,description:daily.description,icon_type:'custom',icon_style:'seal',quality:daily.quality,count:values.legacyDaily?3:values.unique,max_owned:values.legacyDaily?undefined:1,target:values.legacyDaily?999999:1,item_type:'积分道具',source_kind:'daily',duplicate_points:25,duplicate_currency:'shop_points',converted_currency:'shop_points'}
    ];
    rows.forEach(row=>{row.count_known=1;row.unlocked=row.count>0?1:0;});
    const original=JSON.stringify(rows),categories=data.archiveCats;
    cfg.SurvivalArchive.Open();cfg.SurvivalArchive.SelectCategory('points');
    emit('survival_archive_snapshot',{ok:1,category_id:'points',sequence,chunk:1,chunks:1,categories,rows});syncLayout();
    window.__uiqaStackableFixture={values,sequence,rows,original};
    return {rows:JSON.parse(original),purchaseOriginSku:values.legacyAlias?'video_p103':null,cloudOrPayment:false,metadataSource:'Actual snapshot content/daily CSV metadata with explicit synthetic inventory counts'};
}
module.exports={seedStackableArchive};
