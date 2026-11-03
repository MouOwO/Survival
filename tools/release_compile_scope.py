"""Immutable-source, isolated official compilation for reviewed pending assets.

Plan reads both Git trees once and resolves only requested blobs/LFS objects.
Compile exports those exact compiler bytes to a fresh external content/game
junction pair. It never overwrites the project worktree, signs, submits, starts
a game, deletes files, writes a release journal or changes Git.
"""
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,re,subprocess,time
from collections import Counter
from datetime import datetime,timezone
from pathlib import Path,PurePosixPath

ROOT=Path(__file__).resolve().parents[1]
CONTENT=ROOT.parents[2]/'content/dota_addons/Survival'
ENGINE=ROOT.parents[2]
COMPILER=ENGINE/'game/bin/win64/resourcecompiler.exe'
EXTERNAL=Path('D:/Survival_本地排演/compile_scope_20261103')
HEX=re.compile(r'[a-f0-9]{64}\Z')
REV=re.compile(r'[a-f0-9]{40}\Z')
TEXT={'.js','.css','.xml','.vtex','.svg'}
MAX_OBJECT=32*1024*1024
MAX_TOTAL=256*1024*1024
spec=importlib.util.spec_from_file_location('compile_scope_inventory',Path(__file__).with_name('release_pending_inventory.py'))
inventory=importlib.util.module_from_spec(spec);spec.loader.exec_module(inventory)

def sha(raw):return hashlib.sha256(raw).hexdigest()
def checks(raw):return dict(bytes=len(raw),sha256=sha(raw),md5=hashlib.md5(raw).hexdigest())
def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True)+'\n').encode()
def need(ok,code):
    if not ok:raise ValueError(code)
def safe(path):
    need(isinstance(path,str)and path and '\\'not in path and ':'not in path and not path.startswith('/')and all(p not in ('','.','..')for p in path.split('/')),'unsafe_resource_path')
    return path
def write_new(path,raw):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb')as stream:stream.write(raw)
def read_json(path,digest):
    need(HEX.fullmatch(digest or''),'control_sha256_required');need(path.is_file()and not path.is_symlink()and path.stat().st_size<=16*1024*1024,'bounded_control_json_required')
    raw=path.read_bytes();need(sha(raw)==digest,'control_json_raw_hash_mismatch');return json.loads(raw)
def run_git(root,*args):
    done=subprocess.run(['git','-c','safe.directory='+root.resolve().as_posix(),'--no-replace-objects','-C',str(root),*args],capture_output=True,env={**os.environ,'GIT_OPTIONAL_LOCKS':'0'})
    need(done.returncode==0,'read_only_git_failed');return done.stdout
def immutable(root,revision):
    need(REV.fullmatch(revision or''),'immutable_commit_required');actual=run_git(root,'rev-parse','--verify',revision+'^{commit}').decode().strip();need(actual==revision,'commit_binding_differs');return revision
def no_reparse(path,root):
    need(path.resolve().is_relative_to(root.resolve()),'path_outside_declared_root')
    for item in (path,*path.parents):
        if item==root:break
        need(not item.is_symlink()and not(hasattr(item,'is_junction')and item.is_junction()),'input_reparse_point_refused')

