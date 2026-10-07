'use strict';
const fs=require('fs');
// CSV supports quoted newlines; preview data is read-only, never sent to a server.
function csv(file){
 const source=fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''),all=[];let row=[],field='',quoted=false;
 for(let i=0;i<source.length;i++){const c=source[i];if(c==='"'){if(quoted&&source[i+1]==='"'){field+='"';i++;}else quoted=!quoted;}else if(c===','&&!quoted){row.push(field);field='';}else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&source[i+1]==='\n')i++;row.push(field);if(row[0]&&!row[0].startsWith('#'))all.push(row);row=[];field='';}else field+=c;}
 if(field||row.length){row.push(field);all.push(row);}const header=all.shift();return all.map(r=>Object.fromEntries(header.map((h,i)=>[h,r[i]||''])));
}
function fixture(){
 const base='data/csv/',cats=csv(base+'商城支付系统/payment_categories.csv').filter(r=>r.enabled==='1').sort((a,b)=>Number(a.sort_order)-Number(b.sort_order)).map(r=>({id:r.category_id,label:r.display_name}));
 function products(group,payment){const rewards=csv(base+group+'/'+(payment?'payment_rewards':'commerce_rewards')+'.csv');return csv(base+group+'/'+(payment?'payment_products':'commerce_products')+'.csv').filter(p=>p.enabled==='1').sort((a,b)=>Number(a.sort_order)-Number(b.sort_order)).map(p=>({
  sku:p.sku,title:p.display_name,category_id:p.category_id,product_type:p.product_type,amount_fen:payment?Math.round(Number(p.price_yuan)*100):undefined,
  purchase_method:payment?'paid':'wallet',price:Number(p.price),currency:p.currency,currency_name:{u_coin:'U币',shop_points:'积分',shop_gold:'金币'}[p.currency],enabled:true,owned:0,icon:p.icon,description:p.description,
  reward_lines:rewards.filter(r=>r.sku===p.sku&&r.enabled==='1').map(r=>({kind:r.reward_type,id:r.target_id,label:r.display_name,quantity:Number(r.amount)}))
 }));}
 return {paid:{categories:cats,products:products('商城支付系统',true),catalog_hash:'CSV_LOCAL_READONLY'},wallet:{categories:cats,products:products('商城兑换系统',false),balances:{u_coin:0,shop_points:0,shop_gold:0}}};
}
module.exports={csv,fixture};
if(require.main===module){const d=fixture();console.log(JSON.stringify({categories:d.paid.categories,paid:d.paid.products.length,wallet:d.wallet.products.length,icons:[...new Set(d.paid.products.concat(d.wallet.products).map(p=>p.icon))]},null,2));}
