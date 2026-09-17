// Keep callbacks tied to their own layout; $ selectors may use a newer context.
module.exports=function(source){
 const replace=(from,to)=>{if(source.split(from).length!==2)throw Error('Daily lifetime anchor: '+from);source=source.replace(from,to);};
 replace('function p(id){return $(\'#\'+id);}',"function valid(panel){return panel&&(!panel.IsValid||panel.IsValid());}function p(id){return valid(dailyRoot)?dailyRoot.FindChildTraverse(id):null;}function viewValid(){return valid(p('DailyWindow'));}function stopIfInvalid(){if(!active)return true;if(viewValid())return false;active=false;life.Dispose();if(typeof viewLife!=='undefined')viewLife.Dispose();if(shell)shell.Dispose();return true;}");
 replace('if(cfg.SurvivalDaily&&cfg.SurvivalDaily.Dispose)',"var dailyRoot=$.GetContextPanel();if(!viewValid()){active=false;return;}\nif(cfg.SurvivalDaily&&cfg.SurvivalDaily.Dispose)");
 replace('function close(){','function close(){if(!active)return;');
 // Close can be requested while a native layout is being destroyed.
 source=source.replace(/p\('(DailyWindow|DailyScrim|DailyRulesText|DailyTooltip)'\)\.AddClass\('ArchiveHidden'\);/g,
  (_,id)=>"if(valid(p('"+id+"')))p('"+id+"').AddClass('ArchiveHidden');");
 replace('function render(){','function render(){if(stopIfInvalid())return;');
 replace('function request(){if(!active','function request(){if(stopIfInvalid())return;if(!active');
 replace('Open:function(pass){',"Open:function(pass){if(!active||!viewValid())return;");
 source=source.replace('function poll(){if(!active', 'function poll(){if(stopIfInvalid()||!active');
 return source;
};
