"""Immutable-source, isolated official compilation for reviewed pending assets.

Plan reads both Git trees once and resolves only requested blobs/LFS objects.
Compile exports those exact compiler bytes to a fresh external content/game
junction pair. It never overwrites the project worktree, signs, submits, starts
a game, deletes files, writes a release journal or changes Git.
"""
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,re,struct,subprocess,time
from collections import Counter,deque
from datetime import datetime,timezone
from pathlib import Path,PurePosixPath

ROOT=Path(__file__).resolve().parents[1]
EXECUTED_TOOL_LF_SHA256=hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n',b'\n')).hexdigest()
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
inventory=importlib.util.module_from_spec(spec)
_inventory_bytes=Path(spec.origin).read_bytes()
EXECUTED_INVENTORY_LF_SHA256=hashlib.sha256(_inventory_bytes.replace(b'\r\n',b'\n')).hexdigest()
exec(compile(_inventory_bytes,spec.origin,'exec'),inventory.__dict__)

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

def compiler_bytes(raw,text):
    """Canonical compiler input is derived only from the immutable Git blob.

    A physical checkout may have mixed line endings or unrelated user edits;
    neither can change the bytes of an isolated source-bound compilation.
    """
    if not text:return raw,'BINARY_GIT_IDENTITY'
    normalized=raw.replace(b'\r\n',b'\n')
    need(b'\r'not in normalized,'immutable_text_lone_cr_requires_review')
    result=normalized.replace(b'\n',b'\r\n')
    return result,'GIT_IDENTITY'if result==raw else'IMMUTABLE_GIT_TEXT_TO_COMPILER_CRLF_ONLY'

def runtime_raw_dependency(path):
    """MoviePanel src checks raw WebM in game, not the content source tree."""
    safe(path)
    return path.startswith('panorama/videos/') and PurePosixPath(path).suffix=='.webm'

def stage_source(stage_content,stage_game,path,raw):
    # One write per unique dependency. Only immutable plan payloads reach this
    # function; raw movies are mirrored without conversion or directory scans.
    safe(path);write_new(stage_content/path,raw)
    if runtime_raw_dependency(path):write_new(stage_game/path,raw)

def operator_binding(revision):
    immutable(ROOT,revision);result={}
    for relative in ('tools/release_compile_scope.py','tools/release_pending_inventory.py'):
        declared=run_git(ROOT,'show',revision+':'+relative).replace(b'\r\n',b'\n')
        actual=(ROOT/relative).read_bytes().replace(b'\r\n',b'\n')
        need(actual==declared,'executed_operator_tool_differs_from_commit:'+relative)
        loaded=EXECUTED_TOOL_LF_SHA256 if relative.endswith('/release_compile_scope.py')else EXECUTED_INVENTORY_LF_SHA256
        need(sha(declared)==loaded,'loaded_operator_tool_differs_from_commit:'+relative)
        result[relative]=sha(declared)
    return dict(revision=revision,tools_lf_sha256=result)

def content_source(resource):
    safe(resource)
    suffix=PurePosixPath(resource).suffix
    mapping={'.vjs_c':'.js','.vcss_c':'.css','.vxml_c':'.xml','.vsvg_c':'.svg','.vtex_c':'.vtex'}
    need(resource.startswith('panorama/')and suffix in mapping,'unsupported_official_compiler_mapping')
    return str(PurePosixPath(resource).with_suffix(mapping[suffix]))
def artifact_for(source):
    path=PurePosixPath(safe(source));mapping={'.js':'.vjs_c','.css':'.vcss_c','.xml':'.vxml_c','.svg':'.vsvg_c','.vtex':'.vtex_c'}
    need(path.suffix in mapping,'unsupported_compiler_source_type');return str(path.with_suffix(mapping[path.suffix]))

