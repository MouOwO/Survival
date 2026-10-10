'use strict';
// Existing, verified private Tools map only. No launch/force-kill/account APIs.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=path.resolve(__dirname,'..');
const label=process.argv[2]||'capture',towers=Number(process.argv[3]||32),enemies=Number(process.argv[4]||96);
if(!/^[a-z0-9_]+$/.test(label)||![towers,enemies].every(Number.isInteger)||towers<4||towers>96||enemies<4||enemies>256)throw Error('Invalid private capture arguments');
const out=path.join(root,'output/late_combat_20261008',label);fs.mkdirSync(out,{recursive:true});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function send(name,requests,expect=''){
  const file=path.join(out,name+'.json');fs.writeFileSync(file,JSON.stringify(requests));
  const result=cp.spawnSync(process.execPath,[path.join(__dirname,'map_c6/console.cjs'),'--file',file,'--timeout-ms','5000',...(expect?['--expect',expect]:[])],{cwd:root,encoding:'utf8',windowsHide:true,timeout:20000,maxBuffer:128e6});
  fs.writeFileSync(path.join(out,name+'.txt'),result.stdout||'');
  if(result.status!==0)throw Error(name+': '+(result.stderr||result.error||'console failure'));
  return result.stdout;
}
const lua=code=>({name:'dota_run_lua',arguments:{code}}),consoleCommands=commands=>({name:'console_send',arguments:{commands}});
(async()=>{
  try{
    send('start',[lua(`assert(IsInToolsMode() and GetMapName()=='template_map');PauseGame(false);package.loaded['tests/manual_late_combat_stress']=nil;require('tests/manual_late_combat_stress').start(${towers},${enemies},80);print('LATE_CAPTURE_STARTED')`)],'LATE_CAPTURE_STARTED');
    // A minimized Workshop window throttles rendering and produces 0 FPS
    // samples. Show only the verified private game; no keys/clicks are sent.
    const show=cp.spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'map_c6/window.ps1'),'-Show'],{cwd:root,windowsHide:true,encoding:'utf8',timeout:20000});
    fs.writeFileSync(path.join(out,'window.txt'),show.stdout||'');
    if(show.status!==0)throw Error('Private test window unavailable: '+show.stderr);
    console.log('LATE_CAPTURE_WARMUP',label);await sleep(10000);
    const screenshot=cp.spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'map_c6/window.ps1'),'-Show','-Screenshot',`late_${label}.png`],{cwd:root,windowsHide:true,encoding:'utf8',timeout:20000});
    if(screenshot.status!==0)throw Error('Battlefield screenshot unavailable: '+screenshot.stderr);
    send('begin',[consoleCommands('cl_showfps 1\ncl_resetfps\nvprof_off\nvprof_on\nvprof_reset'),lua("assert(GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS);assert(require('systems/startup_loading_service').is_player_ready(0));assert(not GameRules:IsGamePaused(),'Paused benchmark rejected');SURVIVAL_LATE_CAPTURE_CLOCK={wall=Time(),game=GameRules:GetGameTime()};require('tests/manual_late_combat_stress').begin_measurement();print('LATE_CAPTURE_MEASURING')")],'LATE_CAPTURE_MEASURING');
    console.log('LATE_CAPTURE_MEASURING',label);await sleep(25000);
    // VProf prints asynchronously on the client; drain instead of ending on
    // the earlier server marker and accidentally truncating the native report.
    const report=send('performance',[consoleCommands('cl_printfps\nvprof_generate_report\nvprof_off'),lua("local c=SURVIVAL_LATE_CAPTURE_CLOCK;local wall,game=Time()-c.wall,GameRules:GetGameTime()-c.game;print(string.format('[LATE_CLOCK_VALIDATION] wall=%.3f game=%.3f paused=%s ratio=%.3f',wall,game,tostring(GameRules:IsGamePaused()),game/wall));require('tests/manual_late_combat_stress').report();print('LATE_CAPTURE_REPORT')")]);
    const clock=report.match(/\[LATE_CLOCK_VALIDATION\] wall=([\d.]+) game=([\d.]+) paused=(\w+) ratio=([\d.]+)/);
    if(!clock||clock[3]!=='false'||Number(clock[4])<0.85||Number(clock[4])>1.15)throw Error('Invalid paused/time-scaled capture; results excluded');
    if(!report.match(/1000 frames:.*total frames:\s*[1-9]/))throw Error('No rendered FPS samples; minimized/background results excluded');
    console.log(report.split(/\r?\n/).filter(line=>/frames:|Average .*fps|Peak .*frame|BOSS_PERF.*snapshot/.test(line)).join('\n'));
    send('particles',[consoleCommands('cl_particles_dumpsimlist'),lua("print('LATE_CAPTURE_PARTICLES')")]);
    console.log('LATE_CAPTURE_DONE',label);
  }finally{
    send('cleanup',[lua("require('tests/manual_late_combat_stress').stop();local p=package.loaded['tests/manual_boss_performance'];if p then p.stop('cleanup') end;print('LATE_CAPTURE_CLEAN')"),consoleCommands('cl_showfps 0\nvprof_off')]);
  }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
