"""One-off literal Lua dependency/subscription inventory; not runtime profiling."""
from pathlib import Path
import argparse,bisect,collections,hashlib,json,re

ROOT=Path(__file__).resolve().parents[2]
REQUIRE=re.compile(r'''\brequire\s*(?:\(\s*)?["']([^"']+)["']''')
SUBSCRIBE=re.compile(r'''\b\w+\.subscribe\s*\(\s*(?:events\.([A-Z_0-9]+)|["']([^"']+)["'])''')


def components(graph):
    sequence=0;indices={};low={};stack=[];active=set();result=[]
    def visit(node):
        nonlocal sequence
        indices[node]=low[node]=sequence;sequence+=1;stack.append(node);active.add(node)
        for target in graph[node]:
            if target not in indices:visit(target);low[node]=min(low[node],low[target])
            elif target in active:low[node]=min(low[node],indices[target])
        if low[node]==indices[node]:
            found=[]
            while True:
                target=stack.pop();active.remove(target);found.append(target)
                if target==node:break
            if len(found)>1:result.append(sorted(found))
    for node in graph:
        if node not in indices:visit(node)
    return sorted(result,key=lambda item:(-len(item),item))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();modules={};subscriptions=collections.defaultdict(list);raw_bytes=0
    for path in sorted((ROOT/'scripts/vscripts').rglob('*.lua')):
        relative=path.relative_to(ROOT/'scripts/vscripts')
        if any(part in ('tests','debug','fixtures') for part in relative.parts):continue
        raw=path.read_bytes();text=raw.decode('utf8');raw_bytes+=len(raw)
        offsets=[match.start() for match in re.finditer('\n',text)]
        module=relative.with_suffix('').as_posix()
        requires=sorted({match[1].replace('.','/') for match in REQUIRE.finditer(text)})
        modules[module]=dict(path=path.relative_to(ROOT).as_posix(),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
            lines=text.count('\n')+1,requires=requires)
        for match in SUBSCRIBE.finditer(text):
            subscriptions[match[1] or match[2]].append(dict(module=module,line=bisect.bisect_left(offsets,match.start())+1))
    graph={name:{target for target in row['requires'] if target in modules} for name,row in modules.items()}
    incoming=collections.Counter(target for targets in graph.values() for target in targets)
    tops=lambda counter:[dict(module=name,count=count) for name,count in counter.most_common(12)]
    result=dict(schema=1,scope='STATIC_LITERAL_REFERENCES_NOT_RUNTIME_DEPENDENCIES_OR_FPS',source='current_development_lua',
        counts=dict(modules=len(modules),source_bytes=raw_bytes,literal_edges=sum(map(len,graph.values())),
            literal_subscriptions=sum(map(len,subscriptions.values()))),
        top_fan_in=tops(incoming),top_fan_out=tops(collections.Counter({name:len(edges) for name,edges in graph.items()})),
        potential_lazy_dependency_components=components(graph),literal_subscriptions=dict(sorted(subscriptions.items())),modules=modules,
        limitations=['Includes lazy require references, not proof of eager module-load cycles.',
            'Literal scan is not a Lua AST; commented examples and dynamically constructed references need human review.',
            'Loop-generated subscriptions and indirect aliases are not a complete live handler count.',
            'No native FPS, timing, player-state or network evidence is collected.'])
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    print(json.dumps(dict(status='STATIC_COUPLING_INVENTORY_SAVED',**result['counts'],top_fan_in=result['top_fan_in'][:5],
        large_components=[len(group) for group in result['potential_lazy_dependency_components'][:5]],
        watched_literal_subscriptions={name:len(subscriptions[name]) for name in ('PLAYER_PROFILE_CHANGED','PERMANENT_REWARD_EFFECTS_CHANGED','HERO_PROGRESSION_CHANGED')})))


if __name__=='__main__':main()