def compiled_binding(resource,raw,compiler_input):
    """Validate native block bounds and exact embedded JS compiler bytes."""
    need(28<=len(raw)<=MAX_OBJECT,'compiled_resource_absent_or_oversized')
    size,version,_,offset,count=struct.unpack_from('<IHHII',raw);table=8+offset
    texture=resource.endswith('.vtex_c')
    # Native texture files append image payload after the resource metadata.
    # Other reviewed Panorama resource types must end at their declared size.
    need((16<=size<=len(raw)if texture else size==len(raw))and version==12 and 1<=count<=64
         and 16<=table<=size-12*count,'compiled_resource_header_invalid')
    blocks={};ranges=[]
    for index in range(count):
        entry=table+index*12;tag,displacement,length=struct.unpack_from('<4sII',raw,entry);start=entry+4+displacement
        need(all(32<=value<=126 for value in tag)and tag not in blocks and start>=table+count*12 and start+length<=size
             and not any(start<end and begin<start+length for begin,end in ranges),'compiled_resource_block_invalid')
        blocks[tag]=raw[start:start+length];ranges.append((start,start+length))
    need(b'DATA'in blocks,'compiled_resource_data_missing')
    is_js=resource.endswith('.vjs_c')
    if is_js:need(blocks[b'DATA']==compiler_input,'compiled_js_data_differs_from_immutable_compiler_input')
    return dict(blocks=[dict(tag=tag.decode('ascii'),bytes=len(value),sha256=sha(value))for tag,value in blocks.items()],
                resource_metadata_bytes=size,texture_external_payload_bytes=len(raw)-size if texture else 0,
                texture_external_payload_sha256=sha(raw[size:])if texture and len(raw)>size else None,
                compiled_js_DATA_equals_input=True if is_js else None,rerl_bytes=len(blocks.get(b'RERL',b'')))

def dependencies(path,raw):
    """Actual XML layouts, CSS image/import URLs and VTEX pixel dependencies."""
    suffix=PurePosixPath(path).suffix
    if suffix not in TEXT:return [],[]
    text=raw.decode('utf-8-sig');refs=[];engine=[]
    if suffix=='.js' and path=='panorama/scripts/custom_game/lottery_cinematic_v1.js':
        # The decoder probe loads an EXISTING compiled CSS through Movie API.
        # Bind its content CSS author and recursive image closure, never a
        # nonexistent content .vcss_c. Its runtime is independently compiled
        # and checked in the complete manifest/native probe evidence.
        probe=re.search(r"\bvar DECODER_PROBE_MOVIE='([^']+)';",text)
        if probe:
            need(probe[1]=='file://{resources}/styles/custom_game/lottery_cinematic_v1.vcss_c','fixed_existing_decoder_probe_uri_required')
            refs.append(content_source('panorama/styles/custom_game/lottery_cinematic_v1.vcss_c'))
        else:need('PreviewDecoderProbe' not in text,'decoder_probe_typed_dependency_missing')
    if suffix=='.vtex':
        pixels=re.findall(r'"m_fileName"\s+"string"\s+"([^"\r\n]+)"',text)
        need(bool(pixels),'vtex_actual_pixel_dependency_required')
        for pixel in pixels:
            safe(pixel);need(pixel.startswith('panorama/images/')and PurePosixPath(pixel).suffix.lower()in{'.png','.tga','.tif','.jpg','.jpeg'},'vtex_pixel_dependency_unreviewed')
            refs.append(pixel)
    def reference(value):
        if value.startswith('file://{resources}/'):refs.append(safe('panorama/'+value[len('file://{resources}/'):]))
        elif value.startswith('file://{images}/'):refs.append(safe('panorama/images/'+value[len('file://{images}/'):]))
        elif value.startswith('s2r://'):engine.append(value)
        elif value.startswith('#'):return
        else:raise ValueError('compiler_dependency_unreviewed:'+value)
    if suffix=='.xml':
        for value in re.findall(r'\b(?:src|layoutfile)\s*=\s*["\']([^"\']+)["\']',text):reference(value)
    if suffix=='.css':
        # Do not confuse url() in comments with an active dependency, or miss
        # unquoted background-image URLs. Empty URLs are invalid, never hidden.
        text=re.sub(r'/\*.*?\*/','',text,flags=re.S)
        for match in re.finditer(r'url\(\s*(?:"([^"\r\n]*)"|\'([^\'\r\n]*)\'|([^\s)]+))\s*\)',text):
            value=next((value for value in match.groups()if value is not None),'')
            need(bool(value),'css_empty_url_requires_review');reference(value)
        need(re.search(r'url\(\s*\)',text)is None,'css_empty_url_requires_review')
        for value in re.findall(r'@import\s+["\']([^"\']+)["\']',text):reference(value)
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

