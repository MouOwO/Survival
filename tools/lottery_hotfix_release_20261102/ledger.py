"""Scoped four-resource hotfix; unpublished0201 inputs remain explicitly deferred.

One operator operation indexes immutable source trees O(S), parent rows O(M),
and reads bounded admitted/deferred blobs O(B). No game-loop/native work exists.
"""
from pathlib import Path
import copy
import hashlib
import importlib.util
import re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
_old=ROOT/'tools/shared_boss_portrait_release_20261101/ledger.py'
_spec=importlib.util.spec_from_file_location('lottery_frozen_0104_ledger',_old)
base=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(base)
REVIEWED_BASELINE_SHA256=base.REVIEWED_BASELINE_SHA256
BASELINE_PATH=base.BASELINE_PATH
GAME_ANCHOR=base.GAME_ANCHOR
CONTENT_ANCHOR=base.CONTENT_ANCHOR
CONTENT_ROOT=base.CONTENT_ROOT
DEFERRED0201_SOURCES={
    'game':'037a4df3d97ffcd106c7ac116849e92ff4d7fc34',
    'content':'faea2c11c1425b7c80320476e551d7ea4a9a7cff',
}
DEFERRED0201_REPORT_SHA256='a56042e7c4706e6e7b49e29fc696c16998f6956a4d0c910e4d22106a7a1a0736'
DEFERRED0201_BUILDER_SHA256='05f52c5b0fe18f8d219751b988e3d3100fb8368cf0019777f41f7693227aa859'
need,sha,canonical,relevant=base.need,base.sha,base.canonical,base.relevant


def load_baseline(parent,parent_manifest_sha256):
    return base.load_baseline(parent,parent_manifest_sha256)


def deferred0201(b):
    path=b.ROOT/'tools/portrait_resolution_release_20261102/build_release.py'
    need(sha(path.read_bytes())==DEFERRED0201_BUILDER_SHA256,'Frozen0201 builder changed')
    need(b.pack.runtime.digest(b.ROOT/'output/portrait_resolution_release_20261102/package.json')
         ==DEFERRED0201_REPORT_SHA256,'Unpublished0201 package evidence changed')
    old=b.module('lottery_deferred0201_builder',path)
    result={'game':set(old.PAYLOADS)|{p['source'] for p in old.COMPILED.values()},'content':set()}
    for pin in old.COMPILED.values():
        result['content'].add('panorama/scripts/custom_game/'+Path(pin['source']).name)
    need(len(result['game'])==20 and len(result['content'])==3,
         'Exact unpublished0201 seventeen resources plus compiler sources required')
    return result


