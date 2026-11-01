"""Read-only immutable Git export versus an authenticated runtime manifest.

The publication commit is NOT a runtime baseline. Protected-source provenance,
explicit admission projection and native compiler bindings are separate maps.
No blanket equality exemption is provided for historical unpublished code.
"""
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import re
import subprocess

PROTECTION_REPORT = Path('D:/Survival_发布候选/20261029_ws4_archive_all_v01_lua/_lua_protection_report.json')
PROTECTION_SHA = '11c90e1acf49a38d6a5b6a96a83e4b2e4dc76edf3d3aaa542a17dbfda3d439c9'
CATALOG_REPORT = Path('D:/Survival_发布候选/20261031_ws4_wall_perf_v01_catalog_work/catalog_protection_report.json')
CATALOG_SHA = '85aedd97fbd433f0a0d8a00bad863e913e3c65d2fb9ac0d52b07d2e599051af7'
CATALOG = 'scripts/vscripts/config/generated/asset_catalog.lua'
TEXT_SUFFIXES = {'.lua', '.txt', '.gameevents'}


def need(ok, message):
    if not ok: raise ValueError(message)


def sha(raw): return hashlib.sha256(raw).hexdigest()


def checks(raw):
    return dict(bytes=len(raw),md5=hashlib.md5(raw).hexdigest(),sha256=sha(raw))


def git_tree(root, revision):
    need(re.fullmatch(r'[a-f0-9]{40}',revision or '') is not None,'Immutable Git40 required')
    result=subprocess.run(['git','-c','safe.directory='+Path(root).resolve().as_posix(),'--no-replace-objects','-C',str(root),'ls-tree','-rlz','--full-tree',revision],
        capture_output=True,timeout=30,env={**os.environ,'GIT_OPTIONAL_LOCKS':'0'})
    need(result.returncode==0 and len(result.stdout)<=32*1024*1024,'Cannot read bounded immutable Git tree')
    entries={}
    for item in result.stdout.split(b'\0'):
        if not item:continue
        header,name=item.split(b'\t',1);mode,kind,oid,size=header.split()
        name=name.decode('utf-8','strict')
        need(name not in entries and not name.startswith('/') and '\\' not in name
            and not set(PurePosixPath(name).parts).intersection({'.','..'}),'Unsafe/duplicate Git path')
        entries[name]=dict(mode=mode.decode(),kind=kind.decode(),oid=oid.decode(),bytes=int(size) if size.isdigit() else None)
    return entries


def selected(name, runtime, parent_paths):
    path=PurePosixPath(name)
    if any(part.startswith('.') or part in runtime.BLOCKED_PARTS for part in path.parts):return False
    if name in runtime.EXCLUDED_EXACT:return False
    if name in runtime.EXACT or name in runtime.OPTIONAL_EXACT:return True
    if name in runtime.SCENE_MAPS or name in {'maps/ws4_entry.vpk','maps/template_map.vpk'}:return True
    for directory,extensions in runtime.RULES.items():
        if name.startswith(directory+'/') and path.suffix.lower() in extensions:return True
    return False


def protection_sources(parent_rows):
    raw=PROTECTION_REPORT.read_bytes()
    need(sha(raw)==PROTECTION_SHA,'Original protection source evidence changed')
    data=json.loads(raw)
    need(data.get('selected_files')==184 and data.get('status')=='PASS_REQUIRES_NATIVE_SMOKE',
        'Original184 protection evidence required')
    result={}
    for row in data['files']:
        name=row['path'];need(name not in result,'Duplicate original protection row')
        result[name]=dict(source_sha256=row['before']['sha256'],after=row['after'])
    raw=CATALOG_REPORT.read_bytes()
    need(sha(raw)==CATALOG_SHA,'Published catalog reprotection evidence changed')
    updated=json.loads(raw)
    need(updated.get('path')==CATALOG and updated.get('status')=='PASS_REQUIRES_NATIVE_SMOKE'
        and updated.get('source_hashes_unchanged') is True,'Published catalog source evidence required')
    result[CATALOG]=dict(source_sha256=updated['target_source_sha256'],after=updated['output'])
    need(len(result)==184,'Exactly184 source-to-protected correspondences required')
    for name,pin in result.items():
        need(name in parent_rows and all(parent_rows[name][k]==pin['after'][k] for k in ('bytes','md5','sha256')),
            'Protected source evidence does not match authenticated parent: '+name)
    return result


