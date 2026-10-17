"""Prepare one scope-locked, offline-only archive candidate; never activate it."""
from __future__ import annotations
import argparse, ast, copy, difflib, gzip, hashlib, importlib.util, io, json, os, shutil, subprocess, sys, tarfile, tempfile
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/commerce_logic_audit_20261016/release'
BASE='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
SOURCE='systems/commerce_settlement.lua'
LOCAL_BASELINE=ROOT/'design_refs/commerce_logic_audit_20261016/baseline/server/archive_backend/service.py'
SERVICE=ROOT/'server/archive_backend/service.py'
POINTER=ROOT/'server/bundles/current.json'
GAME=ROOT/'scripts/vscripts/config/generated/archive_http_bundle.lua'
ANCHOR="        database_id=self.app._database_account_id(account)\n        self.app._ensure_gameplay_stats(database_id)\n"
INSERT="""        if command['kind'] == 'starjoy_reconcile':
            # Cash grants can cross several tiers during one match. Derive a
            # stable receipt from saved progress, never a client-supplied score.
            # profile() also resolves earlier pending operations before reading.
            trusted = self.profile({'account_id': account})
            stats = trusted.get('save', {}).get('gameplay_stats', {})
            score = max(0, *(int(stats.get(key) or 0) for key in
                            ('starjoy_points_earned', 'starjoy_points')))
            command['id'] += ':earned:' + str(score)
"""
FOLLOW='        fingerprint=hashlib.sha256(json.dumps(command,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()\n'
OLD=ANCHOR+FOLLOW
NEW=ANCHOR+INSERT+FOLLOW
PATCH_TOOL = r'''"""Context-guarded offline patch/reverse; writes a separate reviewed output only."""
from pathlib import Path
import argparse,hashlib,json
def transform(raw,spec,reverse=False):
    if b'\r' in raw.replace(b'\r\n',b''):
        raise ValueError('unsupported_line_endings')
    newline=b'\r\n' if b'\r\n' in raw else b'\n'
    if newline==b'\r\n' and b'\n' in raw.replace(b'\r\n',b''):
        raise ValueError('mixed_line_endings')
    old=spec['new_exact'] if reverse else spec['old_exact']
    new=spec['old_exact'] if reverse else spec['new_exact']
    original=old.encode().replace(b'\n',newline)
    replacement=new.encode().replace(b'\n',newline)
    if raw.count(original)!=1:
        raise ValueError('patch_context_not_exactly_once')
    result=raw.replace(original,replacement,1)
    if result==raw:
        raise ValueError('patch_changed_nothing')
    return result
if __name__=='__main__':
    ap=argparse.ArgumentParser(description='No network, no in-place writes. Inspect online source separately before using.')
    ap.add_argument('--source',required=True,type=Path)
    ap.add_argument('--output',type=Path)
    ap.add_argument('--reverse',action='store_true')
    a=ap.parse_args()
    spec=json.loads(Path(__file__).with_name('starjoy_progress_patch.json').read_text('utf-8'))
    raw=a.source.read_bytes();result=transform(raw,spec,a.reverse)
    if a.output:
        if a.output.resolve()==a.source.resolve():
            raise ValueError('in_place_write_refused')
        if a.output.exists():
            raise ValueError('output_already_exists')
        a.output.write_bytes(result)
    print(json.dumps({'status':'PASS','direction':'reverse' if a.reverse else 'forward',
        'source_sha256':hashlib.sha256(raw).hexdigest(),'output_sha256':hashlib.sha256(result).hexdigest(),
        'written':str(a.output) if a.output else None,'deployment_performed':False}))
'''

