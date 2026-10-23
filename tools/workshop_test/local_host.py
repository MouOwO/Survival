"""Owner-approved local test connector for the frozen, isolated four-account build.

Cloud credentials remain outside Dota and Git. The game receives only a fresh
loopback credential. No original backend, database, or existing game is changed.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import queue
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import traceback
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import aliyun_game_test_auth as private_files
import build_runtime_release as runtime

BASE=Path('D:/Survival_发布候选/20261023_ws4_auth_v03')
BASE_SHA='a8ad3b474799bbc07821b568120ec442a2c25a74826fe2e0e92696a09ca36335'
ADDON='survival_ws4_local'
STAGE=ROOT.parent/ADDON
CONTENT=ROOT.parents[2]/'content/dota_addons'/ADDON
OUTPUT=ROOT/'output/ws4_local'
HERE=Path(__file__).resolve().parent
URL='https://pay.xiaofengnet.com/ws4'
PORT=18766
CONSOLE_PORT=29003
STEAMIDS=('76561198424163156','76561198845461206','76561198104787442','76561198974301984')
ACCOUNTS={str(int(s)-76561197960265728) for s in STEAMIDS}
OWNER_ACCOUNT=str(76561198845461206-76561197960265728)
PATHS=frozenset('/v1/'+p for p in ('session/authenticate','session/login','profile',
    'lottery/catalog','lottery/snapshot','archive/config','archive/command','archive/endless-batch',
    'archive/endless-leaderboard','online-time/checkpoint','rewards/grant'))
PRIVATE_REL='scripts/vscripts/ws4_local_launcher/session.kv'
INSTALL_MANIFEST='_ws4_local_install.json'
# Tools writes these root-level caches after opening an addon. They are not
# runtime assets; still reject links, unknown files and any changed frozen byte.
TOOLS_CACHE_FILES=frozenset(('tools_asset_info.bin','tools_thumbnail_cache.sqlite3',
    'tools_thumbnail_cache.sqlite3-journal','tools_thumbnail_cache.sqlite3-wal',
    'tools_thumbnail_cache.sqlite3-shm'))
HIDDEN=getattr(subprocess,'CREATE_NO_WINDOW',0)


class LocalError(RuntimeError):pass


def need(value,code):
    if not value:raise LocalError(code)


def json_file(path,maximum=16*1024*1024):
    private_files.no_reparse(path)
    need(path.is_file() and path.stat().st_size<=maximum,'local_file_invalid')
    return json.loads(path.read_text(encoding='utf-8'))


def report(value):
    OUTPUT.mkdir(parents=True,exist_ok=True)
    runtime.atomic_write_json(OUTPUT/'status.json',value)
    return value


def baseline():
    need((BASE/'_release_manifest.json').is_file(),'host_frozen_release_missing')
    data=json_file(BASE/'_release_manifest.json')
    runtime.validate_manifest(data)
    need(data['content_sha256']==BASE_SHA and data['file_count']==6623,'frozen_release_identity_mismatch')
    return data


def overlay(base):
    route='scripts/vscripts/systems/workshop_connection.lua'
    original=(BASE/route).read_bytes()
    row=next(r for r in base['files'] if r['path']==route)
    need(hashlib.sha256(original).hexdigest()==row['sha256'],'frozen_route_changed')
    before=b'if IsInToolsMode and IsInToolsMode() then return local_url, local_token end'
    after=b'if IsInToolsMode and IsInToolsMode() then return "http://127.0.0.1:18766", local_token end'
    need(original.count(before)==1,'local_route_patch_not_unique')
    result={route:original.replace(before,after,1),
        'scripts/vscripts/config/ws4_local_launcher.lua':
            ('return {kind="WS4-LOCAL-1", proxy_port=18766, base_content_sha256="'+BASE_SHA+'"}\n').encode()}
    for target,source in (('status','local_status'),('probe','local_probe'),('apply','local_apply')):
        raw=(HERE/(source+'.lua')).read_text(encoding='utf8')
        if target=='apply':raw=raw.replace('__RECOVERY__',private_files.recovery_lua())
        result['scripts/vscripts/ws4_local_launcher/'+target+'.lua']=raw.encode('utf8')
    return result


def expected_manifest(base,patches):
    rows={r['path']:dict(r) for r in base['files']}
    for name,raw in patches.items():
        rows[name]={'path':name,'bytes':len(raw),'md5':hashlib.md5(raw).hexdigest(),
                    'sha256':hashlib.sha256(raw).hexdigest()}
    files=sorted(rows.values(),key=lambda r:r['path'])
    data={'schema':2,'kind':'runtime_release_allowlist','hash_algorithms':['md5','sha256'],
          'file_count':len(files),'bytes':sum(r['bytes'] for r in files),'files':files}
    data['content_sha256']=hashlib.sha256(runtime.manifest_payload(data)).hexdigest()
    return data


def verify_stage(data):
    private_files.no_reparse(STAGE)
    expected={r['path']:r for r in data['files']}
    actual=set()
    for path in STAGE.rglob('*'):
        private_files.no_reparse(path)
        if path.is_file():actual.add(path.relative_to(STAGE).as_posix())
    need(actual-{INSTALL_MANIFEST,PRIVATE_REL}-TOOLS_CACHE_FILES==set(expected),'local_stage_file_set_changed')
    for name,row in expected.items():
        need(runtime.checksums(STAGE/name)=={k:row[k] for k in ('bytes','md5','sha256')},
             'local_stage_bytes_changed')


def install(refresh=False):
    need(STAGE.absolute()==(ROOT.parent/'survival_ws4_local').absolute(),'local_stage_path_invalid')
    private_files.no_reparse(STAGE)
    base=baseline();patches=overlay(base);expected=expected_manifest(base,patches)
    if STAGE.exists():
        previous=json_file(STAGE/INSTALL_MANIFEST)
        need(previous.get('base_content_sha256')==BASE_SHA and previous.get('kind')=='WS4-LOCAL-1',
             'unowned_local_stage')
        old=previous['runtime'];runtime.validate_manifest(old)
        old_rows={r['path']:r for r in old['files']}
        need(set(old_rows)=={r['path'] for r in expected['files']},'local_stage_layout_changed')
        for row in base['files']:
            if row['path'] not in patches:need(old_rows[row['path']]==row,'local_stage_baseline_changed')
        verify_stage(old)
        if old['content_sha256']!=expected['content_sha256']:
            need(refresh,'local_overlay_update_requires_install_refresh')
            for name,raw in patches.items():(STAGE/name).write_bytes(raw)
        else:return {'ok':True,'status':'LOCAL_FROZEN_STAGE_VERIFIED','files':expected['file_count']}
    else:
        verified=runtime.verify(BASE,base)
        need(verified['ok'],'frozen_release_bytes_changed')
        STAGE.mkdir()
        for row in base['files']:
            dest=STAGE/row['path'];dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(BASE/row['path'],dest)
        for name,raw in patches.items():
            dest=STAGE/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
    runtime.atomic_write_json(STAGE/INSTALL_MANIFEST,
        {'kind':'WS4-LOCAL-1','base_content_sha256':BASE_SHA,'runtime':expected})
    verify_stage(expected)
    private_files.no_reparse(CONTENT)
    if not CONTENT.exists():CONTENT.mkdir(parents=True)
    marker=CONTENT/'ws4_local_owner.txt'
    if marker.exists():need(marker.read_text()=='WS4-LOCAL-1\n','local_content_marker_changed')
    else:marker.write_text('WS4-LOCAL-1\n')
    return {'ok':True,'status':'LOCAL_FROZEN_STAGE_INSTALLED','files':expected['file_count'],
            'base_runtime_unchanged_except_local_route':True}


def credential_path():
    return Path(os.environ.get('LOCALAPPDATA',str(Path.home()/'AppData/Local')))/'SurvivalWS4/local-host.json'


def private_write(path,raw):
    private_files.no_reparse(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf8'):pass
    private_files.private_acl(path)
    private_files.no_reparse(path)
    path.write_text(raw,encoding='utf8')


def provision():
    path=credential_path()
    private_files.no_reparse(path)
    if path.exists():
        private_files.private_acl(path)
        data=json_file(path,4096)
        need(data.get('workshop_id')=='3824360109' and data.get('kind')=='WS4-LOCAL-1',
             'local_connector_identity_mismatch')
        key=data.get('cloud_key')
        need(isinstance(key,str) and re.fullmatch('[a-f0-9]{64}',key),'local_connector_key_invalid')
    else:
        key=secrets.token_hex(32)
        private_write(path,json.dumps({'kind':'WS4-LOCAL-1','workshop_id':'3824360109','cloud_key':key})+'\n')
    digest=hashlib.sha256(key.encode('ascii')).hexdigest()
    process=subprocess.run([sys.executable,'-B',str(HERE/'deploy.py'),'register_local_host',
        '--local-host-sha256',digest],cwd=ROOT,capture_output=True,timeout=300,creationflags=HIDDEN)
    need(process.returncode==0,'local_connector_registration_failed')
    response=json.loads(process.stdout)
    need(response.get('ok') is True and response.get('local_host_registered') is True,
         'local_connector_registration_not_confirmed')
    return key


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None


def cloud_request(key,path,payload):
    need(path in PATHS,'local_route_not_allowed')
    request=urllib.request.Request(URL+path,data=payload,
        headers={'Authorization':'Bearer '+key,'Content-Type':'application/json; charset=utf-8'},method='POST')
    opener=urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(request,timeout=30) as response:status,body=response.status,response.read(8*1024*1024+1)
    except urllib.error.HTTPError as response:status,body=response.code,response.read(8*1024*1024+1)
    need(len(body)<=8*1024*1024,'cloud_response_too_large')
    need(isinstance(json.loads(body),dict),'cloud_response_invalid')
    return status,body


def proxy_handler(local_key,forward):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def reply(self,status,body):
            if not isinstance(body,bytes):body=json.dumps(body).encode()
            self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(body)))
            self.end_headers();self.wfile.write(body)
        def do_GET(self):
            self.reply(200 if self.path=='/health' else 404,
                {'ok':self.path=='/health','kind':'WS4-LOCAL-1'})
        def do_POST(self):
            supplied=self.headers.get('Authorization','').encode('utf8')
            if not hmac.compare_digest(supplied,('Bearer '+local_key).encode()):
                self.reply(403,{'ok':False,'error':'local_connector_not_authorized'});return
            if self.path not in PATHS:
                self.reply(404,{'ok':False,'error':'local_route_not_allowed'});return
            sizes=self.headers.get_all('Content-Length',[])
            if (self.headers.get('Transfer-Encoding') or len(sizes)!=1
                    or not re.fullmatch('[0-9]{1,6}',sizes[0]) or not 0<int(sizes[0])<=16384):
                self.reply(413,{'ok':False,'error':'local_body_size_invalid'});return
            try:
                raw=self.rfile.read(int(sizes[0]));payload=json.loads(raw)
                if not isinstance(payload,dict):raise ValueError()
            except (ValueError,UnicodeError):
                self.reply(400,{'ok':False,'error':'local_json_invalid'});return
            if 'account_id' in payload and (not isinstance(payload['account_id'],str)
                                            or payload['account_id'] not in ACCOUNTS):
                self.reply(403,{'ok':False,'error':'test_account_not_allowed'});return
            try:status,body=forward(self.path,raw)
            except Exception:
                self.reply(502,{'ok':False,'error':'isolated_backend_unreachable'});return
            self.reply(status,body)
    return Handler


@contextmanager
def proxy(key):
    local_key=secrets.token_hex(32)
    try:
        server=ThreadingHTTPServer(('127.0.0.1',PORT),proxy_handler(local_key,
            lambda path,body:cloud_request(key,path,body)))
    except OSError:raise LocalError('local_proxy_port_unavailable') from None
    server.daemon_threads=True
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:yield local_key
    finally:server.shutdown();server.server_close();thread.join(timeout=3)


def preflight(key):
    session='ws4-local-preflight-'+secrets.token_hex(8)
    for account in sorted(ACCOUNTS):
        payload=json.dumps({'account_id':account,'match_session_id':session}).encode()
        status,raw=cloud_request(key,'/v1/session/authenticate',payload)
        body=json.loads(raw)
        need(status==200 and body.get('authenticated') is True and body.get('account_id')==account
             and body.get('match_session_id')==session,'isolated_cloud_authentication_failed')
    status,raw=cloud_request(key,'/v1/session/authenticate',
        json.dumps({'account_id':'42','match_session_id':session}).encode())
    need(status==403 and json.loads(raw).get('error')=='test_account_not_allowed','isolated_fifth_account_not_rejected')
    with proxy(key) as local_key:
        import http.client
        def request(account,token,path='/v1/session/authenticate',extra=None):
            connection=http.client.HTTPConnection('127.0.0.1',PORT,timeout=35)
            try:
                payload={'account_id':account,'match_session_id':session}
                if extra:payload.update(extra)
                connection.request('POST',path,json.dumps(payload),
                    {'Authorization':'Bearer '+token})
                response=connection.getresponse();return response.status,json.loads(response.read())
            finally:connection.close()
        status,body=request(OWNER_ACCOUNT,local_key)
        need(status==200 and body.get('authenticated') is True,'local_relay_authentication_failed')
        status,body=request(OWNER_ACCOUNT,local_key,'/v1/session/login',{'mode':'standard'})
        need(status==200 and body.get('account_id')==OWNER_ACCOUNT and body.get('match_session_id')==session
             and body.get('mode')=='standard','local_relay_profile_login_failed')
        status,body=request(OWNER_ACCOUNT,local_key,'/v1/profile')
        need(status==200 and body.get('account_id')==OWNER_ACCOUNT and body.get('match_session_id')==session
             and body.get('mode')=='standard','local_relay_profile_read_failed')
        need(request('42',local_key)[0]==403,'local_relay_fifth_account_not_rejected')
        need(request(OWNER_ACCOUNT,'invalid')[0]==403,'local_relay_unauthenticated_request_accepted')
        need(request(OWNER_ACCOUNT,local_key,'/v1/payment/create')[0]==404,'local_relay_payment_route_exposed')
    return {'ok':True,'status':'ISOLATED_LOCAL_CONNECTOR_PREFLIGHT_PASSED','four_account_gate_preserved':True,
            'cloud_accounts_authenticated':4,'local_http_relay_verified':True,'payment_route_rejected':True,
            'standard_profile_login_and_read_verified':True}


class Console:
    def __init__(self):
        node=shutil.which('node.exe') or shutil.which('node')
        need(node is not None,'node_unavailable')
        self.proc=subprocess.Popen([node,str(HERE/'local_console.cjs')],cwd=ROOT,
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
            text=True,encoding='utf8',creationflags=HIDDEN)
        self.rows=queue.Queue();self.serial=0
        def read():
            try:
                for line in self.proc.stdout:
                    if len(line)>8192:break
                    self.rows.put(json.loads(line))
            except Exception:pass
            finally:self.rows.put(None)
        threading.Thread(target=read,daemon=True).start()
    def ask(self,op):
        self.serial+=1
        need(self.proc.poll() is None,'local_console_worker_closed')
        self.proc.stdin.write(json.dumps({'id':self.serial,'op':op})+'\n');self.proc.stdin.flush()
        try:row=self.rows.get(timeout=35)
        except queue.Empty:raise LocalError('local_console_timeout') from None
        need(isinstance(row,dict) and row.get('id')==self.serial,'local_console_protocol_invalid')
        return row
    def close(self):
        if self.proc.poll() is None:
            self.proc.stdin.close()
            try:self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:self.proc.terminate();self.proc.wait(timeout=5)


@contextmanager
def instance_lock():
    import msvcrt
    OUTPUT.mkdir(parents=True,exist_ok=True)
    path=OUTPUT/'launcher.lock';private_files.no_reparse(path)
    with path.open('a+b') as stream:
        if stream.tell()==0:stream.write(b'0');stream.flush()
        stream.seek(0)
        try:msvcrt.locking(stream.fileno(),msvcrt.LK_NBLCK,1)
        except OSError:raise LocalError('local_launcher_already_running') from None
        try:yield
        finally:stream.seek(0);msvcrt.locking(stream.fileno(),msvcrt.LK_UNLCK,1)


def existing_game():
    query="@(Get-Process -Name dota2 -ErrorAction SilentlyContinue).Count"
    p=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',query],
        capture_output=True,text=True,timeout=15,creationflags=HIDDEN)
    need(p.returncode==0,'game_process_check_failed')
    return int(p.stdout.strip())>0


def game_command(direct_join=False):
    command=[str(ROOT.parents[1]/'bin/win64/dota2.exe'),'-steam','-tools','-noassetbrowser','-addon',ADDON,
        '-dev','-novid','-vconport',str(CONSOLE_PORT),'+sv_cheats','1','+host_timescale','1',
        '+r_drawpanorama','1']
    if direct_join:command+=['+sv_lan','0']
    return command+['+dota_launch_custom_game',ADDON,'template_map']


def run(expected_players,direct_join=False):
    need(not existing_game(),'close_dota_first')
    print('正在校验冻结测试资源……',flush=True)
    install()
    print('正在连接独立测试服务……',flush=True)
    key=provision();preflight(key)
    need(not existing_game(),'close_dota_first')
    private=STAGE/PRIVATE_REL
    private_files.no_reparse(private)
    if private.exists():
        need(private.stat().st_size<=1024 and private.read_text().startswith('"ws4_local_session"'),
             'unrecognized_stale_session_file')
        private.unlink()
    with proxy(key) as local_key:
        private_write(private,'"ws4_local_session"\n{\n "token" "'+local_key+'"\n "expected_players" "'+str(expected_players)+'"\n}\n')
        console=None
        try:
            proc=subprocess.Popen(game_command(direct_join),
                cwd=ROOT.parents[1]/'dota',stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            console=Console();applied=False;previous=None;deadline=time.monotonic()+600
            print('本机独立测试已启动。请保留此窗口；在游戏中等待载入，并按正常流程开始加载/选择模式。',flush=True)
            while proc.poll() is None:
                result=console.ask('probe' if applied else 'apply')
                state=result.get('state',{})
                if state.get('credential_applied') is True:
                    applied=True;private.unlink(missing_ok=True)
                value={'ok':True,'status':state.get('status',result.get('error','waiting')),
                    'game_pid':proc.pid,'credential_applied':applied,'expected_players':expected_players,
                    **{k:v for k,v in state.items() if k not in ('credential_applied','status')}}
                report(value)
                summary=json.dumps(value,sort_keys=True)
                if summary!=previous:
                    if state.get('phase')=='team_setup':
                        text='请切回 Dota，在原生队伍设置界面点击“开始游戏”，随后按界面选择模式和难度。'
                    elif state.get('error'):
                        text='档案准备暂未完成：'+state['error']+'。请查看游戏中的重试提示。'
                    elif state.get('profiles_ready'):
                        text='玩家档案已载入，可以继续游戏。'
                    elif state.get('authenticated',0)>=expected_players:
                        text='测试账号认证通过。请在游戏中按正常流程开始/选择模式。'
                    elif state.get('status')=='waiting_for_players':
                        text='等待玩家加入：'+str(state.get('players',0))+'/'+str(expected_players)
                    else:text='正在等待冻结测试地图载入和账号认证……'
                    print(text,flush=True);previous=summary
                if not applied and time.monotonic()>deadline:
                    raise LocalError('local_map_or_party_wait_timeout')
                time.sleep(3)
            return report({'ok':True,'status':'LOCAL_GAME_EXITED_CONNECTOR_STOPPED'})
        finally:
            private.unlink(missing_ok=True)
            if console:console.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('install','provision','preflight','run','status'))
    parser.add_argument('--refresh',action='store_true')
    parser.add_argument('--expected-players',type=int,choices=(1,2,3,4),default=1)
    parser.add_argument('--direct-join',action='store_true',help='Allow direct game connections; configure the restricted VPN firewall first')
    args=parser.parse_args()
    try:
        need(os.name=='nt','windows_only')
        if args.action=='status':value=json_file(OUTPUT/'status.json',8192)
        else:
            with instance_lock():
                if args.action=='install':value=install(args.refresh)
                elif args.action=='provision':
                    provision();value={'ok':True,'status':'LOCAL_CONNECTOR_PROVISIONED'}
                elif args.action=='preflight':value=preflight(provision())
                else:value=run(args.expected_players,args.direct_join)
        print(json.dumps(value,ensure_ascii=False),flush=True);return 0
    except KeyboardInterrupt:
        value=report({'ok':True,'status':'LOCAL_CONNECTOR_STOPPED_GAME_PRESERVED'})
        print(json.dumps(value),flush=True);return 0
    except Exception as error:
        code=str(error) if isinstance(error,LocalError) and re.fullmatch('[a-z_]{1,100}',str(error)) else 'local_launcher_failed'
        value={'ok':False,'error':code,'type':type(error).__name__,
            'frames':[{'function':f.name,'line':f.lineno} for f in traceback.extract_tb(error.__traceback__)[-4:]]}
        report(value)
        if code=='close_dota_first':print('请先退出 Dota 2，保留 Steam，再双击本机测试启动器。',flush=True)
        if code=='host_frozen_release_missing':
            print('这是创建房间的主机入口；本电脑缺少主机专用冻结测试包。仅拉取 Git 代码不会安装该资源。',flush=True)
            print('如果这台电脑用于加入另一台主机，请完整解压 ws4_remote_client 客户端 ZIP，应用最新启动修复包，再运行 join_game.cmd。',flush=True)
            print('也可将解压目录拖到项目根目录 join_ws4_game.cmd 上。主机凭据不需要复制给加入方。',flush=True)
        print(json.dumps(value),flush=True);return 1


if __name__=='__main__':raise SystemExit(main())