class Reader:
    """Two persistent cat-file streams, local LFS only, bounded source bytes."""
    def __init__(self,roots,trees):
        self.roots,self.trees=roots,trees;self.procs={};self.cache={};self.used=0;self.requests=0
        self.commons={}
        for role,root in roots.items():
            common=Path(run_git(root,'rev-parse','--git-common-dir').decode().strip());self.commons[role]=(common if common.is_absolute()else root/common).resolve()
            self.procs[role]=subprocess.Popen(['git','-c','safe.directory='+root.resolve().as_posix(),'--no-replace-objects','-C',str(root),'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={**os.environ,'GIT_OPTIONAL_LOCKS':'0'})
    def get(self,role,path):
        safe(path);key=(role,path)
        if key in self.cache:return self.cache[key]
        entry=self.trees[role].get(path);need(entry and entry.get('kind')=='blob'and entry.get('mode')in{'100644','100755'},'immutable_source_missing:'+role+':'+path)
        size=entry['bytes'];need(isinstance(size,int)and size<=MAX_OBJECT and self.used+size<=MAX_TOTAL,'source_byte_budget_exceeded')
        proc=self.procs[role];proc.stdin.write((entry['oid']+'\n').encode());proc.stdin.flush();header=proc.stdout.readline(256).decode().strip().split()
        need(header==[entry['oid'],'blob',str(size)],'git_batch_header_mismatch')
        raw=inventory._read_exact(proc.stdout,size);need(proc.stdout.read(1)==b'\n','git_batch_delimiter_mismatch');self.requests+=1;self.used+=size
        original=checks(raw);pointer=inventory.parse_lfs_pointer(raw);content=raw
        if pointer:
            oid,real_size=pointer;need(real_size<=MAX_OBJECT and self.used+real_size<=MAX_TOTAL,'lfs_byte_budget_exceeded')
            base=self.commons[role]/'lfs/objects';target=base/oid[:2]/oid[2:4]/oid;no_reparse(target,base)
            need(target.is_file()and target.stat().st_size==real_size,'local_lfs_object_missing_or_wrong_size')
            content=target.read_bytes();need(sha(content)==oid,'local_lfs_object_hash_mismatch');self.used+=real_size
        result=dict(repo=role,path=path,oid=entry['oid'],mode=entry['mode'],git_blob=original,content=checks(content),lfs=bool(pointer),raw=content)
        self.cache[key]=result;return result
    def close(self):
        for proc in self.procs.values():
            proc.stdin.close();code=proc.wait(timeout=10);proc.stdout.close();proc.stderr.close();need(code==0,'git_batch_exit_failed')

def checkout_binding(git_bytes,physical,text):
    """Only identity or exact LF->CRLF conversion, never whitespace repair."""
    if physical==git_bytes:return 'IDENTITY'
    need(text and b'\r'not in git_bytes and physical==git_bytes.replace(b'\n',b'\r\n'),'physical_source_differs_from_immutable_git')
    return 'GIT_LF_TO_COMPILER_CRLF_ONLY'

def content_source(resource):
    safe(resource)
    suffix=PurePosixPath(resource).suffix
    mapping={'.vjs_c':'.js','.vcss_c':'.css','.vxml_c':'.xml','.vsvg_c':'.svg','.vtex_c':'.vtex'}
    need(resource.startswith('panorama/')and suffix in mapping,'unsupported_official_compiler_mapping')
    return str(PurePosixPath(resource).with_suffix(mapping[suffix]))
def artifact_for(source):
    path=PurePosixPath(safe(source));mapping={'.js':'.vjs_c','.css':'.vcss_c','.xml':'.vxml_c','.svg':'.vsvg_c','.vtex':'.vtex_c'}
    need(path.suffix in mapping,'unsupported_compiler_source_type');return str(path.with_suffix(mapping[path.suffix]))

def dependencies(path,raw):
    """Compiler source includes and VTEX pixels, not guessed runtime assets."""
    suffix=PurePosixPath(path).suffix
    if suffix not in TEXT:return [],[]
    text=raw.decode('utf-8-sig');refs=[];engine=[]
    if suffix=='.vtex':
        pixels=re.findall(r'"m_fileName"\s+"string"\s+"([^"\r\n]+)"',text)
        need(bool(pixels),'vtex_actual_pixel_dependency_required')
        for pixel in pixels:
            safe(pixel);need(pixel.startswith('panorama/images/')and PurePosixPath(pixel).suffix.lower()in{'.png','.tga','.tif','.jpg','.jpeg'},'vtex_pixel_dependency_unreviewed')
            refs.append(pixel)
    if suffix=='.xml':
        for value in re.findall(r'<include\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\']',text):
            prefix='file://{resources}/'
            if value.startswith(prefix):refs.append(safe('panorama/'+value[len(prefix):]))
            elif value.startswith('s2r://'):engine.append(value)
            else:raise ValueError('xml_include_dependency_unreviewed:'+value)
    if suffix=='.css':
        for value in re.findall(r'@import\s+(?:url\()?\s*["\']([^"\']+)["\']',text):
            prefix='file://{resources}/'
            if value.startswith(prefix):refs.append(safe('panorama/'+value[len(prefix):]))
            elif value.startswith('s2r://'):engine.append(value)
            else:raise ValueError('css_import_dependency_unreviewed:'+value)
    if suffix=='.svg':
        for value in re.findall(r'(?:xlink:)?href=["\']([^"\']+)["\']',text):
            if value.startswith(('data:','#')):continue
            if value.startswith('panorama/'):refs.append(safe(value))
            else:raise ValueError('svg_external_dependency_unreviewed')
    return sorted(set(refs)),sorted(set(engine))

def selected_rows(scope):
    rows=[]
    for row in scope.get('decisions',[]):
        if row.get('inventory_status')=='UNBOUND_COMPILED_ARTIFACT'and row.get('review_decision')=='IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING':rows.append(row)
        elif row.get('inventory_status')=='UNMAPPED_SOURCE_PENDING'and str(row.get('resource','')).endswith('.vsvg_c'):rows.append(row)
    need(len({row['resource']for row in rows})==len(rows),'duplicate_compile_scope_resource');return rows

def make_plan(scope,scope_sha,revisions,roots= None):
    roots=roots or{'game':ROOT,'content':CONTENT};counts=Counter(git_processes=0,git_tree_calls=0)
    for role in ('game','content'):immutable(roots[role],revisions[role])
    trees={role:inventory.git_tree(roots[role],counts,revisions[role])for role in roots}
    reader=Reader(roots,trees);results=[];all_inputs={}
    def source_pin(path):
        value=reader.get('content',path);actual=roots['content']/path;no_reparse(actual,roots['content'])
        need(actual.is_file()and actual.stat().st_size<=MAX_OBJECT,'physical_content_source_missing:'+path)
        physical=actual.read_bytes();normalization=checkout_binding(value['raw'],physical,PurePosixPath(path).suffix in TEXT)
        pin={k:v for k,v in value.items()if k!='raw'};pin.update(source_revision=revisions['content'],compiler_input=checks(physical),normalization=normalization)
        mirror='panorama/src/'+path[len('panorama/'):]if path.startswith('panorama/')else None
        if mirror and mirror in trees['game']:
            game=reader.get('game',mirror);game_path=roots['game']/mirror;no_reparse(game_path,roots['game']);game_physical=game_path.read_bytes()
            checkout_binding(game['raw'],game_physical,PurePosixPath(path).suffix in TEXT)
            if PurePosixPath(path).suffix in TEXT:
                need(game['raw'].replace(b'\r\n',b'\n')==value['raw'].replace(b'\r\n',b'\n'),'game_content_authors_differ:'+path)
            else:need(game['raw']==value['raw'],'game_content_binary_sources_differ:'+path)
            pin['game_author']={k:v for k,v in game.items()if k!='raw'};pin['game_author'].update(source_revision=revisions['game'],physical=checks(game_physical))
        return pin,physical
    try:
        for row in selected_rows(scope):
            resource=safe(row['resource']);result=dict(resource=resource,status='BLOCKED',sources=[],engine_references=[],review_decision=row['review_decision'])
            try:
                primary=content_source(resource);queue=[primary];seen=set();pins=[];external=[]
                while queue:
                    path=queue.pop(0)
                    if path in seen:continue
                    seen.add(path);pin,physical=source_pin(path);pins.append(pin)
                    child,engine=dependencies(path,reader.get('content',path)['raw']);external.extend(engine);queue.extend(child)
                    existing=all_inputs.get(path)
                    need(not existing or existing['compiler_input']==pin['compiler_input'],'inconsistent_shared_compiler_input')
                    all_inputs[path]=pin
                result.update(status='READY_FOR_ISOLATED_OFFICIAL_COMPILE',primary_source=primary,sources=pins,engine_references=sorted(set(external)),reviewed_candidate_sha256=row.get('candidate',{}).get('sha256'))
            except (ValueError,UnicodeDecodeError,OSError)as error:result['error']=str(error)
            results.append(result)
    finally:reader.close()
    return dict(schema=1,kind='IMMUTABLE_ISOLATED_OFFICIAL_COMPILE_PLAN',scope_sha256=scope_sha,source_revisions=revisions,
        scope_observed_commits=scope.get('observed_commits'),resources=results,inputs=all_inputs,
        counts=dict(Counter(row['status']for row in results)),read_costs=dict(git_tree_calls=counts['git_tree_calls'],git_batch_processes=2,blob_requests=reader.requests,source_bytes=reader.used),
        tool_sha256=sha(Path(__file__).read_bytes()),publication_ready=False,sdk_calls=0,git_mutations=0,project_worktree_writes=0)

def compile_plan(plan,plan_sha,run_id,proof_dir):
    need(plan.get('kind')=='IMMUTABLE_ISOLATED_OFFICIAL_COMPILE_PLAN','immutable_compile_plan_required')
    need(plan.get('tool_sha256')==sha(Path(__file__).read_bytes()),'compiler_tool_changed_since_plan')
    need(re.fullmatch(r'[a-z0-9_]{6,48}',run_id or''),'isolated_compile_run_id_required')
    roots={'game':ROOT,'content':CONTENT};revisions=plan['source_revisions']
    # Recreate all source checks just before staging. The new plan must be
    # supplied again if source bytes/physical mirrors changed in the meantime.
    for role in roots:immutable(roots[role],revisions[role])
    counts=Counter(git_processes=0,git_tree_calls=0);trees={role:inventory.git_tree(roots[role],counts,revisions[role])for role in roots};reader=Reader(roots,trees)
    stage=EXTERNAL/run_id;stage_game=stage/'game';stage_content=stage/'content';alias='svt_compile_'+run_id
    game_mount=ROOT.parent/alias;content_mount=CONTENT.parent/alias
    need(stage.resolve().parent==EXTERNAL.resolve(),'external_compile_stage_parent_differs')
    need(proof_dir.resolve().is_relative_to((ROOT/'output').resolve()),'proof_output_must_stay_in_workspace_output')
    for path in (stage,game_mount,content_mount,proof_dir):need(not os.path.lexists(path),'fresh_stage_mount_and_proof_required:'+str(path))
    need(COMPILER.is_file(),'official_resourcecompiler_required');compiler_sha=checks(COMPILER.read_bytes())['sha256'];ready=[r for r in plan['resources']if r['status']=='READY_FOR_ISOLATED_OFFICIAL_COMPILE']
    required={p['path'] for row in ready for p in row['sources']};payloads={}
    try:
        for row in ready:
            safe(row['resource']);safe(row['primary_source']);need(artifact_for(row['primary_source'])==row['resource'],'plan_artifact_source_mapping_changed')
        for path in sorted(required):
            safe(path)
            pin=plan['inputs'][path];value=reader.get('content',path);need(value['git_blob']==pin['git_blob']and value['content']==pin['content']and value['oid']==pin['oid'],'immutable_git_input_pin_changed')
            no_reparse(CONTENT/path,CONTENT)
            physical=(CONTENT/path).read_bytes();need(checks(physical)==pin['compiler_input'],'physical_source_changed_after_plan:'+path)
            checkout_binding(value['raw'],physical,PurePosixPath(path).suffix in TEXT)
            if pin.get('game_author'):
                author=pin['game_author'];safe(author['path']);no_reparse(ROOT/author['path'],ROOT);game=reader.get('game',author['path']);need(game['git_blob']==author['git_blob']and checks((ROOT/author['path']).read_bytes())==author['physical'],'game_author_changed_after_plan:'+path)
            payloads[path]=physical
    finally:reader.close()
    stage_game.mkdir(parents=True);stage_content.mkdir();proof_dir.mkdir(parents=True)
    for path,raw in payloads.items():write_new(stage_content/path,raw)
    for mount,target in ((game_mount,stage_game),(content_mount,stage_content)):
        subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',"New-Item -ItemType Junction -Path '"+str(mount)+"' -Target '"+str(target)+"' | Out-Null"],check=True)
        need(mount.resolve()==target.resolve(),'isolated_compiler_mount_mismatch')
    results=[]
    for row in plan['resources']:
        if row['status']!='READY_FOR_ISOLATED_OFFICIAL_COMPILE':results.append(dict(resource=row['resource'],status='BLOCKED',error=row.get('error')));continue
        source=content_mount/row['primary_source'];artifact=stage_game/row['resource'];before=checks(artifact.read_bytes())if artifact.is_file()else None
        args=[str(COMPILER),'-i',str(source),'-game',str(ENGINE/'game/dota'),'-fshallow','-nop4']
        started=datetime.now(timezone.utc).isoformat();begin=time.monotonic();done=subprocess.run(args,capture_output=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0));elapsed=time.monotonic()-begin
        log=done.stdout+done.stderr;log_name=row['resource'].replace('/','_')+'.log';write_new(proof_dir/'logs'/log_name,log)
        result=dict(resource=row['resource'],started_utc=started,elapsed_seconds=round(elapsed,6),compiler_exit_code=done.returncode,compiler_argv=args,compiler_log_sha256=sha(log),compiler_log=log_name)
        if done.returncode!=0 or b'0 failed'not in log or not artifact.is_file()or artifact.stat().st_size==0:
            result.update(status='OFFICIAL_COMPILE_FAILED',error='compiler_exit_log_or_artifact_failed');results.append(result);continue
        for pin in row['sources']:need(checks((stage_content/pin['path']).read_bytes())==pin['compiler_input'],'staged_source_changed_during_compile')
        output=checks(artifact.read_bytes());result.update(status='OFFICIALLY_COMPILED_AND_SOURCE_BOUND',artifact_path=str(artifact),artifact=output,prior_stage_artifact=before,
            primary_source=row['primary_source'],inputs=row['sources'],engine_references=row['engine_references'])
        results.append(result)
    report=dict(schema=1,kind='ISOLATED_OFFICIAL_COMPILER_PROOF',plan_sha256=plan_sha,source_revisions=revisions,scope_sha256=plan['scope_sha256'],
        compiler_path=str(COMPILER),compiler_sha256=compiler_sha,tool_sha256=sha(Path(__file__).read_bytes()),external_stage=str(stage),game_mount=str(game_mount),content_mount=str(content_mount),
        results=results,counts=dict(Counter(r['status']for r in results)),complete=all(r['status']=='OFFICIALLY_COMPILED_AND_SOURCE_BOUND'for r in results),
        sdk_calls=0,git_mutations=0,project_worktree_writes=0,publication_ready=False)
    write_new(proof_dir/'proof.json',canonical(report));return report

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='action',required=True)
    plan=sub.add_parser('plan');plan.add_argument('--scope',type=Path,required=True);plan.add_argument('--scope-sha256',required=True);plan.add_argument('--game-source',required=True);plan.add_argument('--content-source',required=True);plan.add_argument('--out',type=Path,required=True)
    compile=sub.add_parser('compile');compile.add_argument('--plan',type=Path,required=True);compile.add_argument('--plan-sha256',required=True);compile.add_argument('--run-id',required=True);compile.add_argument('--proof-dir',type=Path,required=True)
    args=parser.parse_args(argv)
    if args.action=='plan':
        scope=read_json(args.scope,args.scope_sha256);value=make_plan(scope,args.scope_sha256,{'game':args.game_source,'content':args.content_source});write_new(args.out,canonical(value))
    else:value=compile_plan(read_json(args.plan,args.plan_sha256),args.plan_sha256,args.run_id,args.proof_dir)
    print(json.dumps(dict(kind=value['kind'],counts=value['counts'],complete=value.get('complete',False),publication_ready=False,project_worktree_writes=0),ensure_ascii=True))
if __name__=='__main__':main()
