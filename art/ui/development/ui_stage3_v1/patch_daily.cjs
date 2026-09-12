// Lifecycle and first-load presentation only; claim authority stays on server.
module.exports=function(source){
 const replace=(from,to)=>{if(source.split(from).length!==2)throw Error('Daily patch anchor: '+from);source=source.replace(from,to);};
 replace('active=true,life=U.Lifecycle(),shell;','active=true,life=U.Lifecycle(),viewLife=U.Lifecycle(),fetching=false,fetchSerial=0,shell;');
 replace('function close(){shell.Close();','function close(){viewLife.Cancel();fetching=false;fetchSerial++;shell.Close();');
 replace('action:function(){claim(data&&data.today);}','action:function(){if(!data){request();return;}claim(data.today);}');
 replace("function request(){if(active)GameEvents.SendCustomGameEventToServer('survival_daily_request',{});}",`function request(){if(!active||fetching)return;fetching=true;var serial=++fetchSerial;if(!data){errorText='';render();}GameEvents.SendCustomGameEventToServer('survival_daily_request',{});if(shell.IsOpen())viewLife.Later(8,function(){if(!active||serial!==fetchSerial||!fetching)return;fetching=false;if(!data){errorText='读取奖励超时，请重试';render();}});else fetching=false;}
function emptyView(){if(!shell.IsOpen())return;p('DailyHeading').text='每日奖励';p('DailyClaimPage').RemoveClass('ArchiveHidden');p('DailyPassPage').AddClass('ArchiveHidden');p('DailySubtitle').text='';p('DailyCount').text='';p('DailyPassStatusText').text='';p('DailyRuleLine').text='';p('DailyCards').RemoveAndDeleteChildren();p('DailyNotice').text=errorText||'正在读取每日奖励…';p('DailyClaimText').text=fetching?'加载中…':'重试加载';spinner.visible=fetching;U.State.Set(p('DailyClaim'),{enabled:!fetching,busy:fetching});U.State.Set(p('DailyMakeup'),{enabled:false});U.State.Set(p('DailyPassStatus'),{enabled:false});}`);
 replace('function render(){if(!data)return;','function render(){if(!data){emptyView();return;}U.State.Set(p(\'DailyPassStatus\'),{enabled:true});');
 replace("life.Subscribe('survival_daily_snapshot',function(next){if(!active)return;","life.Subscribe('survival_daily_snapshot',function(next){if(!active)return;fetching=false;fetchSerial++;");
 replace("data=next;render();});","data=next;if(!waiting&&!(result&&!result.ok))errorText='';render();});");
 replace('function poll(){if(!active)return;if(shell.IsOpen())request();life.Later(3,poll);}life.Later(3,poll);','function poll(){if(!active||!shell.IsOpen())return;request();viewLife.Later(3,poll);}');
 replace('shell.Open();render();request();','shell.Open();viewLife.Cancel();fetching=false;render();request();viewLife.Later(3,poll);');
 replace('active=false;life.Dispose();shell.Dispose();','active=false;viewLife.Dispose();life.Dispose();shell.Dispose();');
 return source;
};
