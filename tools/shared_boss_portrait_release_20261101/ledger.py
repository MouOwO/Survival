"""Explicit scoped source cursor and signed-resource origins, never full HEAD publication."""
from pathlib import Path, PurePosixPath
import copy
import hashlib
import json
import re

GAME_ANCHOR='20420efc36c2bc1007e316898d5b972956ada3bd'
CONTENT_ANCHOR='f8640121f8c196540fbb90e40416ac1d162144e3'
CONTENT_ROOT=Path('D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival')
BASELINE_PATH=Path(__file__).with_name('source_baseline_0104.json')
# Root reviews the concrete combined baseline/deferral record before pinning it.
# No missing pin, caller-supplied READY flag, or old fourteen-file report admits it.
REVIEWED_BASELINE_SHA256='3a60ddab9a93b58fa936e789f1a9d2008d39ed7eca9545487e1f40bf32219ee3'
ROOTS={'scripts','panorama','materials','models','particles','sounds','soundevents','resource','maps','data','art'}


def need(ok,message):
    if not ok:raise ValueError(message)


def canonical(value):return (json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True)+'\n').encode('ascii')
def sha(raw):return hashlib.sha256(raw).hexdigest()


def relevant(name):
    parts=PurePosixPath(name).parts
    return (name=='addoninfo.txt' or bool(parts and parts[0] in ROOTS)) and not any(
        part in {'tests','__pycache__','node_modules'} or part.startswith('.') for part in parts)


def frozen_origins(parent):
    return {row['path']:dict(kind='FROZEN_SIGNED_RESOURCE',release_sequence=2026110104,
        content_sha256=parent['content_sha256'],resource_sha256=row['sha256'],resource_bytes=row['bytes'],
        source_git_origin_claimed=False) for row in parent['files']}


def load_baseline(parent,parent_manifest_sha256):
    need(re.fullmatch('[a-f0-9]{64}',REVIEWED_BASELINE_SHA256 or '') is not None,
        'PENDING_ROOT_REVIEWED_COMBINED_SOURCE_BASELINE')
    raw=BASELINE_PATH.read_bytes();need(sha(raw)==REVIEWED_BASELINE_SHA256,'Reviewed source baseline changed')
    value=json.loads(raw)
    need(value['source_anchors']=={'game':GAME_ANCHOR,'content':CONTENT_ANCHOR}
        and value['parent_manifest_sha256']==parent_manifest_sha256
        and value['parent_content_sha256']==parent['content_sha256']
        and value['source_anchor_is_full_published_tree'] is False,'Wrong scoped source/parent baseline')
    need(value['resource_origins']==frozen_origins(parent),'Every frozen parent resource origin must remain exact')
    need(value['resource_origins_sha256']==sha(canonical(value['resource_origins'])),
        'Complete parent resource-origin digest differs')
    for entry in value['deferred_sources'].values():
        need(entry['status']=='DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK'
            and entry['safe_or_production_equivalent_claimed'] is False,
            'Historical source drift cannot be promoted to a production mapping')
    return value


def audit(b,revision,content_revision,parent,values,source_bindings):
    snapshot=load_baseline(parent,b.pack.runtime.digest(b.BASE/b.pack.handoff.MANIFEST))
    need(re.fullmatch('[a-f0-9]{40}',content_revision or '') is not None,'Explicit immutable content source revision required')
    targets={'game':revision,'content':content_revision}
    roots={'game':b.ROOT,'content':CONTENT_ROOT}
    trees={role:b.git_export.git_tree(roots[role],commit) for role,commit in targets.items()}
    allowed={'game':set(values)|{pin['source'] for pin in b.COMPILED.values()},'content':set()}
    for pin in b.COMPILED.values():
        mirror='panorama/scripts/custom_game/'+PurePosixPath(pin['source']).name
        allowed['content'].add(mirror)
        raw=b.blob_at(CONTENT_ROOT,content_revision,mirror)
        need(sha(raw)==pin['source_git_sha256'],'Content compiler source mirror differs: '+mirror)
        source_bindings[pin['source']]['content_mirror']=dict(path=mirror,source_revision=content_revision,sha256=sha(raw))
    unknown=[]
    for role,tree in trees.items():
        for name in allowed[role]:
            entry=tree.get(name)
            if not entry or entry.get('kind')!='blob' or entry.get('mode') not in ('100644','100755'):
                unknown.append(role+':'+name+':invalid_source_file_mode')
        old=snapshot['source_inventory'][role]
        for name in set(old)|{name for name in tree if relevant(name)}:
            if name not in allowed[role] and tree.get(name)!=old.get(name):unknown.append(role+':'+name)
    # Explicit deferred entries are pinned by actual Git SHA256, not merely a
    # commit label. Removal/reintroduction also changes their recorded identity.
    for key,entry in snapshot['deferred_sources'].items():
        role,name=entry['repo'],entry['path']
        if name in allowed[role]:raise ValueError('Admitted runtime input cannot be deferred: '+name)
        tree=trees[role]
        if entry['git_sha256'] is None:
            if name in tree:unknown.append(key+':reintroduced_deferred_source')
        elif name not in tree or sha(b.blob_at(roots[role],targets[role],name))!=entry['git_sha256']:
            unknown.append(key+':changed_deferred_source')
    need(not unknown,'NEW_UNREVIEWED_RUNTIME_SOURCE_DRIFT: '+','.join(sorted(set(unknown))))
    before={row['path']:row for row in parent['files']}
    changed={name:raw for name,raw in values.items() if name not in before or sha(raw)!=before[name]['sha256']}
    need(set(changed)==set(b.PAYLOADS),'All seventeen actual signed-parent changes must be included')
    origins=copy.deepcopy(snapshot['resource_origins'])
    for name,raw in changed.items():
        origin=dict(kind='IMMUTABLE_GIT_RUNTIME_BLOB',source_revision=revision,source_path=name,
            resource_sha256=sha(raw),resource_bytes=len(raw),parent_content_sha256=parent['content_sha256'])
        if name in b.COMPILED:
            pin=b.COMPILED[name]
            origin.update(kind='BOUND_OFFICIAL_COMPILER_ARTIFACT',source_path=pin['source'],
                source_git_sha256=pin['source_git_sha256'],compiler_input_sha256=pin['source_sha256'],
                compilation_binding=source_bindings[pin['source']])
        origins[name]=origin
    return dict(kind='SCOPED_GIT_PRIMARY_RELEASE_WITH_EXPLICIT_DEFERRED_HISTORY',complete=True,
        source_revisions=targets,source_anchors=dict(snapshot['source_anchors']),
        source_anchor_is_full_published_tree=False,reviewed_source_baseline_sha256=REVIEWED_BASELINE_SHA256,
        source_gap_audit_sha256=snapshot['source_gap_audit_sha256'],binary_gap_audit_sha256=snapshot['binary_gap_audit_sha256'],
        deferred_sources=copy.deepcopy(snapshot['deferred_sources']),unknown_changes=[],
        changed_runtime_paths=sorted(changed),resource_origins=origins,
        parent_resource_origins_sha256=snapshot['resource_origins_sha256'],resource_origins_sha256=sha(canonical(origins)),
        actual_parent_manifest_sha256=snapshot['parent_manifest_sha256'],
        payload_selection='ALL_SEVENTEEN_BOUND_GIT_OUTPUTS_VS_AUTHENTICATED_PARENT_SHA256',
        other_head_resources_claimed_published=False,full_head_publication_claimed=False)