def source_matches(raw, expected_sha):
    if sha(raw)==expected_sha:return 'IDENTITY'
    # Explicit line-ending conversion only; no BOM/comment/whitespace removal.
    if b'\r' not in raw and sha(raw.replace(b'\n',b'\r\n'))==expected_sha:
        return 'GIT_LF_TO_REVIEWED_CRLF_ONLY'
    return None


class GitBatch:
    """One local read-only Git child; stream large artifacts without RAM copies."""
    def __init__(self,root):
        self.process=subprocess.Popen(['git','-c','safe.directory='+Path(root).resolve().as_posix(),'--no-replace-objects','-C',str(root),'cat-file','--batch'],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
            env={**os.environ,'GIT_OPTIONAL_LOCKS':'0'})
    def __enter__(self):return self
    def read(self, entry):
        oid=entry['oid'];need(re.fullmatch('[0-9a-f]{40}',oid) is not None,'Invalid Git object ID')
        self.process.stdin.write(oid.encode()+b'\n');self.process.stdin.flush()
        header=self.process.stdout.readline(256).split()
        need(len(header)==3 and header[0].decode()==oid and header[1]==b'blob'
            and int(header[2])==entry['bytes'],'Git batch object identity differs')
        remaining=entry['bytes'];need(0<=remaining<=4*1024**3,'Runtime blob exceeds bounded export')
        digests={'sha256':hashlib.sha256(),'md5':hashlib.md5()};small=[] if remaining<=512 else None
        while remaining:
            block=self.process.stdout.read(min(1024*1024,remaining));need(block,'Truncated Git blob')
            remaining-=len(block)
            for digest in digests.values():digest.update(block)
            if small is not None:small.append(block)
        need(self.process.stdout.read(1)==b'\n','Git batch delimiter missing')
        return dict(bytes=entry['bytes'],**{k:v.hexdigest() for k,v in digests.items()}),b''.join(small) if small is not None else None
    def __exit__(self,kind,value,traceback):
        self.process.stdin.close()
        if kind is not None:self.process.terminate()
        try:self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:self.process.kill();self.process.wait(timeout=10)
        self.process.stdout.close()


