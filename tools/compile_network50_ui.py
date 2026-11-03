"""Mirror explicit network50 author inputs and compile with the Valve compiler.

Only the declared UI sources are touched. Original uncommitted HUD binary is
preserved before the first compile. Produces source/compiled SHA bindings; does
not install, sign, upload, or infer release completion.
"""
from pathlib import Path
import argparse, hashlib, json, struct, subprocess

ROOT=Path(__file__).resolve().parents[1]
ENGINE=ROOT.parents[1]
CONTENT=ENGINE.parent/'content/dota_addons/Survival'
COMPILER=ENGINE/'bin/win64/resourcecompiler.exe'
REPORT=ROOT/'output/network50_compile_20261103'
SOURCES=(
 'common/ui_static_catalog.js','common/compact_wire.js','common/compact_ui_runtime.js',
 'common/compact_archive_model.js','common/compact_daily_model.js',
 'common/compact_hud_model.js','common/compact_hud_source.js','common/compact_lottery_model.js',
 'common/lottery_cache.js','common/purple_shell.js',
 'archive_180de7e38b_titles_compact_v6.js','archive_v10.js','collection_gw2.js',
 'daily_remaining_5d5c1152eb.js','lottery_ui_remaining_5d5c1152eb.js',
 'survival_ui.js','topnav_remaining_5d5c1152eb.js',
 'lottery_cinematic_v1.js','lottery_gw2.js',
)
LAYOUTS=('survival_hud.xml','archive.xml')
DEPENDENCIES=SOURCES[:8]
sha=lambda raw:hashlib.sha256(raw).hexdigest()
def need(ok,why):
    if not ok:raise ValueError(why)
