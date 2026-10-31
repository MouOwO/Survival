"""Run 32 synthetic contracts against the actual neighboring input helper.

Requires pwsh and its C# compiler. Every user32 import is replaced with managed
mocks before execution; CIM, COM creation and waits are also mocked. Dates/PIDs
are fictional. There is no live mode, clipboard access, or real UI/input call.
Temporary scripts/logs are cleaned on exit. Source hashes are computed, not
pinned to a particular helper version. This is not real Dota/FPS verification.
Run: python -B tools/arcade_portrait_perf_20261031/test_input_contract.py
"""
from pathlib import Path
import atexit,base64,hashlib,json,re,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
_temporary=tempfile.TemporaryDirectory(prefix='survival-input-contract-')
atexit.register(_temporary.cleanup)
out=Path(_temporary.name)
helper=Path(__file__).with_name('input_arcade.ps1')
source=helper.read_text('utf8')
native=re.search(r"(?s)Add-Type @'\n(.*?)\n'@",source).group(1)
bodies={
 'SendInput':'''FakeSendCalls++;uint sent=FakePartial?1u:n;FakePartial=false;if(FakeScenario=="ascii_key_fail"&&FakeSendCalls==8)sent=0;for(int i=0;i<sent;i++){bool up=a[i].T==1?(a[i].V.Key.F&2)!=0:(a[i].V.Mouse.F&4)!=0;int key=a[i].V.Key.V;FakeKeys+=(a[i].T==1?key.ToString():"M")+(up?"U":"D")+",";if(a[i].T==1){if((a[i].V.Key.F&4)!=0){FakeUnicodeEvents++;if(!up)FakeTyped+=(char)a[i].V.Key.S;}else{if(key==16)FakeShift=!up;else if(key==17)FakeControl=!up;else if(key==18)FakeAlt=!up;else if(!up){char c=(char)key;if(key>=65&&key<=90)c=(char)(FakeShift?key:key+32);else if(key==189)c=FakeShift||(FakeControl&&FakeAlt)?'_':'-';else if(key==191)c='/';else if(key==190)c='.';FakeTyped+=c;}}if(!up&&((FakeScenario=="ascii_shift_foreign"&&key==16)||(FakeScenario=="ascii_ctrl_foreign"&&key==17)||(FakeScenario=="ascii_alt_foreign"&&key==18)||(FakeScenario=="ascii_key_foreign"&&key!=16&&key!=17&&key!=18)))FakeForeground=new IntPtr(3000);}}if(FakeScenario=="text_foreign"||FakeScenario=="ctrl_foreign")FakeForeground=new IntPtr(3000);if(FakeScenario=="key_aux"||FakeScenario=="click_aux")FakeForeground=new IntPtr(2000);return sent;''',
 'EnumWindows':'''p(new IntPtr(1000),d);p(new IntPtr(2000),d);p(new IntPtr(3000),d);if(FakeScenario=="duplicate"||FakeScenario=="ambiguous")p(new IntPtr(4000),d);return true;''',
 'GetWindowText':'''string v=h.ToInt64()==1000||h.ToInt64()==4000?"Dota 2":h.ToInt64()==2000?"":"Foreign";t.Append(v);return v.Length;''',
 'IsWindow':'''return h!=IntPtr.Zero;''',
 'IsWindowVisible':'''return true;''',
 'IsIconic':'''return false;''',
 'GetForegroundWindow':'''return FakeForeground;''',
 'ClientToScreen':'''p.X+=100;p.Y+=100;return true;''',
 'GetClientRect':'''r=new R{L=0,T=0,Rt=h.ToInt64()==2000?0:1600,B=h.ToInt64()==2000?0:900};return true;''',
 'SetCursorPos':'''FakeCursorCalls++;return FakeScenario!="cursor_fail";''',
 'WindowFromPoint':'''return new IntPtr(1000);''',
 'GetAncestor':'''return h;''',
 'GetWindowThreadProcessId':'''p=(h.ToInt64()==3000||(h.ToInt64()==4000&&FakeScenario=="ambiguous"))?77u:42u;return 70;''',
 'SetThreadDpiAwarenessContext':'''FakeDpiCalls++;return FakeScenario=="dpi_fail"&&c.ToInt64()==-4?IntPtr.Zero:new IntPtr(-2);''',
 'GetKeyboardLayout':'''FakeLayoutCalls++;FakeLayoutThread=thread;return new IntPtr(FakeScenario=="ascii_layout_change"&&FakeLayoutCalls>2?0x4090408:0x4090409);''',
 'VkKeyScanEx':'''if(c=='_'&&FakeScenario=="ascii_unmap")return -1;if(c=='_'&&FakeScenario=="ascii_badflags")return 0x8BD;if(c=='_'&&(FakeScenario=="ascii_altgr"||FakeScenario=="ascii_ctrl_foreign"||FakeScenario=="ascii_alt_foreign"))return 0x6BD;if(c>='a'&&c<='z')return (short)(c-32);if(c>='A'&&c<='Z')return (short)(0x100+c);if(c>='0'&&c<='9')return (short)c;if(c=='_')return 0x1BD;if(c=='/')return 191;if(c=='.')return 190;if(c==' ')return 32;if(c=='-')return 189;return -1;''',
 'GetAsyncKeyState':'''return (short)((FakeScenario=="ascii_preheld"&&key==16)||(key==16&&FakeShift)||(key==17&&FakeControl)||(key==18&&FakeAlt)?-32768:0);'''
}
replaced=[]
def replace(match):
 signature=match[1];name=re.search(r'\b(\w+)\(',signature).group(1);replaced.append(name)
 return 'public static '+signature+'{'+bodies[name]+'}'
