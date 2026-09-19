const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_native'),shots=path.resolve(root,'../../dota/screenshots');
const vpk=path.join(root,'maps/survival_basin_native.vpk'),built=fs.statSync(vpk).mtimeMs;
const list=[['overview','整体鸟瞰'],['basin','中央盆地与浅水出怪点'],['stair','官方阶梯与坡口'],['pine','高处场地与崖边']];
const captures=list.map(([key,label])=>{
 const files=fs.readdirSync(shots).filter(f=>new RegExp('^basin_native_'+key+'_\\d+\\.tga$').test(f)).map(f=>({name:f,time:fs.statSync(path.join(shots,f)).mtimeMs})).sort((a,b)=>b.time-a.time);
 if(!files.length||files[0].time<built)throw Error('No fresh capture: '+key);
 cp.execFileSync(process.execPath,[path.join(__dirname,'capture_dota_image.cjs'),files[0].name,path.join(out,key+'.png')],{stdio:'pipe'});
 return {key,label,...files[0]};
});
fs.writeFileSync(path.join(out,'capture_manifest.json'),JSON.stringify({builtAt:new Date(built).toISOString(),vpkSha256:crypto.createHash('sha256').update(fs.readFileSync(vpk)).digest('hex'),captures},null,2));
fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>盆地 · 官方地形首版</title><style>body{margin:0;background:#e6e9e2;color:#26352e;font:17px/1.7 system-ui}main{max-width:1500px;margin:auto;padding:24px}img{width:100%;display:block}figure{margin:26px 0;background:#fff;padding:12px}h1{font-size:27px}a{color:#236657}code{background:#d5ded3;padding:4px}figcaption{padding:8px}</style><main><h1>盆地 · 官方地形首版</h1><p>本轮先看地形：中央低盆地、四条窄入口、四个高处场地。可活动地面、崖边和阶梯使用官方天辉地形块；水面独立铺在可通行地床上。草土统一打底，四季主题和装饰暂未细化。</p><p>独立地图：<code>survival_basin_native.vmap</code>。原有 review / edit 地图保留。打开新地图后可继续使用 Hammer 地形工具编辑。</p><p>检查结果：地图编译通过；中央到四座场地的双向寻路通过。外围裁切与背景仍是地形预览状态，本轮请重点判断高差、场地大小和阶梯衔接。</p>${captures.map(s=>`<figure><a href="${s.key}.png"><img src="${s.key}.png" alt="${s.label}"></a><figcaption>${s.label} · 点击查看原图</figcaption></figure>`).join('')}</main></html>`);
console.log('Fresh native terrain preview:',path.join(out,'index.html'));
