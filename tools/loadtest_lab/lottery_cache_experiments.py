"""Opt-in immutable lottery revision cache: fixed two-source startup proof.
No per-request work. Source bytes are reversed and replayed before archetype use.
"""
from pathlib import Path
import hashlib,re,subprocess
KEY="lottery_static_cache"
OPERATOR="operator/runtime_experiments/lottery_revision_cache.py"
RECIPE_SHA = '95deddc5713753e88f1013df71e96da5640a3bc99de57ca900e5de3829a3b9bd'
PARENTS = {'runtime/archive_backend/settlement_runner.py': '61c51346fc526a76816810469b6a8f82e1fe9b0a548628e0d18d9ac897421234', 'runtime/archive_backend/worker_fast.lua': '4a85d79d97599f44bc5026bad154f0f2ffbe35b024151ca327a30625716d20b4'}
OUTPUTS = {'runtime/archive_backend/settlement_runner.py': 'd83fc0dbd39d6fe593f0a49f7c6b34b30eb93abeadb37e67bcfccc03898453dc', 'runtime/archive_backend/worker_fast.lua': 'a34e00e825941793109b9870dc6237ded5490baa4d0e7e815c8712267b2ba256'}

def need(ok,code):
    if not ok: raise ValueError(code)
def sha(raw): return hashlib.sha256(raw).hexdigest()
def metadata(cfg):
    if KEY not in cfg:
        need(OPERATOR not in cfg.get("sources",{}),"lottery_cache_binding_missing")
        return {}
    row=cfg[KEY]
    need(type(row)is dict and set(row)=={"id","source_revision","recipe_sha256","parent_sources","output_sources"}
        and row["id"]=="pool-revisions-v1" and cfg.get("kind")=="SURVIVAL_ISOLATED_LOADTEST"
        and cfg.get("purpose")=="capacity" and cfg.get("backend_db_pool")=="bounded-v2", "lottery_cache_metadata_invalid")
    need(type(row["source_revision"])is str and re.fullmatch("[a-f0-9]{40}",row["source_revision"])
        and row["source_revision"]==cfg.get("csv_source_revision") and row["recipe_sha256"]==RECIPE_SHA
        and row["parent_sources"]==PARENTS and row["output_sources"]==OUTPUTS
        and cfg["sources"].get(OPERATOR)==RECIPE_SHA
        and all(cfg["sources"].get(k)==v for k,v in OUTPUTS.items()),"lottery_cache_exact_binding_required")
    return dict(PARENTS)
def validate(cfg,read_source):
    if not metadata(cfg): return {}
    raw=read_source(OPERATOR)
    need(type(raw)is bytes and len(raw)<=32768 and sha(raw)==RECIPE_SHA,"lottery_cache_recipe_changed")
    ns={"__name__":"exact_reviewed_lottery_cache"};exec(compile(raw,OPERATOR,"exec"),ns)
    restored={}
    for target,digest in OUTPUTS.items():
        output=read_source(target);need(type(output)is bytes and len(output)<=65536 and sha(output)==digest,"lottery_cache_output_bytes_changed")
        name=target.removeprefix("runtime/");parent=ns["transform"](name,output,True)
        need(sha(parent)==PARENTS[target] and ns["transform"](name,parent)==output,"lottery_cache_parent_replay_failed")
        restored[target]=sha(parent)
    return restored
def prepare(root,cfg,revision,mode,repository):
    need(mode in("baseline","pool-revisions-v1") and KEY not in cfg,"lottery_cache_mode_invalid")
    if mode=="baseline": metadata(cfg);return
    root,repository=Path(root),Path(repository)
    need(not(root/"lab.json").exists() and not(root/OPERATOR).exists() and revision==cfg["csv_source_revision"],"lottery_cache_new_lab_required")
    source="server/fishing_api_overrides/lottery_revision_cache.py"
    raw=subprocess.run(["git","-C",str(repository),"show",revision+":"+source],capture_output=True,check=True).stdout
    need(sha(raw)==RECIPE_SHA and raw.replace(b"\r\n",b"\n")== (repository/source).read_bytes().replace(b"\r\n",b"\n"),"lottery_cache_committed_recipe_required")
    ns={"__name__":"reviewed_lottery_cache_prepare"};exec(compile(raw,OPERATOR,"exec"),ns)
    changed={}
    for target,digest in PARENTS.items():
        original=(root/target).read_bytes();need(cfg["sources"].get(target)==digest and sha(original)==digest,"lottery_cache_parent_changed")
        changed[target]=ns["transform"](target.removeprefix("runtime/"),original)
    path=root/OPERATOR;path.parent.mkdir(parents=True,exist_ok=True);path.open("xb").write(raw);cfg["sources"][OPERATOR]=RECIPE_SHA
    for target,output in changed.items(): (root/target).write_bytes(output);cfg["sources"][target]=sha(output)
    cfg[KEY]={"id":mode,"source_revision":revision,"recipe_sha256":RECIPE_SHA,"parent_sources":PARENTS,"output_sources":OUTPUTS}
    validate(cfg,lambda name:(root/name).read_bytes())
