const params=new URLSearchParams(location.search);cfg.SurvivalQueueLayout=params.get('layout')||'A';
window.selectedEntity=42;
window.setQueueState=function(kind){
 const opts=structuredClone(TRAINING_FIXTURE);let active={},queued=[];const job=i=>({...opts[i%4],job_id:100+i,started_at:90,duration:20,finish_at:110});
 if(['single','waiting','full','complete','types','costs'].includes(kind))active=job(0);
 if(kind==='waiting'||kind==='full')queued=Array.from({length:kind==='full'?6:3},(_,i)=>job(i+1));
 if(kind==='full')opts.forEach(x=>{x.available=0;x.reason='training_queue_full';});
 if(kind==='costs'){opts.splice(0,4);opts.forEach(x=>{x.available=1;});}
 if(kind==='types'){opts[1].training_id='train_repairer_01';opts[1].name='维修工';}
 if(kind==='complete')opts[0].count=5;
 if(kind==='locked')opts.forEach(x=>{x.available=0;x.reason='population_limit';});
 if(kind==='hero')window.selectedEntity=44;else window.selectedEntity=42;
 emit('ui_selected_unit_stats_snapshot',{success:1,player_id:0,entindex:42,training:{options:opts,active_job:active,queued,queue_capacity:7}});
 cfg.SurvivalProductionHUD.Refresh(previewGeometry(),window.selectedEntity,true,[]);
};
window.showArchive=function(mode){nodes.SurvivalProductionPanel.visible=false;const rows=Array.from({length:24},(_,i)=>({id:'preview_'+i,name:i===0&&mode==='long'?'来自服务端的超长存档名称边界测试条目':'通关存档 · 第'+(i+1)+'章',description:'攻击力提升 2%\n每次攻击额外回复生命值',count:i<3?10:0,target:10,unlocked:i<3?1:0,icon_type:'item',icon:['broadsword','skadi','reaver','demon_edge','gloves','ultimate_orb'][i%6]}));emit('survival_archive_snapshot',{ok:1,category_id:'clear',sequence:1,chunk:1,chunks:1,categories:[{id:'clear',name:'通关存档'},{id:'shadow',name:'虚空之影'},{id:'points',name:'积分道具'},{id:'fragment',name:'神兵碎片'},{id:'pet',name:'秘法牢笼'},{id:'endless',name:'无尽存档'},{id:'friend',name:'我的好基友'}],rows});cfg.SurvivalArchive.Toggle();const win=nodes.ArchiveWindow;win.style.position=((innerWidth/previewScale-869)/2)+'px '+((1080-713)/2)+'px 0px';syncFlows();};
if(params.get('page')==='archive')showArchive(params.get('state'));else setQueueState(params.get('state')||'idle');
