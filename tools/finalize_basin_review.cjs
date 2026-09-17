const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_review');
const built=JSON.parse(fs.readFileSync(path.join(out,'compile.json'),'utf8').replace(/^\uFEFF/,''));
const consoleText=fs.readFileSync('D:/steam/steamapps/common/dota 2 beta/game/dota/console.log','utf8');
const begin=consoleText.lastIndexOf('[BASIN_NAV]\tpuddle');
const nav=consoleText.slice(begin<0?0:begin);
const summary=nav.match(/\[BASIN_NAV_SUMMARY\][^\r\n]*/g)?.at(-1);
assert(summary&&/failed=0(?:\s|$)/.test(summary),'Runtime navigation has not passed: '+summary);
assert(nav.includes('[BASIN_CAPTURE_COMPLETE]'),'Capture incomplete');
const paths=nav.split(/\r?\n/).filter(s=>s.includes('[BASIN_PATH]'));assert(paths.length===4&&paths.every(s=>/true\s+true/.test(s)),'Bidirectional route failure');
const shots=[['overview','整体结构','中央低盆地与四座高平台；东桃花、北冰雪、西松林、南暖砂。'],['basin','中央出生盆地','中心是浅水洼，四个出口通向阶梯。'],['peach','东 · 桃花青石','偏青绿的石地、苔草过渡与边缘桃花。'],['snow','北 · 冰雪石庭','冷灰石地与积雪混合，内部保持平坦。'],['pine','西 · 松林苔地','草、土、岩石与旧石路连续混合。'],['sand','南 · 暖砂石庭','暖色砂土与岩石地表；内部无水域。'],['stair_gate','阶梯与城墙缺口','单一窄通道可上下往返，顶端预留城墙位置。']];
shots.splice(4,0,['snow_material_close','冰雪平台 · 新材质近景','独立 Blender 石板模型烘焙颜色与法线；地面仍然平坦，积雪沿边缘覆盖。']);
const manifest=[];
for(const[name,title,description]of shots){
 const dir='D:/steam/steamapps/common/dota 2 beta/game/dota/screenshots/';
 const exact=new RegExp('^basin_review_'+name+'_\\d+\\.tga$');
 const file=fs.readdirSync(dir).filter(f=>exact.test(f)).sort((a,b)=>fs.statSync(dir+b).mtimeMs-fs.statSync(dir+a).mtimeMs)[0],src=dir+file;
 assert(fs.statSync(src).mtimeMs>new Date(built.builtAt).getTime(),'Stale screenshot '+file);
 cp.execFileSync(process.execPath,[path.join(root,'tools/capture_dota_image.cjs'),file,path.join(out,name+'.png')]);manifest.push({name,title,description});
}
fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify({builtAt:built.builtAt,map:'survival_basin_review',navigation:summary,bidirectionalPaths:paths,screenshots:manifest,scope:'Independent central battlefield sample. Main map not replaced; production wave and builder configuration not migrated.'},null,2));
fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="zh"><meta charset="utf-8"><title>盆地与四季建造区 · 实机样板</title><style>body{margin:0;background:#18252b;color:#e6e8df;font:17px/1.75 system-ui}main{max-width:1350px;margin:auto;padding:32px}h1{font-size:30px}p{color:#b8c8c6}nav{display:flex;gap:20px;flex-wrap:wrap}a{color:#b8ded4}figure{margin:36px 0 50px}img{display:block;width:100%;border-radius:8px}figcaption{margin:12px 0;font-size:21px}small{display:block;font-size:15px;color:#a8b9b9}code{background:#263b43;padding:2px 7px}</style><main><h1>中央盆地 + 四座圆形建造区</h1><p>这是新方向的独立实机样板，原来的整图仍保留。中央低盆地、四条可往返的窄阶梯、四座平坦的干燥建造平台，入口留出城墙缺口。以下为本次编译后的游戏截图。</p><nav>${shots.map(s=>`<a href="#${s[0]}">${s[1]}</a>`).join('')}</nav>${shots.map(([name,title,desc])=>`<figure id="${name}"><a href="${name}.png"><img src="${name}.png" alt="${title}"></a><figcaption>${title}<small>${desc}</small></figcaption></figure>`).join('')}<p>测试地图：<code>survival_basin_review</code>。四个方向已检查双向寻路、阶梯高度和通道外阻挡。城墙建造规则与正式出怪配置尚未迁移；此页用于确认局部结构、美术和尺度。</p></main>`);
console.log('Basin review published: output/basin_review/index.html');
