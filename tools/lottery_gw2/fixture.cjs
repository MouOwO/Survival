'use strict';
// Formal current pools/rewards/notices. Only balances and ownership are samples.
const path=require('path'),{csv}=require('../shop_ui_12h/catalog.cjs');
function fixture(){
 const base=path.resolve(__dirname,'../../data/csv/抽奖系统'),read=name=>csv(path.join(base,name+'.csv')).filter(row=>row.enabled===undefined||row.enabled==='1');
 return {pools:read('lottery_pool_definitions'),items:read('lottery_item_definitions'),members:read('lottery_pool_items'),pity:read('lottery_pity_rules'),updates:read('lottery_pool_updates'),runtimeValues:'Explicit local ticket balances, ownership, unlock progress, sequence, request IDs and result samples; no account, server, purchase or real draw. Formal names, reward art IDs, costs and notices come from current repository CSV.',source:['lottery_pool_definitions','lottery_item_definitions','lottery_pool_items','lottery_pity_rules','lottery_pool_updates'].map(name=>'data/csv/抽奖系统/'+name+'.csv')};
}
module.exports={fixture};
if(require.main===module)console.log(JSON.stringify(fixture(),null,2));
