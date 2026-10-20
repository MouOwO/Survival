"""Offline release-scope checks. Does not deploy, connect, or touch current pointers."""
from pathlib import Path
import ast
import importlib.util
import json
import sys

sys.dont_write_bytecode = True

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/points_goods_unique_20261018/release'
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import Bundle


def tree(source):return ast.parse(source)


def main():
    plan=json.loads((OUT/'plan.json').read_bytes())
    original=json.loads((OUT/'baseline/addon/server/bundles'/plan['parent_bundle']/'bundle.json').read_bytes())
    directory=OUT/'candidate/addon/server/bundles'/plan['bundle']
    bundle=Bundle(directory)
    candidate=json.loads((directory/'bundle.json').read_bytes())
    prefix='addon/server/bundles/'+plan['bundle']+'/'
    approved_files={
        'backend/archive_backend/service.py','backend/archive_backend/unique_points.py',
        'addon/server/bundles/current.json','addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        'addon/data/csv/商城兑换系统/commerce_products.csv','addon/data/csv/抽奖系统/lottery_item_definitions.csv',
        prefix+'bundle.json',*(prefix+name for name in original['sources']),
    }
    actual_files={path.relative_to(OUT/'candidate').as_posix() for path in (OUT/'candidate').rglob('*') if path.is_file()}
    assert set(plan['archive_files'])==approved_files and actual_files==approved_files,'candidate_file_whitelist_mismatch'
    assert not any(path.is_symlink() for path in (OUT/'candidate').rglob('*')),'candidate_symlink_refused'
    changed_sources={key for key in original['sources'] if original['sources'][key]!=candidate['sources'][key]}
    assert changed_sources=={'systems/commerce_settlement.lua','systems/lottery_http_settlement.lua'}
    changed_configs={key for key in original['configs'] if original['configs'][key]!=candidate['configs'][key]}
    assert changed_configs=={'commerce_products','commerce_catalog','lottery_item_definitions'}
    for name in ('lottery_pool_definitions','lottery_pool_items','lottery_pity_rules','player_gameplay_stats'):
        assert candidate['configs'][name]==original['configs'][name]
    before={row['sku']:row for row in original['configs']['commerce_catalog']['rows']}
    after={row['sku']:row for row in candidate['configs']['commerce_catalog']['rows']}
    assert before.keys()==after.keys()
    for sku in before:
        for field in ('price','currency','effects','grants','ownership_quantity'):
            assert before[sku][field]==after[sku][field],sku+':'+field
        if sku not in {'video_p089','video_p103'}:assert before[sku]==after[sku]
    assert after['video_p089']['enabled'] is False and after['video_p089']['ownership_quantity']==100
    assert after['video_p103']['purchase_limit']==1 and after['video_p103']['price']==29
    compatibility=candidate['compatible_config_hashes']
    assert all(compatibility[key]==value for key,value in original.get('compatible_config_hashes',{}).items())
    assert compatibility[plan['parent_bundle']]['upgrade_commands']==[]
    a=tree((OUT/'baseline/backend/archive_backend/service.py').read_text('utf-8-sig'))
    b=tree((OUT/'candidate/backend/archive_backend/service.py').read_text('utf-8-sig'))
    a_class=next(node for node in a.body if isinstance(node,ast.ClassDef) and node.name=='ArchiveService')
    b_class=next(node for node in b.body if isinstance(node,ast.ClassDef) and node.name=='ArchiveService')
    am={node.name:node for node in a_class.body if isinstance(node,ast.FunctionDef)}
    bm={node.name:node for node in b_class.body if isinstance(node,ast.FunctionDef)}
    assert bm.keys()-am.keys()=={'commerce_unique_block'}
    assert am.keys()<=bm.keys()
    changed_methods={name for name in am if ast.dump(am[name])!=ast.dump(bm[name])}
    assert changed_methods=={'finish_prepared','lottery_snapshot'}
    # FIELDS, validation, command admission, challenge seeds and install stay exact.
    assert [ast.dump(node) for node in a.body if node is not a_class]==[ast.dump(node) for node in b.body if node is not b_class]
    unique_path=OUT/'candidate/backend/archive_backend/unique_points.py'
    spec=importlib.util.spec_from_file_location('points_release_unique_helper',unique_path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    items,aliases=module.catalog(bundle)
    assert len(items)==97 and set(items.values())=={5,25,100,400,1000}
    assert module.legacy_lottery_error(bundle.hash,plan['parent_bundle'],'lottery_draw')=='lottery_config_refresh_required'
    assert module.legacy_lottery_error(bundle.hash,bundle.hash,'lottery_draw') is None
    assert module.legacy_lottery_error(bundle.hash,plan['parent_bundle'],'daily_claim') is None
    report=dict(status='OFFLINE_RELEASE_SCOPE_PASS',bundle=bundle.hash,unique_items=len(items),
        changed_sources=sorted(changed_sources),changed_configs=sorted(changed_configs),changed_service_methods=sorted(changed_methods),
        prices_effects_probabilities_and_old_compatibility_preserved=True,strict_file_whitelist=True,
        bytecode_files=0,payment_files=0,pointers_changed=False,remote_executed=False)
    (OUT/'offline_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':main()