def sha(raw): return hashlib.sha256(raw).hexdigest()
def canonical(value): return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def put(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(raw)
def write_json(path,data): put(path,canonical(data)+b'\n')
def norm(raw): return raw.decode('utf-8-sig').replace('\r\n','\n')
def load_patch_module(path):
    spec=importlib.util.spec_from_file_location('commerce_starjoy_guarded_patch',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def smoke(candidate,old,folder,lua):
    sys.path[:0]=[str(ROOT/'server'),str(ROOT)]
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from archive_backend.config_compatibility import accepts,upgrades
    from tests.test_archive_backend import Database,App
    new_bundle=Bundle(candidate)
    old_bundle=Bundle(old)
    catalog={r['sku']:r for r in new_bundle.configs['commerce_catalog']['rows']}
    assert len(catalog)==123
    assert new_bundle.configs['commerce_catalog']==old_bundle.configs['commerce_catalog']
    for kind in new_bundle.compatible_config_hashes[BASE]['commands']:
        assert accepts(new_bundle,BASE,kind)
        assert not upgrades(new_bundle,BASE,kind)
    db=Database(new_bundle);app=App(db);service=ArchiveService(app,new_bundle,lua)
    def profile(account='100'):
        p=db.profile(app._database_account_id(account))
        p['save']['content_inventory']={}
        p['save']['archive']['commerce']={'balances':{'u_coin':1000000000,'shop_points':1000000000,'shop_gold':1000000000}}
        p['save']['gameplay_stats'].update(starjoy_points=0,starjoy_points_earned=1000,starjoy_reward_level=5)
        return p
    def payload(kind='commerce_purchase',digest=None,account='100',token='patch-audit-purchase',**kw):
        c={'id':'same-audit-match:'+kind,'kind':kind,**kw}
        if kind=='commerce_purchase':c.update(sku=kw.get('sku','video_p004'),request_id=token)
        return {'account_id':account,'config_hash':digest or new_bundle.hash,'command':c}
    def send(*args,**kw):return service.command(payload(*args,**kw))
    calls=[];real_run=subprocess.run
    def run(*args,**kwargs):
        calls.append(str(Path(kwargs['cwd']).name))
        return real_run(*args,**kwargs)
    checks=[]
    with patch('archive_backend.service.subprocess.run',side_effect=run):
        p=profile()
        full=service.settle(p,{'id':'catalog-before','kind':'commerce_catalog'},False)
        old_full=ArchiveService(app,old_bundle,lua).settle(p,{'id':'catalog-before','kind':'commerce_catalog'},False)
        assert full==old_full and len(full['products'])==121
        checks.append({'name':'catalog_123_definitions_121_enabled_and_prices_unchanged','status':'PASS','catalog_count':123,'enabled_count':121,
                       'catalog_sha256':sha(canonical(new_bundle.configs['commerce_catalog']))})
        before=copy.deepcopy(p);r=send()
        assert r['ok'],r
        s=p['save']['gameplay_stats']
        assert s['starjoy_points']==68 and s['starjoy_points_earned']==1068
        assert p['save']['archive']['commerce']['balances']['u_coin']==before['save']['archive']['commerce']['balances']['u_coin']-catalog['video_p004']['price']
        assert calls[-1]==new_bundle.hash
        after=copy.deepcopy(p);count=len(calls);assert send()['ok'];assert p==after and len(calls)==count
        checks.append({'name':'new_hash_spent_balance_purchase_and_done_receipt','status':'PASS','earned':1068,'price':catalog['video_p004']['price'],'retry_worker_calls':0})
        p=profile('101');s=p['save']['gameplay_stats'];s.update(starjoy_points_earned=1450,starjoy_reward_level=5)
        r=send(account='101',token='patch-new-cross-tier');assert r['ok'],r
        s=p['save']['gameplay_stats'];assert s['starjoy_points_earned']==1518 and s['starjoy_reward_level']==6 and s['tower_critical_chance_pct']==3
        r=send(account='101',token='patch-second-product',sku='video_p011');assert r['ok'],r
        s=p['save']['gameplay_stats'];assert s['starjoy_points_earned']==1586 and s['starjoy_reward_level']==6 and s['tower_critical_chance_pct']==3
        checks.append({'name':'new_hash_tier_crossing_then_second_purchase_no_duplicate_tier','status':'PASS','earned':1586,'tier':6})
        p=profile('102');before=copy.deepcopy(p)
        r=send(digest=BASE,account='102',token='patch-old-hash-purchase');assert r['ok'],r
        s=p['save']['gameplay_stats'];assert s['starjoy_points']==68 and s['starjoy_points_earned']==1000
        assert calls[-1]==BASE
        checks.append({'name':'dee_old_client_purchase_keeps_original_reducer','status':'PASS','earned_retains_old_rule':1000,'reducer':BASE})
        p=profile('103')
        old_service=ArchiveService(app,old_bundle,lua)
        old_request=payload(digest=BASE,account='103',token='patch-previously-done')
        db.lose_reply=True
        try:old_service.command(old_request);raise AssertionError('expected_lost_reply')
        except TimeoutError:pass
        after=copy.deepcopy(p);count=len(calls)
        assert service.command(old_request)['ok'] and p==after and len(calls)==count
        op=db.ops[(app._database_account_id('103'),'commerce:patch-previously-done')]
        assert op['hash']==BASE and op['done']
        checks.append({'name':'previously_done_dee_receipt_never_replayed_after_candidate','status':'PASS','retry_worker_calls':0,'receipt_hash':op['hash']})
        p=profile('104');s=p['save']['gameplay_stats'];s.update(starjoy_points_earned=1450,starjoy_reward_level=5)
        assert send('starjoy_reconcile',account='104')['ok']
        s=p['save']['gameplay_stats'];s['starjoy_points']+=68;s['starjoy_points_earned']+=68;p['revision']+=1
        assert send('starjoy_reconcile',account='104')['ok']
        s=p['save']['gameplay_stats'];assert s['starjoy_reward_level']==6 and s['tower_critical_chance_pct']==3
        old_state=copy.deepcopy(s);assert send('starjoy_reconcile',account='104')['ok'];assert s==old_state
        s['starjoy_points']+=600;s['starjoy_points_earned']+=600;p['revision']+=1
        assert send('starjoy_reconcile',account='104')['ok']
        s=p['save']['gameplay_stats'];assert s['starjoy_reward_level']==7
        checks.append({'name':'local_service_guarded_progress_key_two_same_match_crossings','status':'PASS','final_tier':7,
                       'scope':'actual local service.py plus actual worker subprocess; online Python file not yet inspected'})
    return {'status':'PASS','checks':checks,'worker':'actual Lua 5.1 executable subprocess, packaged worker.lua unchanged',
            'lua_executable':str(lua),'real_worker_calls':len(calls),'external_requests':0,'real_account_data':False,
            'scope':'temporary local Database/App receipt fixture; not live PostgreSQL, network, server or game'}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--lua',default='C:/Program Files/lua/bin/lua5.1.exe')
    args=ap.parse_args()
    lua=Path(args.lua)
    assert lua.is_file(),'lua51_executable_missing'
    active_before={str(p.relative_to(ROOT)):p.read_bytes() for p in (POINTER,GAME)}
    assert json.loads(active_before[str(POINTER.relative_to(ROOT))])['hash']==BASE,'active_baseline_pointer_changed'
    assert BASE in norm(active_before[str(GAME.relative_to(ROOT))]),'game_baseline_pointer_changed'
    commerce_raw=(ROOT/'scripts/vscripts'/SOURCE).read_bytes()
    basefile=ROOT/'server/bundles'/BASE/'bundle.json'
    raw=basefile.read_bytes();assert sha(raw)==BASE,'baseline_digest_mismatch'
    base=json.loads(raw);data=copy.deepcopy(base)
    replacement=norm(commerce_raw)
    assert replacement!=base['sources'][SOURCE],'commerce_source_has_no_patch'
    data['sources'][SOURCE]=replacement
    aliases=data.setdefault('compatible_config_hashes',{})
    commands=sorted(set().union(*(set(rule['commands']) for rule in aliases.values())))
    assert len(commands)==22 and BASE not in aliases
    aliases[BASE]={'commands':commands,'upgrade_commands':[]}
    assert data['configs']==base['configs']
    assert data['csv_hashes']==base['csv_hashes']
    assert set(data['sources'])==set(base['sources'])
    changed=[k for k in base['sources'] if base['sources'][k]!=data['sources'][k]]
    assert changed==[SOURCE],changed
    for digest,rule in base['compatible_config_hashes'].items():assert aliases[digest]==rule
    assert data['sources']['worker.lua']==base['sources']['worker.lua']
    body=canonical(data);digest=sha(body);dest=OUT/('archive-starjoy-'+digest[:12])
    candidate=dest/'candidate/addon/server/bundles'/digest
    for name,text in data['sources'].items():put(candidate/name,text.encode('utf-8'))
    put(candidate/'bundle.json',body)
    prospective={'hash':digest,'protocol':1}
    write_json(dest/'candidate/addon/server/bundles/current.json',prospective)
    put(dest/'candidate/addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        ('-- Prepared candidate only; not activated. Reopen the map after a reviewed deployment.\nreturn { protocol = 1, hash = "'+digest+'" }\n').encode())
    put(dest/'rollback/bundle.json',raw)
    put(dest/'rollback/server_current.json',active_before[str(POINTER.relative_to(ROOT))])
    put(dest/'rollback/archive_http_bundle.lua',active_before[str(GAME.relative_to(ROOT))])
    put(dest/'rollback/commerce_settlement.lua',base['sources'][SOURCE].encode('utf-8'))
    local_baseline=LOCAL_BASELINE.read_bytes();local_current=SERVICE.read_bytes()
    assert OLD in norm(local_baseline) and norm(local_baseline).count(OLD)==1
    assert norm(local_baseline).replace(OLD,NEW,1)==norm(local_current),'unexpected_service_changes'
    ast.parse(norm(local_current))
    spec={'version':1,'purpose':'nine-line server-owned starjoy earned-score receipt key; exact context only',
          'old_exact':OLD,'new_exact':NEW,'old_context_sha256':sha(OLD.encode()),'new_context_sha256':sha(NEW.encode()),
          'local_baseline_source':str(LOCAL_BASELINE.relative_to(ROOT)),'local_baseline_sha256':sha(local_baseline),
          'local_current_sha256':sha(local_current),'online_source_verified':False,
          'deployment_requirement':'Read the actual online source and review its diff before applying this separate-output guarded patch. Never replace it with the unverified local whole service.py.'}
    write_json(dest/'candidate/guarded_patches/starjoy_progress_patch.json',spec)
    patch_path=dest/'candidate/guarded_patches/apply_starjoy_progress.py'
    put(patch_path,PATCH_TOOL.encode())
    ast.parse(PATCH_TOOL)
    mod=load_patch_module(patch_path)
    applied=mod.transform(local_baseline,spec)
    assert norm(applied)==norm(local_current)
    assert mod.transform(applied,spec,True)==local_baseline
    for invalid in (local_baseline.replace(b'_ensure_gameplay_stats(database_id)',b'_changed_profile_schema(database_id)'),applied):
        try:mod.transform(invalid,spec)
        except ValueError:pass
        else:raise AssertionError('guard_accepted_unexpected_source')
    # Ensure importing the test-only patch did not add unmanifested bytecode.
    for extra in patch_path.parent.glob('__pycache__/apply_starjoy_progress.*.pyc'):extra.unlink()
    cache=patch_path.parent/'__pycache__'
    if cache.is_dir() and not any(cache.iterdir()):cache.rmdir()
    diff={
        'base_hash':BASE,'candidate_hash':digest,'changed_top_level_keys':['compatible_config_hashes','sources'],
        'changed_sources':changed,'configs_identical':True,'csv_hashes_identical':True,'worker_identical':True,
        'other_sources_identical':True,'existing_compatibility_rules_identical':True,'added_compatibility':{BASE:aliases[BASE]},
        'catalog_definitions':len(data['configs']['commerce_catalog']['rows']),
        'enabled_catalog_definitions':sum(row['enabled'] for row in data['configs']['commerce_catalog']['rows']),
        'commerce_source_unified_diff':''.join(difflib.unified_diff(base['sources'][SOURCE].splitlines(True),replacement.splitlines(True),fromfile=BASE+'/'+SOURCE,tofile=digest+'/'+SOURCE)),
        'service_guarded_patch_matches_local_baseline':True,'service_reverse_restores_local_baseline_bytes':True,
        'service_unexpected_context_and_already_applied_refused':True,'online_python_baseline_verified':False,
        'active_pointers_modified':False}
    write_json(dest/'exact_diff.json',diff)
    with tempfile.TemporaryDirectory(prefix='archive-starjoy-review-') as temp:
        folder=Path(temp);old=folder/BASE;new=folder/digest
        shutil.copytree(ROOT/'server/bundles'/BASE,old)
        shutil.copytree(candidate,new)
        result=smoke(new,old,folder,lua)
    write_json(dest/'smoke.json',result)
    plan={'status':'PREPARED_NOT_DEPLOYED','base_hash':BASE,'candidate_hash':digest,
          'activation_requires_review':True,'new_map_requires_candidate_game_pointer':True,
          'old_dee_clients':'all existing declared commands accepted; purchases keep recorded dee reducer and its historical limitations',
          'done_receipts':'database done receipt returned without worker execution or reward replay',
          'python_delivery':'guarded nine-line patch only, no unverified whole service.py; read online source before deployment',
          'payment_or_sql_files_included':False,'catalog_or_currency_rules_changed':False,
          'source_inputs':{SOURCE:sha(commerce_raw),'local_service.py':sha(local_current),
                           'local_baseline_service.py':sha(local_baseline),'base_bundle.json':sha(raw)},
          'active_pointers_before':{k:sha(v) for k,v in active_before.items()},
          'external_requests':0,'production_deployed':False}
    write_json(dest/'release_plan.json',plan)
    text="""# 星悦商城修复：可审查发布候选（未部署）

本候选从已发布 dee53fe2... 的不可变 bundle 克隆。只替换 commerce_settlement.lua，保留原配置、CSV 哈希、123 条商品定义、币价、worker 和所有其他 Lua source。兼容规则仅新增 dee 别名，既有历史兼容与 upgrade_commands 原样保留。

候选目录中的 current.json 与游戏 archive_http_bundle.lua 是待审查文件；当前工程和正在使用的指针没有修改。部署并更新游戏指针、重新开图后，新客户端以新 hash 购买才能使用修正的星悦累计与等级奖励。dee 旧客户端继续按原规则处理购买；历史已完成回执不会重放。候选没有修改金融 upgrade allowlist。

Python 只附带 9 行、上下文必须精确匹配的 guarded patch。没有打包或声称已核对线上整份 service.py。部署前须读取线上实际源码，审核其现状；先执行补丁校验并输出独立文件，再审阅前后差异。异常上下文、已应用、同路径覆盖和已存在输出均拒绝。反向 --reverse 可恢复该补丁，线上整文件备份仍必须在正式部署阶段完成。

离线校验示例（只检查，不写文件）：
py -3 candidate/guarded_patches/apply_starjoy_progress.py --source <已读取并审阅的service.py>
显式 --output <新文件> 才会写出文件。此工具没有网络、服务重启或激活逻辑。

smoke.json 使用真实 Lua 5.1 子进程执行候选/旧版原 worker；数据库仅使用本地回执替身。覆盖新 hash 的已花积分累计、跨级与重复领取、新旧 hash 路由、历史 done 回执无重放，以及本机 Python progress-key 在同局两次越级。它不等于线上 PostgreSQL 或实机验收。

回滚资料保存在 rollback/：已发布 bundle.json、原服务/游戏指针和原 commerce Lua。Python 回滚仅使用 guarded patch 的反向变换，部署时还应保留线上实际整文件备份。未部署、未连接外网、没有真实账号数据。manifest.json 锁定每个文件 SHA256；tar.gz 是相同审查资料的归档。
"""
    put(dest/'README.md',text.encode())
    for path,previous in active_before.items():assert (ROOT/path).read_bytes()==previous,'active_pointer_was_changed'
    assert (ROOT/'scripts/vscripts'/SOURCE).read_bytes()==commerce_raw,'commerce_source_changed_during_prepare'
    assert SERVICE.read_bytes()==local_current and LOCAL_BASELINE.read_bytes()==local_baseline,'python_source_changed_during_prepare'
    assert basefile.read_bytes()==raw,'immutable_baseline_changed_during_prepare'
    files={p.relative_to(dest).as_posix():sha(p.read_bytes()) for p in dest.rglob('*') if p.is_file() and p.name not in {'manifest.json','archive_patch.tar.gz','archive_patch.tar.gz.sha256'}}
    # A candidate must not silently retain files from another task or an earlier scope.
    expected={f'candidate/addon/server/bundles/{digest}/'+name for name in list(data['sources'])+['bundle.json']}
    expected.update({'candidate/addon/server/bundles/current.json','candidate/addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        'candidate/guarded_patches/starjoy_progress_patch.json','candidate/guarded_patches/apply_starjoy_progress.py',
        'rollback/bundle.json','rollback/server_current.json','rollback/archive_http_bundle.lua','rollback/commerce_settlement.lua',
        'README.md','release_plan.json','exact_diff.json','smoke.json'})
    assert set(files)==expected,{'unexpected':sorted(set(files)-expected),'missing':sorted(expected-set(files))}
    assert not any(k.endswith('service.py') or k.endswith('config_compatibility.py') for k in files)
    assert not any('payment_backend' in k or k.endswith('.sql') or '__pycache__' in k for k in files)
    write_json(dest/'manifest.json',{'format':1,'status':'PREPARED_NOT_DEPLOYED','base':BASE,'candidate':digest,'files':files})
    for name,expected in files.items():assert sha((dest/name).read_bytes())==expected
    archive=dest/'archive_patch.tar.gz'
    with archive.open('wb') as target:
        with gzip.GzipFile(filename='',mode='wb',fileobj=target,mtime=0) as zipped:
            with tarfile.open(fileobj=zipped,mode='w') as tar:
                for name in sorted(list(files)+['manifest.json']):
                    raw_file=(dest/name).read_bytes();info=tarfile.TarInfo(name);info.size=len(raw_file);info.mtime=0;info.mode=0o644
                    tar.addfile(info,io.BytesIO(raw_file))
    with tarfile.open(archive,'r:gz') as tar:
        assert set(tar.getnames())==set(files)|{'manifest.json'}
        for entry in tar.getmembers():
            assert entry.isfile() and not entry.name.startswith('/') and '..' not in Path(entry.name).parts
            assert tar.extractfile(entry).read()==(dest/entry.name).read_bytes()
    put(dest/'archive_patch.tar.gz.sha256',(sha(archive.read_bytes())+'  archive_patch.tar.gz\n').encode())
    write_json(OUT/'LATEST_PREPARED.json',{'status':'PREPARED_NOT_DEPLOYED','directory':dest.relative_to(ROOT).as_posix(),'candidate':digest,
               'archive_sha256':sha(archive.read_bytes()),'production_deployed':False})
    print(json.dumps({'status':'PREPARED_NOT_DEPLOYED','candidate':digest,'directory':str(dest.relative_to(ROOT)),'smoke_checks':len(result['checks']),
                     'archive_sha256':sha(archive.read_bytes()),'active_pointers_unchanged':True},ensure_ascii=False))
if __name__=='__main__':main()
