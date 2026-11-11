"""Interactive root-SSH account maintenance; default action is preview only."""
from pathlib import Path
import argparse
import base64
import json
import re
import secrets
import subprocess
import sys

from engine import canonical, sha, need

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUTPUT = Path('D:/Survival_本地工具/runs/account_cleanup')
SOURCES = ('engine.py', 'remote.py', 'schema_contract.json', 'cli.py')


def operator_sources():
    files = {}
    inputs = {name: HERE / name for name in SOURCES}
    inputs['transport.py'] = ROOT / 'tools/archive_caps_20261020/remote_driver.py'
    inputs['ledger.py'] = ROOT / 'tools/release_storage_ledger.py'
    for name, path in inputs.items():
        blob = subprocess.run(['git','-C',str(ROOT),'show','HEAD:' + path.relative_to(ROOT).as_posix()],
                              capture_output=True, check=True).stdout.replace(b'\r\n', b'\n')
        need(path.read_bytes().replace(b'\r\n', b'\n') == blob, 'operator_files_must_match_committed_revision')
        files[name] = blob
    return files, sha(canonical({name: sha(raw) for name, raw in files.items()}))


def remote(payload, files):
    transport_path = ROOT / 'tools/archive_caps_20261020/remote_driver.py'
    import types
    transport = types.ModuleType('account_cleanup_known_host_transport')
    transport.__file__ = str(transport_path)
    exec(compile(files['transport.py'], str(transport_path), 'exec'), transport.__dict__)
    encoded = {name: base64.b64encode(raw).decode() for name, raw in files.items()}
    script = 'FILES=' + repr(encoded) + '\nPAYLOAD=' + repr(payload) + '''
import base64,json,sys,types
engine=types.ModuleType('account_cleanup_engine')
sys.modules['account_cleanup_engine']=engine
exec(compile(base64.b64decode(FILES['engine.py']),'account_cleanup_engine.py','exec'),engine.__dict__)
operator=types.ModuleType('account_cleanup_operator')
exec(compile(base64.b64decode(FILES['remote.py']),'account_cleanup_operator.py','exec'),operator.__dict__)
try:
 result=operator.execute(PAYLOAD,json.loads(base64.b64decode(FILES['schema_contract.json'])))
except Exception as error:
 import re
 reason=str(error) if isinstance(error,ValueError) and re.fullmatch('[a-z0-9_]{1,120}',str(error)) else 'account_cleanup_operator_failed'
 result={'ok':False,'error':reason,'automatic_retry':False}
print(json.dumps(result,ensure_ascii=True))
'''
    raw = transport.remote(script, timeout=600)
    need(len(raw.encode()) <= 2*1024*1024, 'remote_response_budget_exceeded')
    value = json.loads(raw.strip().splitlines()[-1])
    need(isinstance(value, dict) and type(value.get('ok')) is bool, 'invalid_remote_result')
    return value


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(canonical(value) + b'\n')


def save_maintenance_result(directory, name, value, files):
    path = directory / name
    save(path, {**value, 'artifact_root': str(directory.resolve())})
    # Register actual receipts only, including interrupted/unknown outcomes.
    # Execute the committed bytes already included in the operator binding.
    source = ('__file__=' + repr(str(ROOT / 'tools/release_storage_ledger.py'))
              + '\nexec(compile(' + repr(files['ledger.py']) + ',__file__,"exec"))\n').encode()
    try:
        result = subprocess.run([sys.executable,'-B','-X','utf8','-','record','--receipt',str(path)],
                                input=source,capture_output=True,timeout=60)
        record = {'returncode':result.returncode,'stdout':result.stdout.decode('utf8','replace')}
        save(directory / ('storage_registration_' + name), record)
        registered = result.returncode == 0
    except (OSError, subprocess.SubprocessError, KeyboardInterrupt):
        registered = False
    if not registered:
        print('维护回执已保留，但清理目录登记未完成：' + str(path), file=sys.stderr)


