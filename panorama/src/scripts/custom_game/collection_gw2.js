(function(){
"use strict";
var cfg=GameUI.CustomUIConfig(),U=cfg.SurvivalUI,A=cfg.ArchiveHandoff,root=$.GetContextPanel();
if(!U||!A)return;
if(cfg.SurvivalCollection&&cfg.SurvivalCollection.Dispose)cfg.SurvivalCollection.Dispose();
var P=cfg.CollectionGW2Data||{},size=P.canvas||[1200,800],life=U.Lifecycle(),viewLife=U.Lifecycle();
// Intent and authoritative caches outlive an individual layout/script instance.
// Closing or reloading must never turn one pending draw into another purchase.
var shared=cfg.SurvivalCollectionState||(cfg.SurvivalCollectionState={pages:{},versions:{},pending:null,serial:0});
var active=true,opened=false,current="ex",query="",selected="",assemblies={},resync={},fetchJob=null,fetching=false;
var canvas,grid,gridBody,empty,search,draw,drawText,tickets,summary,result,tipPanel,tipFrame,tipViewport,tipTitle,tipBody,tipAnchor=null;
var tooltipEpoch=0,scale=1,cardsKey="",visibleRows=[],slots=[],tabs={},nodes={},api,createdRoots=[];
var names={ex:"我的前女友",friend:"我的前男友",wife:"我的老婆"};
function valid(n){return n&&(!n.IsValid||n.IsValid());}
function p(id){return valid(root)?root.FindChildTraverse(id):null;}
function make(type,parent,id,cls){var n=$.CreatePanel(type,parent,id||"");if(cls)n.AddClass(cls);if(id)nodes[id]=n;return n;}
function style(n,values){Object.keys(values).forEach(function(k){if(n.style[k]!==values[k])n.style[k]=values[k];});}
function rect(n,x,y,w,h){style(n,{position:x+"px "+y+"px 0px",width:w+"px",height:h+"px",margin:"0px",padding:"0px",horizontalAlign:"left",verticalAlign:"top"});}
function skin(n,key){var a=P.assets&&P.assets[key];if(a)style(n,{backgroundImage:'url("'+a.file+'")',backgroundColor:"transparent",backgroundSize:"100% 100%",backgroundRepeat:"no-repeat",border:"0px"});}
function art(parent,key,x,y,w,h,id){var n=make("Panel",parent,id,"CollectionGW2Art");rect(n,x,y,w,h);n.hittest=false;n.hittestchildren=false;skin(n,key);return n;}
function label(parent,text,x,y,w,h,font,color,id){var n=make("Label",parent,id,"CollectionGW2Text");rect(n,x,y,w,h);n.text=String(text===undefined?"":text);n.hittest=false;style(n,{fontSize:font+"px",color:color||"#dfdfd6",fontFamily:'"Source Han Sans SC"',whiteSpace:"nowrap",textOverflow:"ellipsis"});return n;}
function array(v){return Array.isArray(v)?v:Object.keys(v||{}).sort(function(a,b){return Number(a)-Number(b);}).map(function(k){return v[k];});}
function copy(v){return JSON.parse(JSON.stringify(v));}
function known(v){return v!==undefined&&v!==null&&String(v).trim()!==""&&isFinite(Number(v))&&Number(v)>=0;}
function number(v){return known(v)?String(v):"—";}
function countKnown(item){return Number(item.count_known)!==0&&known(item.count);}
function alive(){if(!active)return false;if(valid(root)&&valid(canvas)&&cfg.SurvivalCollection===api)return true;dispose();return false;}
var win=p("CollectionWindow"),scrim=p("CollectionScrim");
if(!valid(scrim)){scrim=make("Button",root,"CollectionScrim","ArchiveHidden");createdRoots.push(scrim);}
if(!valid(win)){win=make("Panel",root,"CollectionWindow","ArchiveHidden");createdRoots.push(win);}
win.AddClass("CollectionGW2Page");
var shell=U.ModalShell.Adopt({id:"collection",panel:win,root:root,scrim:scrim,width:size[0],height:size[1],fit:{reference:size.slice()},onClose:close});
// ModalShell establishes input/layer ownership and writes its generic fallback.
// Apply this independent window's alpha shell after adoption so it stays exact.
style(win,{width:size[0]+"px",height:size[1]+"px",horizontalAlign:"center",verticalAlign:"center",flowChildren:"none",backgroundColor:"transparent",backgroundImage:"none",border:"0px",boxShadow:"none",padding:"0px",margin:"0px",overflow:"noclip",transformOrigin:"50% 50%"});
canvas=make("Panel",win,"CollectionGW2Canvas","CollectionGW2Canvas");rect(canvas,0,0,size[0],size[1]);canvas.hittest=false;canvas.hittestchildren=true;
art(canvas,"window_background",20,28,1160,744,"CollectionGW2Background");
art(canvas,"header_strip",20,28,1160,74,"CollectionGW2Header");
art(canvas,"sidebar_background",32,106,112,598,"CollectionGW2Sidebar");
art(canvas,"footer_strip",146,674,1016,86,"CollectionGW2Footer");
label(canvas,"收藏",61,43,820,48,35,"#f4f0df","CollectionGW2Title");
var closeButton=make("Button",canvas,"CollectionGW2Close","CollectionGW2Button");rect(closeButton,1124,49,30,30);skin(closeButton,"close");
if(!(P.assets&&P.assets.close))label(closeButton,"×",0,-5,30,36,32,"#eee9df");
closeButton.hittestchildren=false;closeButton.SetPanelEvent("onactivate",function(){if(alive())shell.RequestClose("button");});
scrim.SetPanelEvent("onactivate",function(){if(alive())shell.RequestClose("scrim");});
Object.keys(names).forEach(function(id,i){
 var tab=make("Button",canvas,"CollectionGW2Tab_"+id,"CollectionGW2Tab");rect(tab,39,127+i*118,98,104);skin(tab,"tab_background");tab.hittestchildren=false;
 var selectedArt=art(tab,"tab_selected",0,0,98,104);selectedArt.AddClass("CollectionGW2TabSelected");
 art(tab,"tab_"+id,19,8,60,60);var text=label(tab,names[id],0,72,98,24,15,"#d4d7d5");style(text,{textAlign:"center"});
 tab.SetPanelEvent("onactivate",function(){if(alive())select(id);});
 tab.SetPanelEvent("onmouseover",function(){if(alive()&&opened)$.DispatchEvent("DOTAShowTextTooltip",tab,names[id]);});tab.SetPanelEvent("onmouseout",function(){$.DispatchEvent("DOTAHideTextTooltip");});tabs[id]=tab;
});
label(canvas,"",163,109,650,34,23,"#f1ecdc","CollectionGW2Category");
art(canvas,"search_background",865,111,287,35,"CollectionGW2SearchBacking");
search=make("TextEntry",canvas,"CollectionGW2Search","CollectionGW2Search");rect(search,882,115,252,29);search.SetAttributeString&&search.SetAttributeString("placeholder","搜索收藏");
var searchHint=label(canvas,"搜索收藏",884,116,243,26,17,"#9ba9ad","CollectionGW2SearchHint");
search.SetPanelEvent("ontextentrychange",function(){if(!alive())return;query=String(search.text||"").trim();searchHint.visible=!String(search.text||"").length;selected="";grid.ScrollToTop();hideTooltip();render();});
grid=make("Panel",canvas,"CollectionGW2Grid","CollectionGW2Grid");rect(grid,160,166,996,492);
gridBody=make("Panel",grid,"CollectionGW2GridBody","CollectionGW2GridBody");rect(gridBody,0,0,980,490);
empty=label(canvas,"",350,449,615,70,22,"#c4c7c6","CollectionGW2Empty");style(empty,{whiteSpace:"normal",textAlign:"center"});empty.visible=false;
summary=label(canvas,"",162,667,720,26,17,"#b9c0bc","CollectionGW2Summary");
tickets=label(canvas,"",162,698,700,24,18,"#cbd6d8","CollectionGW2Tickets");
result=label(canvas,"",162,728,975,22,16,"#c7c2ad","CollectionGW2Result");
draw=make("Button",canvas,"CollectionGW2Draw","CollectionGW2Button CollectionGW2Draw");rect(draw,908,700,240,44);skin(draw,"draw_button");draw.hittestchildren=false;
var drawHover=art(draw,"draw_button_hover",0,0,240,44);drawHover.AddClass("CollectionGW2Hover");
drawText=label(draw,"抽取",0,7,240,31,23,"#f2e4c8","CollectionGW2DrawText");style(drawText,{textAlign:"center"});
draw.SetPanelEvent("onactivate",drawOne);
tipPanel=make("Panel",canvas,"CollectionGW2Tooltip","CollectionGW2Tooltip");skin(tipPanel,"tooltip_background");tipPanel.visible=false;tipPanel.hittest=true;tipPanel.hittestchildren=true;
tipFrame=art(tipPanel,"tooltip_frame",0,0,360,230,"CollectionGW2TooltipFrame");
tipViewport=make("Panel",tipPanel,"CollectionGW2TooltipViewport","CollectionGW2TooltipViewport");rect(tipViewport,18,17,324,196);
tipTitle=label(tipViewport,"",0,0,324,34,23,"#f3d998","CollectionGW2TooltipTitle");
tipBody=label(tipViewport,"",0,0,324,150,18,"#deded5","CollectionGW2TooltipBody");
style(tipTitle,{height:"fit-children",whiteSpace:"normal",marginBottom:"10px"});style(tipBody,{height:"fit-children",whiteSpace:"normal",textOverflow:"clip"});
tipPanel.SetPanelEvent("onmouseover",function(){tooltipEpoch++;});tipPanel.SetPanelEvent("onmouseout",leaveTooltip);
function hideTooltip(){tooltipEpoch++;tipAnchor=null;if(valid(tipPanel))tipPanel.visible=false;}
function leaveTooltip(){if(!alive())return;var epoch=++tooltipEpoch;viewLife.Later(.16,function(){if(alive()&&epoch===tooltipEpoch)hideTooltip();});}
function fitTooltip(epoch){
 if(!alive()||!opened||epoch!==tooltipEpoch||!valid(tipAnchor))return;
 var origin=canvas.GetPositionWithinWindow(),at=tipAnchor.GetPositionWithinWindow(),sx=(canvas.actualuiscale_x||1)*scale,sy=(canvas.actualuiscale_y||1)*scale;
 var height=Math.min(610,Math.max(190,(tipTitle.actuallayoutheight||34)+(tipBody.actuallayoutheight||160)+45));
 var x=(at.x-origin.x)/sx+75,y=(at.y-origin.y)/sy;if(x+360>1160)x=(at.x-origin.x)/sx-372;
 rect(tipPanel,Math.max(30,Math.min(800,x)),Math.max(105,Math.min(760-height,y)),360,height);rect(tipFrame,0,0,360,height);rect(tipViewport,18,17,324,height-34);
}
function showTooltip(card,item){
 if(!alive()||!opened||!valid(card))return;hideTooltip();tipAnchor=card;tipTitle.text=item.name||"收藏";
 tipBody.text=(item.description||"属性说明待同步")+"\n\n持有数量："+(countKnown(item)?number(item.count):"—")+(known(item.target)?" / "+item.target:"")+"\n"+(countKnown(item)?Number(item.count)>0?"已收藏 · 效果按持有数量叠加":"尚未收藏":"数量待同步");
 tipPanel.visible=true;var epoch=tooltipEpoch;fitTooltip(epoch);[0,.05,.15].forEach(function(delay){viewLife.Later(delay,function(){fitTooltip(epoch);});});
}
function rewardIcon(card,item){
 var host=make("Panel",card,"","CollectionGW2Portrait");rect(host,3,3,60,60);host.hittest=false;host.hittestchildren=false;
 // ArchiveHandoff.Icon is backed by archive_item_icons.csv / portraits_v3.
 // SurvivalItemArt's older social head catalog is deliberately not used here.
 A.Icon(host,item,current,{});
 function fit(n){n.hittest=false;n.hittestchildren=false;if(n.paneltype==="Image"){rect(n,0,0,60,60);if(n.SetScaling)n.SetScaling("stretch-to-fit-preserve-aspect");}else if(n.BHasClass("ArchiveArt")){rect(n,0,0,60,60);style(n,{overflow:"clip"});}else if(n.paneltype==="Label")n.visible=false;array(n.Children()).forEach(fit);}
 array(host.Children()).forEach(fit);
}
function renderCards(rows){
 var signature=JSON.stringify([current,query,rows]);if(signature===cardsKey)return;cardsKey=signature;hideTooltip();gridBody.RemoveAndDeleteChildren();slots=[];
 visibleRows=rows.filter(function(item){return !query||String(item.name||"").toLowerCase().indexOf(query.toLowerCase())>=0;});
 var count=Math.max(98,Math.ceil(visibleRows.length/14)*14);rect(gridBody,0,0,980,Math.max(490,Math.ceil(count/14)*70));
 for(var i=0;i<count;i++){
  var item=visibleRows[i],card=make(item?"Button":"Panel",gridBody,item?"CollectionGW2Item_"+item.id:"CollectionGW2EmptySlot_"+i,"CollectionGW2Slot");rect(card,(i%14)*70,Math.floor(i/14)*70,66,66);skin(card,"slot_background");card.hittest=!!item;card.hittestchildren=false;card.__collectionItem=item||null;
  if(item){rewardIcon(card,item);card.SetHasClass("CollectionGW2Unowned",countKnown(item)&&Number(item.count)===0);card.SetHasClass("CollectionGW2Unknown",!countKnown(item));}
  art(card,"slot_frame",0,0,66,66);var hover=art(card,"slot_hover",0,0,66,66);hover.AddClass("CollectionGW2Hover");
  var selection=art(card,"slot_selected",0,0,66,66);selection.visible=!!item&&item.id===selected;card.__collectionSelection=selection;
  if(item){var quantity=label(card,countKnown(item)?number(item.count):"—",6,43,55,20,15,"#fbf3db");style(quantity,{textAlign:"right",textShadow:"#000000 0px 1px 2px 2.0"});bindCard(card,item);}
  slots.push(card);
 }
}
function bindCard(card,item){card.SetPanelEvent("onmouseover",function(){showTooltip(card,item);});card.SetPanelEvent("onmouseout",leaveTooltip);card.SetPanelEvent("onactivate",function(){if(!alive()||!opened)return;selected=item.id;slots.forEach(function(slot){slot.__collectionSelection.visible=!!slot.__collectionItem&&slot.__collectionItem.id===selected;});showTooltip(card,item);});}
function canDraw(){var data=shared.pages[current],s=data&&data.social;return opened&&current!=="wife"&&!shared.pending&&s&&Number(data.pending)!==1&&known(s.tickets)&&known(s.draw_cost)&&Number(s.draw_cost)>0&&Number(s.tickets)>=Number(s.draw_cost)&&known(s.remaining)&&Number(s.remaining)>0;}
function render(){
 if(!alive()||!opened)return;var data=current==="wife"?null:shared.pages[current],s=data&&data.social,rows=array(data&&data.rows);
 Object.keys(tabs).forEach(function(id){tabs[id].SetHasClass("CollectionGW2Selected",id===current);});nodes.CollectionGW2Category.text=names[current];
 renderCards(rows);empty.visible=current==="wife"||!data||!visibleRows.length;
 empty.text=current==="wife"?"暂无收藏配置":!data?"正在读取收藏…":query?"没有找到匹配的收藏":"暂无收藏";
 summary.text=current==="wife"?"奖励暂未配置":data?"已收藏 "+rows.filter(function(item){return countKnown(item)&&Number(item.count)>0;}).length+" / "+rows.length+" 种"+(s?" · 共 "+number(s.total)+" 件":"")+(query?" · 找到 "+visibleRows.length+" 项":""):"等待服务端同步";
 tickets.text=current==="wife"?"":s?String(s.currency_name||"抽取券")+"："+number(s.tickets)+"  ·  每次消耗 "+number(s.draw_cost)+" 张":"正在读取抽取资格…";
 draw.enabled=!!canDraw();draw.SetHasClass("CollectionGW2Disabled",!draw.enabled);drawText.text=current==="wife"?"暂未开放":shared.pending?"结算中…":s&&Number(s.remaining)===0?"已全部集满":"抽取";
 var outcome=shared.outcome&&shared.outcome.pool_id===current?shared.outcome:null;
 result.text=current==="wife"?"该栏目开放后可在此查看收藏。":shared.pending?"奖励正在结算，请稍候…":outcome&&!outcome.ok?outcome.error||"抽取未完成，请稍后重试":data&&data.last_draw&&data.last_draw.pool_id===current?"获得："+data.last_draw.name:s?"重复获得叠加效果 · 剩余数量决定抽取权重":"";
}
function request(full){
 if(!alive()||current==="wife")return;fetching=true;
 GameEvents.SendCustomGameEventToServer("survival_archive_request",{category_id:current,prefetch:full?1:0});
 if(!fetchJob&&opened){fetchJob=life.Later(.8,function(){fetchJob=null;if(!alive())return;if(opened&&current!=="wife"&&(!shared.pages[current]||Object.keys(resync).length))request(true);});}
}
function queueResync(category){resync[category]=true;if(!opened||current==="wife"||fetchJob)return;fetchJob=life.Later(.2,function(){fetchJob=null;if(alive()&&opened)request(true);});}
function snapshot(packet){
 if(!alive()||!packet||["ex","friend"].indexOf(packet.category_id)<0)return;
 var category=packet.category_id,sequence=Number(packet.sequence)||0;if(sequence<=Number(shared.versions[category]||0)||!(packet.ok===true||Number(packet.ok)===1))return;
 var group=assemblies[category];if(!group||sequence>group.sequence)group=assemblies[category]={sequence:sequence,header:copy(packet),chunks:{},count:Number(packet.chunks)||1};
 if(sequence!==group.sequence)return;var chunk=Number(packet.chunk)||1;if(chunk<1||chunk>group.count)return;group.chunks[chunk]=copy(array(packet.rows));
 if(Object.keys(group.chunks).length!==group.count)return;
 var complete=group.header;complete.rows=[];for(var i=1;i<=group.count;i++){if(!group.chunks[i])return;complete.rows=complete.rows.concat(group.chunks[i]);}delete assemblies[category];
 if(Number(complete.delta)===1){if(!shared.pages[category]||Number(shared.versions[category])!==Number(complete.base_sequence)){queueResync(category);return;}complete=cfg.SurvivalSnapshotCache.Apply(shared.pages[category],complete.rows);}else delete resync[category];
 shared.pages[category]=complete;shared.versions[category]=sequence;fetching=false;
 if(shared.pending&&shared.pending.pool_id===category&&(shared.pending.acknowledged?matchesDraw(complete,shared.pending):committedDraw(complete,shared.pending)))shared.pending=null;
 if(opened&&current===category)render();
}
function committedDraw(data,intent){var draw=data&&data.last_draw,suffix=":social_draw:"+intent.request_id;return !!draw&&Number(data.pending)===0&&draw.pool_id===intent.pool_id&&String(draw.id||"").slice(-suffix.length)===suffix;}
function matchesDraw(data,intent){if(!data)return false;if(known(intent.revision))return known(data.revision)&&Number(data.revision)>=Number(intent.revision);return committedDraw(data,intent);}
function drawOne(){
 if(!alive()||!canDraw())return;var requestId="collection_"+Date.now()+"_"+(++shared.serial);
 shared.pending={pool_id:current,request_id:requestId};shared.outcome=null;render();
 GameEvents.SendCustomGameEventToServer("survival_archive_social_draw",{pool_id:current,request_id:requestId});
}
function drawResult(message){
 if(!alive()||!message||!shared.pending)return;var intent=shared.pending;
 if(message.request_id!==intent.request_id||message.pool_id!==intent.pool_id)return;
 // Transient persistence failures remain queued server-side: never issue a new intent.
 if((message.ok===true||Number(message.ok)===1)&&(message.terminal===true||Number(message.terminal)===1)){shared.outcome={pool_id:intent.pool_id,ok:true};if(known(message.revision))intent.revision=Number(message.revision);if(matchesDraw(shared.pages[intent.pool_id],intent))shared.pending=null;else{intent.acknowledged=true;if(opened&&current!=="wife")request(true);}}
 else if(message.terminal===true||Number(message.terminal)===1){shared.outcome={pool_id:intent.pool_id,ok:false,error:message.error};shared.pending=null;}
 render();
}
function recoverIntent(){
 var intent=shared.pending;if(!intent||intent.acknowledged||current==="wife")return;
 var pool=intent.pool_id,requestId=intent.request_id;
 // One delayed replay per closed-to-open transition repairs an ACK lost during
 // layout reload. The original nonce retains the server's idempotency record.
 viewLife.Later(.55,function(){
  if(!alive()||!opened||current==="wife")return;var pending=shared.pending;
  if(!pending||pending.acknowledged||pending.pool_id!==pool||pending.request_id!==requestId)return;
  GameEvents.SendCustomGameEventToServer("survival_archive_social_draw",{pool_id:pool,request_id:requestId});
 });
}
function select(id){if(!alive()||!names[id])return;current=id;query="";selected="";search.text="";searchHint.visible=true;grid.ScrollToTop();hideTooltip();render();if(opened&&id!=="wife"&&!shared.pages[id])request(true);}
function open(id){if(!alive())return;var wasOpen=opened;if(id&&names[id]&&id!==current){current=id;query="";selected="";search.text="";searchHint.visible=true;grid.ScrollToTop();}if(cfg.SurvivalArchive&&cfg.SurvivalArchive.IsOpen&&cfg.SurvivalArchive.IsOpen())cfg.SurvivalArchive.Close();opened=true;win.RemoveClass("ArchiveHidden");scrim.RemoveClass("ArchiveHidden");shell.Open();scale=Number(U.Fit(win,root,size[0],size[1],{reference:size.slice()}))||1;render();if(current!=="wife")request(!shared.pages[current]||Object.keys(resync).length>0);if(!wasOpen)recoverIntent();}
function close(){if(!active)return;opened=false;hideTooltip();viewLife.Cancel();if(valid(win)){shell.Close();win.AddClass("ArchiveHidden");}if(valid(scrim))scrim.AddClass("ArchiveHidden");$.DispatchEvent("DOTAHideTextTooltip");}
function dispose(){if(!active)return;close();active=false;life.Dispose();viewLife.Dispose();shell.Dispose();if(valid(canvas))canvas.DeleteAsync(0);createdRoots.forEach(function(n){if(valid(n))n.DeleteAsync(0);});if(valid(win))win.RemoveClass("CollectionGW2Page");}
api=cfg.SurvivalCollection={Open:open,Close:close,Toggle:function(){if(alive()){if(opened)close();else open();}},Select:select,IsOpen:function(){return alive()&&opened;},Dispose:dispose,Inspect:function(){return {open:opened,layout:"collection_gw2",category:current,search:query,rows:visibleRows.map(function(item){return {id:item.id,name:item.name,count:item.count,target:item.target};}),slots:slots.length,drawEnabled:!!draw.enabled,pending:shared.pending?copy(shared.pending):null,versions:copy(shared.versions),tooltipVisible:valid(tipPanel)&&tipPanel.visible};}};
life.Subscribe("survival_archive_snapshot",snapshot);life.Subscribe("survival_archive_social_result",drawResult);
win.AddClass("ArchiveHidden");scrim.AddClass("ArchiveHidden");shell.Close();
})();