def audit_source(root, revision, parent, base, values, compiled, *,read_blob,
                 admission_paths,admission_projection,runtime,entries=None,protected=None,
                 coverage_anchor=None,baseline_entries=None):
    rows={row['path']:row for row in parent['files']}
    entries=git_tree(root,revision) if entries is None else entries
    exported={name:entry for name,entry in entries.items() if selected(name,runtime,set(rows))}
    protected=protection_sources(rows) if protected is None else protected
    proofs={};unknown=[];added=[];removed=[]
    baseline_entries=git_tree(root,coverage_anchor) if baseline_entries is None else baseline_entries
    for name,entry in exported.items():
        if entry['mode'] not in ('100644','100755') or entry['kind']!='blob':unknown.append(name+':unsafe_git_mode')
    # Native artifacts absent from Git inherit the authenticated parent. Missing
    # executable/plaintext source cannot be waved through as compiled inheritance.
    for name in rows:
        if name not in exported and (PurePosixPath(name).suffix in TEXT_SUFFIXES
                or name in baseline_entries):removed.append(name)
    unknown.extend(name+':missing_runtime_source' for name in removed)
    compiled_sources={pin['source'] for pin in compiled.values()}
    for name in set(baseline_entries)|set(entries):
        if name.startswith('panorama/src/') and PurePosixPath(name).suffix in {'.js','.xml','.css'}:
            if baseline_entries.get(name)!=entries.get(name) and name not in compiled_sources:
                unknown.append(name+':unmapped_native_compiler_source_change')
    texts=sorted(name for name in exported if PurePosixPath(name).suffix in TEXT_SUFFIXES)
    for name in texts:
        raw=read_blob(revision,name)
        if name in values:
            need(raw==values[name],'Collected payload differs from its immutable Git blob')
            if name not in rows or sha(raw)!=rows[name]['sha256']:
                proofs[name]=dict(kind='CHANGED_IMMUTABLE_GIT_PAYLOAD',source=checks(raw))
                if name not in rows:added.append(name)
            continue
        if name not in rows:unknown.append(name+':new_runtime_source');continue
        if name in protected:
            projection=source_matches(raw,protected[name]['source_sha256'])
            if projection:proofs[name]=dict(kind='PRESERVED_PROTECTED_SOURCE',projection=projection,source=checks(raw))
            else:unknown.append(name+':protected_source_drift')
            continue
        signed_raw=(base/name).read_bytes()
        need(checks(signed_raw)=={k:rows[name][k] for k in ('bytes','md5','sha256')},'Authenticated parent file changed: '+name)
        expected=admission_projection(name,signed_raw) if name in admission_paths else signed_raw
        projection=source_matches(raw,sha(expected))
        if projection:proofs[name]=dict(kind='PRESERVED_ADMISSION_PROJECTION' if name in admission_paths else 'PRESERVED_SIGNED_TEXT',projection=projection,source=checks(raw))
        else:unknown.append(name+':unreviewed_runtime_source_drift')
    # Fail early on real source gaps; do not stream gigabytes of assets merely
    # to repeat an already decisive refusal. This is not a complete audit PASS.
    binary_names=sorted(set(exported)-set(texts))
    if not unknown:
        with GitBatch(root) as reader:
            for name in binary_names:
                if name in values:
                    raw=read_blob(revision,name);need(raw==values[name],'Git artifact changed')
                    proofs[name]=dict(kind='CHANGED_BOUND_NATIVE_ARTIFACT',source=checks(raw));continue
                pin,small=reader.read(exported[name])
                pointer=re.fullmatch(rb'version https://git-lfs.github.com/spec/v1\noid sha256:([a-f0-9]{64})\nsize ([0-9]+)\n',small or b'')
                expected=rows.get(name)
                if expected and ((pointer and pointer[1].decode()==expected['sha256'] and int(pointer[2])==expected['bytes'])
                    or all(pin[k]==expected[k] for k in ('bytes','md5','sha256'))):
                    proofs[name]=dict(kind='PRESERVED_LFS_SHA256_IDENTITY' if pointer else 'PRESERVED_SIGNED_ARTIFACT',source=pin)
                else:unknown.append(name+':unreviewed_runtime_artifact_drift')
    changed=sorted(name for name,raw in values.items() if name not in rows or sha(raw)!=rows[name]['sha256'])
    return dict(kind='AUTHENTICATED_PARENT_VS_IMMUTABLE_GIT_RUNTIME',source_revision=revision,
        authenticated_parent_content_sha256=parent['content_sha256'],complete=not unknown,
        runtime_export_count=len(exported),changed_runtime_paths=changed,added_runtime_paths=sorted(added),
        removed_runtime_paths=sorted(removed),unknown_changes=sorted(set(unknown)),
        source_identity_proofs=proofs,asset_audit_skipped_due_to_source_gap=bool(unknown and len(proofs)<len(exported)),
        baseline_git_diff_used_as_payload=False,worktree_ignored=True,
        git_coverage_anchor=coverage_anchor,coverage_anchor_is_not_a_runtime_baseline=True,
        protection_provenance_sha256=PROTECTION_SHA,catalog_provenance_sha256=CATALOG_SHA,
        source_equality_does_not_claim_native_execution=True)