def make_plan(scope,scope_sha,revisions,roots=None,operator_revision=None):
    roots=roots or{'game':ROOT,'content':CONTENT};counts=Counter(git_processes=0,git_tree_calls=0)
    for role in ('game','content'):immutable(roots[role],revisions[role])
    trees={role:inventory.git_tree(roots[role],counts,revisions[role])for role in roots}
    operator=operator_binding(operator_revision)if operator_revision else None
    reader=Reader(roots,trees);results=[];all_inputs={};dependency_cache={}
    def source_pin(path):
        value=reader.get('content',path)
        payload,normalization=compiler_bytes(value['raw'],PurePosixPath(path).suffix in TEXT)
        pin={k:v for k,v in value.items()if k!='raw'};pin.update(source_revision=revisions['content'],compiler_input=checks(payload),normalization=normalization)
        cover_author=inventory.LOADING_COVER_AUTHORS.get(path)
        mirror=cover_author or (path if runtime_raw_dependency(path) else 'panorama/src/'+path[len('panorama/'):]if path.startswith('panorama/')else None)
        if cover_author:need(mirror in trees['game'],'loading_cover_game_author_missing:'+path)
        if runtime_raw_dependency(path):need(mirror in trees['game'],'raw_movie_game_author_missing:'+path)
        if mirror and mirror in trees['game']:
            game=reader.get('game',mirror)
            if PurePosixPath(path).suffix in TEXT:
                need(compiler_bytes(game['raw'],True)[0]==payload,'game_content_authors_differ:'+path)
            else:need(game['raw']==value['raw'],'game_content_binary_sources_differ:'+path)
            pin['game_author']={k:v for k,v in game.items()if k!='raw'};pin['game_author'].update(source_revision=revisions['game'])
        return pin,payload
    try:
        for row in selected_rows(scope):
            resource=safe(row['resource']);result=dict(resource=resource,status='BLOCKED',sources=[],engine_references=[],review_decision=row['review_decision'])
            try:
                primary=content_source(resource);queue=deque([primary]);seen=set();pins=[];external=[]
                while queue:
                    path=queue.popleft()
                    if path in seen:continue
                    seen.add(path)
                    pin,payload=source_pin(path);pins.append(pin)
                    if path not in dependency_cache:dependency_cache[path]=dependencies(path,reader.get('content',path)['raw'])
                    child,engine=dependency_cache[path];external.extend(engine);queue.extend(child)
                    if PurePosixPath(path).suffix.lower()in{'.png','.jpg','.jpeg','.tga','.tif'}:
                        descriptor=str(PurePosixPath(path).with_suffix('.vtex'))
                        if descriptor in trees['content']:queue.append(descriptor)
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
        tool_sha256=sha(Path(__file__).read_bytes()),operator_binding=operator,publication_ready=False,sdk_calls=0,git_mutations=0,project_worktree_writes=0)

def compile_execution_rows(rows):
    """One fixed descriptor runs after its Panorama implicit dependencies.

    Preserve every other relative order. Proof rows remain in the original
    plan order; this execution order is not a different source/coverage plan.
    Cold O(N) rows and O(N) references; no runtime/game work.
    """
    return ([row for row in rows if row['resource'] != inventory.LOADING_COVER_RESOURCE]
            + [row for row in rows if row['resource'] == inventory.LOADING_COVER_RESOURCE])


