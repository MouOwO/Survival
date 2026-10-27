"""Resume only the unchanged PWA switch after an indented systemd unit guard."""
import hashlib
import json
from pathlib import Path
import re

ORIGINAL = '9cc5a4e583f1ce0de1b1832bca6b804a5ad29a172d21e679070643b59e713700'


def need(value,code):
    if not value:raise RuntimeError(code)


def repaired_unit(raw,release):
    """Systemd accepts leading whitespace; preserve every unrelated byte."""
    need(str(release)=='/opt/goufayu-ws4-web/releases/20261027-payment-'+ORIGINAL[:20],'repair_fixed_pwa_release_required')
    text=raw.decode();lines=text.splitlines(keepends=True);seen={}
    allowed={'User':'goufayu-ws4-web','Group':'goufayu-ws4-web',
             'EnvironmentFile':'/etc/goufayu-ws4-web/auth.env',
             'ExecStart':'/usr/bin/python3.11 -B -m player_web_auth.run'}
    section=None
    for index,line in enumerate(lines):
        stripped=line.strip()
        if stripped.startswith('['):section=stripped;continue
        key,separator,value=stripped.partition('=');key=key.strip();value=value.strip()
        if key not in set(allowed)|{'WorkingDirectory'} or not separator:continue
        need(section=='[Service]' and key not in seen,'repair_unit_duplicate_or_wrong_section')
        seen[key]=value
        if key=='ExecStart':need(value in (allowed[key],'/usr/bin/python3.11 -m player_web_auth.run'),'repair_unit_executable_unexpected')
        elif key in allowed:need(value==allowed[key],'repair_unit_identity_unexpected')
        else:
            need(value.startswith('/opt/goufayu-ws4-web/releases/') and '..' not in Path(value).parts,'repair_unit_old_release_invalid')
            match=re.fullmatch(r'(\s*WorkingDirectory\s*=\s*)([^\r\n]*)(\r?\n)?',line)
            need(match is not None,'repair_unit_assignment_invalid')
            lines[index]=match[1]+str(release)+(match[3] or '')
    need(set(seen)==set(allowed)|{'WorkingDirectory'},'repair_unit_required_directive_missing')
    return ''.join(lines).encode()


def inspect(op,capsule):
    need(capsule['activation_sha256']==ORIGINAL,'repair_original_capsule_required')
    stage=op.checked_stage(capsule)
    old=op.regular(op.PWA_UNIT);backup=op.regular(stage/'private-backup/web.unit')
    env=op.regular(op.PWA_ENV);env_backup=op.regular(stage/'private-backup/web.env')
    release=op.PWA_BASE/'releases'/('20261027-payment-'+ORIGINAL[:20])
    unit=repaired_unit(old,release)
    need(old==backup and env==env_backup,'repair_original_pwa_was_changed')
    need(not (stage/'activated.json').exists() and not (stage/'pwa.unit.after').exists(),'repair_phase_already_advanced')
    need((stage/'activation-started.json').is_file() and (stage/'pwa.env.after').is_file(),'repair_partial_activation_required')
    need(op.regular(op.NGINX)==op.regular(stage/'nginx.after') and op.regular(op.PAYMENT_LOCATIONS)==op.nginx_rules(),'repair_new_routes_changed')
    config=json.loads(op.regular(op.PAYMENT_CONFIG/'config.json'))
    need(op.regular(stage/'pwa.env.after')==op.payment_env(env_backup,config['game_token'],False),'repair_payment_environment_changed')
    need(release.is_dir() and not release.is_symlink(),'repair_existing_release_required')
    hashes={}
    for name,digest in capsule['candidate']['source_hashes'].items():
        if name.startswith(('player_web_auth/','lobby_backend/')):
            actual=hashlib.sha256(op.regular(release/name)).hexdigest()
            need(actual==digest,'repair_existing_pwa_source_changed');hashes[name]=actual
    baseline=op.baseline();op.legacy_unchanged(capsule['audit']['baseline'])
    payment=op.command(['systemctl','show','goufayu-ws4-payment.service','--property=ActiveState,MainPID']).decode().splitlines()
    need('ActiveState=active' in payment,'repair_payment_service_not_active')
    safe=[line.strip() for line in old.decode().splitlines() if line.strip().partition('=')[0] in
          ('User','Group','WorkingDirectory','EnvironmentFile','ExecStart')]
    return {'ok':True,'kind':'WS4_PWA_INDENTED_UNIT_READONLY_INSPECTION','original_capsule':ORIGINAL,
            'stage':str(stage),'release':str(release),'unit_sha256':hashlib.sha256(old).hexdigest(),
            'env_sha256':hashlib.sha256(env).hexdigest(),'unit_after_sha256':hashlib.sha256(unit).hexdigest(),
            'payment_env_after_sha256':hashlib.sha256(op.regular(stage/'pwa.env.after')).hexdigest(),
            'pwa_directives':safe,'pwa_sources':hashes,'old_services':baseline,'new_payment_service':payment,
            'pwa_untouched':True,'remote_writes':0,'secrets_exported':False}