def blocks(raw):
    need(len(raw)>=16,'truncated_compiled_resource')
    offset,count=struct.unpack_from('<II',raw,8)
    start=8+offset
    need(count<128 and start+count*12<=len(raw),'invalid_resource_blocks')
    result={}
    for index in range(count):
        entry=start+index*12
        tag,relative,size=struct.unpack_from('<4sII',raw,entry)
        begin=entry+4+relative
        need(begin+size<=len(raw),'truncated_resource_block')
        result[tag]=raw[begin:begin+size]
    return result
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--only-existing',action='store_true')
    parser.add_argument('--wire-layouts',action='store_true',help='Add explicit shared compact dependencies to both actual roots.')
    parser.add_argument('--materialize-evidence',action='store_true')
    args=parser.parse_args()
    if args.materialize_evidence:
        directory=ROOT/'data/ui/registry_history';directory.mkdir(parents=True,exist_ok=True)
        for path in (ROOT/'output/ui_static_catalog_20261103/registry_history').glob('*.json'):
            raw=path.read_bytes();need(sha(raw)==path.stem,'registry_history_digest_mismatch')
            target=directory/path.name
            if target.exists():need(target.read_bytes().replace(b'\r\n',b'\n')==raw,'immutable_registry_history_changed')
            else:target.write_bytes(raw)
        s2c=(ROOT/'output/network50_native_probe_20261103/native_budget.json').read_bytes()
        c2s=(ROOT/'output/network50_native_probe_20261103/native_c2s_budget.json').read_bytes()
        left,right=json.loads(s2c),json.loads(c2s)
        need(left['engine_build']==right['engine_build'] and left['networksystem_sha256']==right['networksystem_sha256'],'native_builds_differ')
        need(left['value_budget']==right['value_budget']==24 and left['max_admitted_native_bytes']==right['max_admitted_native_bytes']==49,'native_budget_drift')
        evidence=dict(kind='NATIVE_TOOLS_BIDIRECTIONAL_MESSAGE_CALIBRATION_NOT_ORDINARY_ACCEPTANCE',
            server_to_client=left,client_to_server=right,s2c_receipt_sha256=sha(s2c),c2s_receipt_sha256=sha(c2s))
        (ROOT/'data/ui/ui_compact_wire_native_evidence_20261103.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8',newline='\n')
        print(json.dumps(dict(status='PUBLIC_NATIVE_EVIDENCE_AND_IMMUTABLE_REGISTRY_HISTORY_MATERIALIZED')))
        if not args.apply:return
    if args.wire_layouts:
        for name in LAYOUTS:
            path=ROOT/'panorama/src/layout/custom_game'/name
            text=path.read_text(encoding='utf-8')
            if 'common/compact_ui_runtime.js' not in text:
                need(text.count('<scripts>')==1,'unique_layout_script_container_required')
                includes='\n'+''.join('        <include src="file://{resources}/scripts/custom_game/'+source+'" />\n' for source in DEPENDENCIES)
                path.write_text(text.replace('<scripts>','<scripts>'+includes,1),encoding='utf-8',newline='\n')
        if not args.apply:
            print(json.dumps(dict(status='LOCAL_LAYOUT_DEPENDENCIES_WIRED',layouts=LAYOUTS)));return
    mappings=[('panorama/src/scripts/custom_game/'+name,'panorama/scripts/custom_game/'+name,
        'panorama/scripts/custom_game/'+name[:-3]+'.vjs_c') for name in SOURCES]
    mappings += [('panorama/src/layout/custom_game/'+name,'panorama/layout/custom_game/'+name,
        'panorama/layout/custom_game/'+name[:-4]+'.vxml_c') for name in LAYOUTS]
    if args.only_existing:mappings=[row for row in mappings if (ROOT/row[0]).is_file()]
    need(all((ROOT/source).is_file() for source,_,_ in mappings),'declared_source_missing')
    if not args.apply:
        print(json.dumps(dict(status='COMPILE_PLAN_ONLY',inputs=len(mappings),mappings=mappings)));return
    REPORT.mkdir(parents=True,exist_ok=True)
    original=ROOT/'panorama/layout/custom_game/survival_hud.vxml_c'
    preserved=REPORT/'original_uncommitted_survival_hud.vxml_c'
    if not preserved.exists():
        with preserved.open('xb') as out:out.write(original.read_bytes())
    records=[]
    for source,mirror,compiled in mappings:
        authored=(ROOT/source).read_bytes().replace(b'\r\n',b'\n')
        need(b'\r' not in authored,'unexpected_line_ending:'+source)
        physical=authored.replace(b'\n',b'\r\n')
        target=CONTENT/mirror;target.parent.mkdir(parents=True,exist_ok=True)
        if not target.is_file() or target.read_bytes()!=physical:target.write_bytes(physical)
        result=subprocess.run([str(COMPILER),'-i',str(target),'-game',str(ENGINE/'dota'),'-fshallow','-nop4'],
            capture_output=True,timeout=180)
        log=REPORT/(Path(source).name+'.compile.log');log.write_bytes(result.stdout+result.stderr)
        need(result.returncode==0,'official_compile_failed:'+source)
        artifact=(ROOT/compiled).read_bytes();data=blocks(artifact).get(b'DATA')
        if source.endswith('.js'):need(data==physical,'compiled_JS_DATA_not_exact_input:'+source)
        records.append(dict(source=source,content_source=mirror,compiled=compiled,
            source_git_sha256=sha(authored),source_sha256=sha(physical),compiled_sha256=sha(artifact),
            source_normalization='GIT_LF_TO_COMPILER_CRLF_ONLY',compiled_bytes=len(artifact),
            official_compile_exit=0,compiled_data_equals_source=(data==physical) if source.endswith('.js') else None))
        print(json.dumps(dict(compiled=compiled,bytes=len(artifact),sha256=sha(artifact))))
    (REPORT/'compile_binding.json').write_text(json.dumps(dict(status='OFFICIAL_COMPILE_ONLY_NOT_PUBLISHED',
        records=records,preserved_original_sha256=sha(preserved.read_bytes())),indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