def show_preview(value):
    need(value.get('ok') is True, value.get('error', 'preview_failed'))
    plan = value['plan']
    print('目标 Steam AccountID：' + plan['account_id'] + '；SteamID64：' + plan['steam_id64'])
    print('数据库：' + plan['database'] + '（只处理此账号）')
    for name, detail in plan['state']['tables'].items():
        if detail['rows']:
            print('  ' + name + ': ' + str(detail['rows']) + ' 行')
    print('兑换码占用：' + str(sum(row[2] for row in plan['state']['code_counters'])) + ' 次；定义保留。')
    print('旧网页授权/会话：' + str(sum(plan['auth_rows'].values())) + ' 行')
    print('未结算订单：' + str(plan['state']['open_payment_orders']))
    print('实际清理前会备份完整 WS4 数据库和网页认证库，短暂停止 WS4 网页、支付、存档服务。')
    print('清理包含存档、属性、库存、权益、限额、兑换记录、支付记录、排行榜和旧登录会话。')
    print('保留管理员准入白名单、商品/兑换码定义及其他账号；不会进行退款。')
    print('目标账号须先退出当前对局，清理完成后重新开局和授权。')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=('preview','apply','status'))
    parser.add_argument('--account', help='Steam AccountID or SteamID64; never a player slot or nickname')
    parser.add_argument('--plan', type=Path)
    parser.add_argument('--sha256')
    parser.add_argument('--confirm', help='Exact DELETE <AccountID> STOP WS4 phrase')
    parser.add_argument('--request-id')
    args = parser.parse_args(argv)
    interactive = args.action is None
    files, digest = operator_sources()
    if args.action == 'status':
        need(bool(re.fullmatch('[a-f0-9]{32}', args.request_id or '')), 'request_identity_invalid')
        print(json.dumps(remote({'action':'status','request_id':args.request_id,'operator_sha256':digest}, files),
                         ensure_ascii=False, indent=2))
        return 0
    if args.action == 'apply':
        need(args.plan and re.fullmatch('[a-f0-9]{64}', args.sha256 or ''), 'explicit_plan_and_digest_required')
        raw = args.plan.read_bytes()
        need(len(raw) <= 2*1024*1024 and sha(raw) == args.sha256, 'local_plan_digest_mismatch')
        value = json.loads(raw)
        show_preview(value)
        need(sha(canonical(value['plan'])) == value['plan_sha256'], 'plan_content_digest_mismatch')
        need(value['plan']['operator_sha256'] == digest, 'operator_changed_preview_again')
        directory = args.plan.parent
        need(directory.resolve().is_relative_to(OUTPUT.resolve()), 'plan_must_be_in_external_cleanup_workspace')
    else:
        account = args.account if not interactive else input('请输入目标 Steam AccountID 或 SteamID64（仅预览）：').strip()
        need(bool(re.fullmatch('[0-9]{1,17}', account or '')), 'numeric_steam_identity_required')
        value = remote({'action':'preview','account':account,'operator_sha256':digest}, files)
        show_preview(value)
        directory = OUTPUT / ('run_' + secrets.token_hex(12))
        path = directory / 'preview.json'
        save(path, value)
        print('预览已保存：' + str(path))
        print('文件 SHA256：' + sha(path.read_bytes()))
        if not interactive:
            return 0
    plan = value['plan']
    need(plan['state']['open_payment_orders'] == 0, 'pending_payment_orders_must_be_resolved')
    phrase = 'DELETE ' + plan['account_id'] + ' STOP WS4'
    confirmation = input('实际清理请输入 ' + phrase + '；其他输入退出且不删除：').strip() if interactive else args.confirm
    if interactive and confirmation != phrase:
        print('已结束预览，未删除账号数据。')
        return 0
    need(confirmation == phrase, 'exact_account_and_maintenance_confirmation_required')
    request_id = secrets.token_hex(16)
    save(directory / ('intent_' + request_id + '.json'), {'account_id':plan['account_id'],
        'request_id':request_id,'plan_sha256':value['plan_sha256'],'automatic_retry':False})
    print('维护请求号：' + request_id, flush=True)
    try:
        result = remote({'action':'apply','account':plan['account_id'],'operator_sha256':digest,
            'expected':plan,'confirm':'DELETE ' + plan['account_id'],'request_id':request_id}, files)
    except (Exception, KeyboardInterrupt):
        save_maintenance_result(directory, 'unknown_' + request_id + '.json', {'status':'REMOTE_RESULT_UNKNOWN',
            'request_id':request_id,'automatic_retry':False}, files)
        print('远端结果未知，不会自动重试。请用 status --request-id ' + request_id + ' 核对维护回执。')
        return 2
    save_maintenance_result(directory, 'result_' + request_id + '.json', result, files)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['ok'] else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        reason = str(error) if isinstance(error, ValueError) and re.fullmatch('[a-z0-9_]{1,120}', str(error)) else 'account_cleanup_not_completed'
        print('未完成：' + reason + '；未自动重试。', file=sys.stderr)
        raise SystemExit(2)