def apply(op,capsule,plan):
    import pwd
    value=dict(plan);identity=value.pop('repair_sha256')
    need(hashlib.sha256(op.canonical(value)).hexdigest()==identity,'repair_plan_hash_mismatch')
    observed=inspect(op,capsule)
    need(observed==plan['inspection'],'repair_preconditions_changed')
    stage=Path(observed['stage']);release=Path(observed['release'])
    need(not (stage/'pwa-repair-started.json').exists(),'repair_already_attempted')
    counts=op.database_counts()
    need(not any(counts[name] for name in ('orders','vip_recharge_credits','test_resets','test_accounts','cleared_reward_grants')),'repair_unexpected_payment_ledger')
    op.validate_privileges(op.privilege_state(),active=True)
    config=json.loads(op.regular(op.PAYMENT_CONFIG/'config.json'))
    op.assert_seed_rows(stage,config)
    unit=repaired_unit(op.regular(op.PWA_UNIT),release)
    user=pwd.getpwnam('goufayu-ws4-web')
    need(user.pw_uid>0 and user.pw_gid>0,'repair_pwa_user_invalid')
    # Only the PWA unit/env change. Existing release, SQL, keys, payment unit,
    # callback routes, role, and payment worker remain as already installed.
    op.private_file(stage/'pwa-repair-started.json',op.canonical({'repair_sha256':plan['repair_sha256'],'original_capsule':ORIGINAL}))
    op.private_file(stage/'pwa.unit.after',unit)
    op.private_file(op.PWA_ENV,op.regular(stage/'pwa.env.after'),user.pw_gid,0o640,replace=True)
    op.private_file(op.PWA_UNIT,unit,0,0o644,replace=True)
    op.command(['systemctl','daemon-reload']);op.command(['systemctl','restart','goufayu-ws4-web.service'])
    op.wait_health('http://127.0.0.1:18767/health')
    current_payment=op.command(['systemctl','show','goufayu-ws4-payment.service','--property=ActiveState,MainPID']).decode().splitlines()
    need(current_payment==observed['new_payment_service'],'repair_payment_service_changed')
    op.legacy_unchanged(capsule['audit']['baseline'])
    op.private_file(stage/'activated.json',op.canonical({'activation_sha256':ORIGINAL,
        'payment_release':capsule['candidate']['payment']['release'],'pwa_release':str(release),
        'payments_enabled':False,'seeded_tables_only':True,'config_sha256':hashlib.sha256(op.regular(op.PAYMENT_CONFIG/'config.json')).hexdigest(),
        'completed_by_reviewed_repair':plan['repair_sha256']}))
    result=op.verify_capsule(capsule)
    result['repair_sha256']=plan['repair_sha256'];result['payment_service_preserved']=True
    return result