def finalize_compile_results(plan_rows, results):
    """Refuse a successful proof if a later native command changed an output."""
    by_resource = {row['resource']: row for row in results}
    expected = [row['resource'] for row in plan_rows]
    need(len(by_resource) == len(results) == len(expected)
         and len(set(expected)) == len(expected) and set(by_resource) == set(expected),
         'final_compile_result_scope_changed')
    ordered = [by_resource[name] for name in expected]
    for result in ordered:
        if result['status'] != 'OFFICIALLY_COMPILED_AND_SOURCE_BOUND':
            continue
        artifact = Path(result['artifact_path'])
        need(artifact.is_file() and checks(artifact.read_bytes()) == result['artifact'],
             'compiler_artifact_changed_after_later_compile:' + result['resource'])
    return ordered


def compile_plan(plan,plan_sha,run_id,proof_dir):
    need(plan.get('kind')=='IMMUTABLE_ISOLATED_OFFICIAL_COMPILE_PLAN','immutable_compile_plan_required')
    need(plan.get('tool_sha256')==sha(Path(__file__).read_bytes()),'compiler_tool_changed_since_plan')
    need(plan.get('operator_binding')and operator_binding(plan['operator_binding']['revision'])==plan['operator_binding'],'immutable_operator_binding_required')
    need(re.fullmatch(r'[a-z0-9_]{6,48}',run_id or''),'isolated_compile_run_id_required')
    roots={'game':ROOT,'content':CONTENT};revisions=plan['source_revisions']
    # Recreate immutable source checks. Physical worktree bytes are never inputs.
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
            payload,normalization=compiler_bytes(value['raw'],PurePosixPath(path).suffix in TEXT)
            need(checks(payload)==pin['compiler_input']and normalization==pin['normalization'],'immutable_compiler_input_changed_after_plan:'+path)
            if pin.get('game_author'):
                author=pin['game_author'];safe(author['path']);game=reader.get('game',author['path']);need(game['git_blob']==author['git_blob']and game['content']==author['content'],'game_author_changed_after_plan:'+path)
            payloads[path]=payload
    finally:reader.close()
    stage_game.mkdir(parents=True);stage_content.mkdir();proof_dir.mkdir(parents=True)
    for path,raw in payloads.items():stage_source(stage_content,stage_game,path,raw)
    created_mounts=[]
    try:
        for mount,target in ((game_mount,stage_game),(content_mount,stage_content)):
            subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',"New-Item -ItemType Junction -Path '"+str(mount)+"' -Target '"+str(target)+"' | Out-Null"],check=True)
            created_mounts.append((mount,target))
            need(mount.resolve()==target.resolve(),'isolated_compiler_mount_mismatch')
        results=[]
        for row in compile_execution_rows(plan['resources']):
            if row['status']!='READY_FOR_ISOLATED_OFFICIAL_COMPILE':results.append(dict(resource=row['resource'],status='BLOCKED',error=row.get('error')));continue
            source=content_mount/row['primary_source'];artifact=stage_game/row['resource'];before=checks(artifact.read_bytes())if artifact.is_file()else None
            for pin in row['sources']:
                if runtime_raw_dependency(pin['path']):
                    need(checks((stage_game/pin['path']).read_bytes())==pin['compiler_input'],'staged_runtime_raw_changed_before_compile')
            args=[str(COMPILER),'-i',str(source),'-game',str(ENGINE/'game/dota'),'-fshallow','-nop4']
            started=datetime.now(timezone.utc).isoformat();begin=time.monotonic();done=subprocess.run(args,capture_output=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0));elapsed=time.monotonic()-begin
            log=done.stdout+done.stderr;log_name=row['resource'].replace('/','_')+'.log';write_new(proof_dir/'logs'/log_name,log)
            result=dict(resource=row['resource'],started_utc=started,elapsed_seconds=round(elapsed,6),compiler_exit_code=done.returncode,compiler_argv=args,compiler_log_sha256=sha(log),compiler_log=log_name)
            if done.returncode!=0 or b'0 failed'not in log or not artifact.is_file()or artifact.stat().st_size==0:
                result.update(status='OFFICIAL_COMPILE_FAILED',error='compiler_exit_log_or_artifact_failed');results.append(result);continue
            runtime_raw={}
            for pin in row['sources']:
                need(checks((stage_content/pin['path']).read_bytes())==pin['compiler_input'],'staged_source_changed_during_compile')
                if runtime_raw_dependency(pin['path']):
                    actual=checks((stage_game/pin['path']).read_bytes())
                    need(actual==pin['compiler_input'],'staged_runtime_raw_changed_during_compile')
                    runtime_raw[pin['path']]=actual
            raw=artifact.read_bytes();output=checks(raw)
            try:binding=compiled_binding(row['resource'],raw,payloads[row['primary_source']])
            except ValueError as error:
                result.update(status='OFFICIAL_COMPILE_FAILED',error=str(error));results.append(result);continue
            result.update(status='OFFICIALLY_COMPILED_AND_SOURCE_BOUND',artifact_path=str(artifact),artifact=output,prior_stage_artifact=before,
                primary_source=row['primary_source'],inputs=row['sources'],engine_references=row['engine_references'],**binding)
            if runtime_raw:result['runtime_raw_dependencies']=runtime_raw
            results.append(result)
        results = finalize_compile_results(plan['resources'], results)
        report=dict(schema=1,kind='ISOLATED_OFFICIAL_COMPILER_PROOF',plan_sha256=plan_sha,source_revisions=revisions,scope_sha256=plan['scope_sha256'],
            compiler_path=str(COMPILER),compiler_sha256=compiler_sha,tool_sha256=sha(Path(__file__).read_bytes()),operator_binding=plan['operator_binding'],external_stage=str(stage),game_mount=str(game_mount),content_mount=str(content_mount),
            results=results,counts=dict(Counter(r['status']for r in results)),complete=all(r['status']=='OFFICIALLY_COMPILED_AND_SOURCE_BOUND'for r in results),
            sdk_calls=0,git_mutations=0,project_worktree_writes=0,publication_ready=False)
        write_new(proof_dir/'proof.json',canonical(report));return report
    finally:
        # Junction removal is nonrecursive and only targets mounts this call
        # created after all immutable exports were checked. Preserve the LAB.
        for mount,target in reversed(created_mounts):
            need(mount.is_junction()and mount.resolve()==target.resolve(),'compiler_mount_changed_before_cleanup')
            os.rmdir(mount)

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='action',required=True)
    plan=sub.add_parser('plan');plan.add_argument('--scope',type=Path,required=True);plan.add_argument('--scope-sha256',required=True);plan.add_argument('--game-source',required=True);plan.add_argument('--content-source',required=True);plan.add_argument('--operator-source',required=True);plan.add_argument('--out',type=Path,required=True)
    compile=sub.add_parser('compile');compile.add_argument('--plan',type=Path,required=True);compile.add_argument('--plan-sha256',required=True);compile.add_argument('--run-id',required=True);compile.add_argument('--proof-dir',type=Path,required=True)
    args=parser.parse_args(argv)
    if args.action=='plan':
        scope=read_json(args.scope,args.scope_sha256);value=make_plan(scope,args.scope_sha256,{'game':args.game_source,'content':args.content_source},operator_revision=args.operator_source);write_new(args.out,canonical(value))
    else:value=compile_plan(read_json(args.plan,args.plan_sha256),args.plan_sha256,args.run_id,args.proof_dir)
    print(json.dumps(dict(kind=value['kind'],counts=value['counts'],complete=value.get('complete',False),publication_ready=False,project_worktree_writes=0),ensure_ascii=True))
if __name__=='__main__':main()