def audit(b,revision,content_revision,parent,values,source_bindings):
    snapshot=load_baseline(parent,b.pack.runtime.digest(b.BASE/b.pack.handoff.MANIFEST))
    need(re.fullmatch('[a-f0-9]{40}',content_revision or '') is not None,
         'Explicit immutable content source revision required')
    targets={'game':revision,'content':content_revision}
    roots={'game':b.ROOT,'content':CONTENT_ROOT}
    trees={role:b.git_export.git_tree(roots[role],commit) for role,commit in targets.items()}
    allowed={'game':set(values)|{p['source'] for p in b.COMPILED.values()},'content':set()}
    for pin in b.COMPILED.values():
        mirror=pin['content_source'];allowed['content'].add(mirror)
        raw=b.blob_at(CONTENT_ROOT,content_revision,mirror)
        need(sha(raw)==pin['source_git_sha256'],'Content compiler mirror differs: '+mirror)
        source_bindings[pin['source']]['content_mirror']=dict(
            path=mirror,source_revision=content_revision,sha256=sha(raw))
    deferred=deferred0201(b)
    need(all(not allowed[r].intersection(deferred[r]) for r in roots),
         'Hotfix and unpublished0201 domains must be disjoint')
    frozen={role:b.git_export.git_tree(roots[role],commit)
            for role,commit in DEFERRED0201_SOURCES.items()}
    new_deferred={}
    unknown=[]
    for role,tree in trees.items():
        old=snapshot['source_inventory'][role]
        for name in allowed[role]:
            row=tree.get(name)
            if not row or row.get('kind')!='blob' or row.get('mode') not in ('100644','100755'):
                unknown.append(role+':'+name+':invalid_source_file_mode')
        for name in set(old)|{name for name in tree if relevant(name)}:
            if name in allowed[role]:continue
            expected=frozen[role].get(name) if name in deferred[role] else old.get(name)
            if tree.get(name)!=expected:unknown.append(role+':'+name)
        for name in sorted(deferred[role]):
            row=tree.get(name)
            need(row and row.get('kind')=='blob' and row.get('mode') in ('100644','100755'),
                 'Deferred0201 source must remain a regular immutable blob')
            raw=b.blob_at(roots[role],targets[role],name)
            pin=b.blob_at(roots[role],DEFERRED0201_SOURCES[role],name)
            if raw!=pin:unknown.append(role+':'+name+':changed_unpublished0201_source')
            new_deferred[role+':'+name]=dict(repo=role,path=name,
                status='DEFERRED_UNRELEASED_0201_OUTSIDE_THIS_HOTFIX',
                source_revision=DEFERRED0201_SOURCES[role],git_sha256=sha(pin),
                source_entry=dict(row),signed0201_report_sha256=DEFERRED0201_REPORT_SHA256,
                source_anchor_is_published=False,safe_or_production_equivalent_claimed=False)
    for key,entry in snapshot['deferred_sources'].items():
        role,name=entry['repo'],entry['path']
        need(name not in allowed[role] and name not in deferred[role],
             'Historical deferral cannot be silently promoted or replaced')
        if entry['git_sha256'] is None:
            if name in trees[role]:unknown.append(key+':reintroduced_deferred_source')
        elif name not in trees[role] or sha(b.blob_at(roots[role],targets[role],name))!=entry['git_sha256']:
            unknown.append(key+':changed_deferred_source')
    need(not unknown,'NEW_UNREVIEWED_RUNTIME_SOURCE_DRIFT: '+','.join(sorted(set(unknown))))
    before={row['path']:row for row in parent['files']}
    changed={n:r for n,r in values.items() if n not in before or sha(r)!=before[n]['sha256']}
    need(set(changed)==set(b.PAYLOADS) and set(changed)<=set(before),
         'Exactly four existing signed-parent resources must be replaced')
    origins=copy.deepcopy(snapshot['resource_origins'])
    for name,raw in changed.items():
        origin=dict(kind='IMMUTABLE_GIT_RUNTIME_BLOB',source_revision=revision,
            source_path=name,resource_sha256=sha(raw),resource_bytes=len(raw),
            parent_content_sha256=parent['content_sha256'])
        if name in b.COMPILED:
            pin=b.COMPILED[name]
            origin.update(kind='BOUND_OFFICIAL_COMPILER_ARTIFACT',source_path=pin['source'],
                source_git_sha256=pin['source_git_sha256'],compiler_input_sha256=pin['source_sha256'],
                compilation_binding=source_bindings[pin['source']])
        origins[name]=origin
    return dict(kind='FOUR_UI_RESOURCE_HOTFIX_WITH_EXPLICIT_UNPUBLISHED0201_DEFERRALS',
        complete=True,source_revisions=targets,source_anchors=dict(snapshot['source_anchors']),
        source_anchor_is_full_published_tree=False,
        reviewed_source_baseline_sha256=REVIEWED_BASELINE_SHA256,
        source_gap_audit_sha256=snapshot['source_gap_audit_sha256'],
        binary_gap_audit_sha256=snapshot['binary_gap_audit_sha256'],
        deferred_sources=copy.deepcopy(snapshot['deferred_sources']),
        deferred_unpublished0201_sources=new_deferred,
        deferred_unpublished0201_sources_sha256=sha(canonical(new_deferred)),
        unknown_changes=[],changed_runtime_paths=sorted(changed),resource_origins=origins,
        parent_resource_origins_sha256=snapshot['resource_origins_sha256'],
        resource_origins_sha256=sha(canonical(origins)),
        actual_parent_manifest_sha256=snapshot['parent_manifest_sha256'],
        payload_selection='FOUR_BOUND_GIT_OUTPUTS_VS_AUTHENTICATED0104_RESOURCE_ROWS',
        other_head_resources_claimed_published=False,full_head_publication_claimed=False,
        unpublished0201_artifacts_preserved=True)