mock=re.sub(r'\[DllImport\([^\]]+\)\]public static extern ([^;]+);',replace,native)
assert set(replaced)==set(bodies) and 'DllImport' not in mock and ' extern ' not in mock
mock=mock.replace('public static class ArcadeInput {','''public static class ArcadeInput {
 public static string FakeScenario,FakeKeys="";public static IntPtr FakeForeground=new IntPtr(1000);
 public static int FakeSendCalls,FakeCursorCalls,FakeDpiCalls,FakeFocusCalls,FakeUnicodeEvents,FakeLayoutCalls;public static uint FakeLayoutThread;public static bool FakePartial,FakeShift,FakeControl,FakeAlt;public static string FakeTyped="";
''')
mock+='''
public class FakeShell {public bool AppActivate(string title){ArcadeInput.FakeFocusCalls++;if(title!="Dota 2")throw new Exception("bad_title");if(ArcadeInput.FakeScenario=="focus_false")return false;ArcadeInput.FakeForeground=new IntPtr(ArcadeInput.FakeScenario=="focus_wrong"?3000:1000);return true;}}
'''
cases=[
 ('normal_key','normal',{'Action':'Key','Key':'Enter'},'ACTION_COMPLETED',2,0),
 ('normal_text','normal',{'Action':'Text','Text':'sv_cheats'},'ACTION_COMPLETED',18,0),
 ('reject_aux','aux',{'Action':'Key','Key':'Enter'},'ERROR',0,0),
 ('reject_foreign','foreign',{'Action':'Text','Text':'sv_cheats'},'ERROR',0,0),
 ('key_release_after_aux','key_aux',{'Action':'Key','Key':'Enter'},'ACTION_COMPLETED_FOCUS_CHANGED',2,0),
 ('text_stops_after_foreign','text_foreign',{'Action':'Text','Text':'sv_cheats'},'ACTION_STOPPED_FOCUS_CHANGED',2,0),
 ('ctrl_release_after_foreign','ctrl_foreign',{'Action':'Key','Key':'CtrlA'},'ACTION_STOPPED_FOCUS_CHANGED',2,0),
 ('reject_dpi_failure','dpi_fail',{'Action':'Click','X':2,'Y':2},'ERROR',0,0),
 ('reject_cursor_failure','cursor_fail',{'Action':'Click','X':2,'Y':2},'ERROR',0,0),
 ('explicit_focus','focus_ok',{'Action':'Focus'},'FOCUS_ESTABLISHED',0,1),
 ('focus_false_no_retry','focus_false',{'Action':'Focus'},'FOCUS_NOT_ESTABLISHED',0,1),
 ('focus_wrong_no_input','focus_wrong',{'Action':'Focus'},'FOCUS_NOT_ESTABLISHED',0,1),
 ('reject_ambiguous_title','ambiguous',{'Action':'Focus'},'ERROR',0,0),
 ('reject_duplicate_main','duplicate',{'Action':'Key','Key':'Enter'},'ERROR',0,0),
 ('partial_text_releases','partial',{'Action':'Text','Text':'sv_cheats'},'ERROR',2,0),
 ('reject_unlisted_text','normal',{'Action':'Text','Text':'arbitrary_command'},'ERROR',0,0),
 ('normal_click','normal',{'Action':'Click','X':2,'Y':2},'ACTION_COMPLETED',2,0),
 ('click_release_after_aux','click_aux',{'Action':'Click','X':2,'Y':2},'ACTION_COMPLETED_FOCUS_CHANGED',2,0),
]
def ascii_events(text,altgr=False):return 2*len(text)+2*sum(c.isupper() or c=='_' for c in text)+(2*text.count('_') if altgr else 0)
for name,scenario,text,status,events in [
 ('ascii_underscore','normal','con_enable','ACTION_COMPLETED',ascii_events('con_enable')),
 ('ascii_slash_path','normal','con_logfile output/arcade_portrait_perf_20261031/test_log.log','ACTION_COMPLETED',ascii_events('con_logfile output/arcade_portrait_perf_20261031/test_log.log')),
 ('ascii_uppercase','normal','echo ARCADE_READONLY_ACK','ACTION_COMPLETED',ascii_events('echo ARCADE_READONLY_ACK')),
 ('ascii_altgr_modifiers','ascii_altgr','con_enable','ACTION_COMPLETED',ascii_events('con_enable',True)),
 ('ascii_reject_nonascii','normal','控制台','ERROR',0),
 ('ascii_reject_unmappable','ascii_unmap','con_enable','ERROR',0),
 ('ascii_reject_unknown_modifiers','ascii_badflags','con_enable','ERROR',0),
 ('ascii_shift_release_on_focusloss','ascii_shift_foreign','con_enable','ACTION_STOPPED_FOCUS_CHANGED',8),
 ('ascii_ctrl_release_on_focusloss','ascii_ctrl_foreign','con_enable','ACTION_STOPPED_FOCUS_CHANGED',8),
 ('ascii_alt_release_on_focusloss','ascii_alt_foreign','con_enable','ACTION_STOPPED_FOCUS_CHANGED',10),
 ('ascii_base_release_on_focusloss','ascii_key_foreign','con_enable','ACTION_STOPPED_FOCUS_CHANGED',2),
 ('ascii_layout_change_stops','ascii_layout_change','con_enable','ERROR',2),
 ('ascii_preheld_modifiers_rejected','ascii_preheld','con_enable','ERROR',0),
 ('ascii_failed_base_releases_shift','ascii_key_fail','con_enable','ERROR',8),
]:cases.append((name,scenario,{'Action':'Text','TextMode':'AsciiKeys','Text':text},status,events,0))
results=[]
for name,scenario,params,status,events,focus in cases:
 script="$ErrorActionPreference='Stop'\nAdd-Type @'\n"+mock+"\n'@\n"
 script+="function Get-CimInstance { [pscustomobject]@{Name='dota2.exe';CommandLine='dota2.exe -steam';CreationDate=[datetime]::Parse('2026-01-01T00:00:00Z').ToUniversalTime()} }\n"
 script+="function Start-Sleep {param([int]$Milliseconds)}\nfunction New-Object {param([string]$ComObject);if($ComObject -ne 'WScript.Shell'){throw 'unexpected_COM'};return [FakeShell]::new()}\n"
 script+="[ArcadeInput]::FakeScenario='"+scenario+"'\n"
 if scenario in ('aux','focus_ok','focus_false','focus_wrong'):script+='[ArcadeInput]::FakeForeground=[IntPtr]::new(2000)\n'
 if scenario=='foreign':script+='[ArcadeInput]::FakeForeground=[IntPtr]::new(3000)\n'
 if scenario=='partial':script+='[ArcadeInput]::FakePartial=$true\n'
 script+="$actual=[scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+base64.b64encode(source.encode()).decode()+"')))\n"
 script+="$argsMap=ConvertFrom-Json -AsHashtable @'\n"+json.dumps(params)+"\n'@\n"
 script+="try{$answer=& $actual -GameProcessId 42 -CreatedUtc '2026-01-01T00:00:00Z' @argsMap;$value=$answer|ConvertFrom-Json}catch{$value=[pscustomobject]@{status='ERROR';error=$_.Exception.Message}}\n"
 script+="[ordered]@{result=$value;events_inserted=[ArcadeInput]::EventsInserted;focus_calls=[ArcadeInput]::FakeFocusCalls;keys=[ArcadeInput]::FakeKeys;send_calls=[ArcadeInput]::FakeSendCalls;cursor_calls=[ArcadeInput]::FakeCursorCalls;typed=[ArcadeInput]::FakeTyped;unicode_events=[ArcadeInput]::FakeUnicodeEvents;layout_thread=[ArcadeInput]::FakeLayoutThread;shift_held=[ArcadeInput]::FakeShift;control_held=[ArcadeInput]::FakeControl;alt_held=[ArcadeInput]::FakeAlt;real_UI_calls=0}|ConvertTo-Json -Compress -Depth 6\n"
 path=out/(name+'.ps1');path.write_text(script,encoding='utf8')
 run=subprocess.run(['pwsh','-NoProfile','-NonInteractive','-File',str(path)],capture_output=True,text=True,
  encoding='utf8',errors='replace',timeout=30,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
 (out/(name+'.log')).write_text(run.stdout+run.stderr,encoding='utf8')
 assert run.returncode==0,(name,run.stderr)
 value=json.loads(run.stdout.strip())
 assert value['result']['status']==status and value['events_inserted']==events and value['focus_calls']==focus,(name,value)
 if name=='ctrl_release_after_foreign':assert value['keys']=='17D,17U,'
 if name in ('key_release_after_aux','normal_key'):assert value['keys']=='13D,13U,'
 if name in ('click_release_after_aux','normal_click'):assert value['keys']=='MD,MU,'
 if name=='reject_cursor_failure':assert value['cursor_calls']==1 and value['send_calls']==0
 if status=='ACTION_STOPPED_FOCUS_CHANGED':assert value['result']['focus_changed'] and value['result']['stopped_on_focus_change']
 if params.get('TextMode')=='AsciiKeys':
  assert value['unicode_events']==0 and value['layout_thread']==70 and not any(value[k] for k in ('shift_held','control_held','alt_held')),(name,value)
  if status=='ACTION_COMPLETED':assert value['typed']==params['Text'],(name,value)
  if name=='ascii_underscore':assert '16D,189D,189U,16U,' in value['keys']
  if name=='ascii_slash_path':assert '191D,191U,' in value['keys']
  if name=='ascii_uppercase':assert '16D,65D,65U,16U,' in value['keys']
  if name=='ascii_altgr_modifiers':assert '17D,18D,189D,189U,18U,17U,' in value['keys']
 results.append({'case':name,'passed':True,'status':status,'simulated_events':events,'simulated_focus_calls':focus})
receipt={'status':'INPUT_HELPER_ISOLATED_CONTRACT_PASS','source_sha256':hashlib.sha256(helper.read_bytes()).hexdigest(),'tests':results,'real_UI_calls':0,'real_SendInput_calls':0,'real_COM_calls':0,'all_native_imports_replaced':True}
(out/'checks.json').write_text(json.dumps(receipt,indent=2),encoding='utf8')
print(json.dumps({'status':receipt['status'],'cases':len(results),'real_UI_calls':0,'real_SendInput_calls':0,'real_COM_calls':0}))
