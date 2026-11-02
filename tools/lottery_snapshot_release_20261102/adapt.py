"""Private, hash-pinned reuse of frozen0202 operations; never edits a parent.

Imports only read bounded tool bytes. Function adaptation uses those exact
captured bytes and requires every explicit replacement to occur exactly once.
"""
from pathlib import Path
from types import ModuleType
import ast
import hashlib
import importlib.util

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
PARENT=ROOT/'tools/lottery_hotfix_release_20261102'


def need(ok,message):
    if not ok:raise ValueError(message)


def local(name):
    path=HERE/(name+'.py')
    spec=importlib.util.spec_from_file_location('snapshot0203_'+name,path)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result)
    return result


def frozen(name,expected):
    path=PARENT/(name+'.py');raw=path.read_bytes()
    need(len(raw)<=128*1024 and hashlib.sha256(raw).hexdigest()==expected,
         'Frozen0202 dependency changed: '+name)
    result=ModuleType('snapshot0203_private0202_'+name);result.__file__=str(path)
    exec(compile(raw,str(path),'exec'),result.__dict__)
    result._frozen_source=raw.decode('utf-8-sig')
    return result


def function(module,name,replacements):
    source=module._frozen_source;lines=source.splitlines(True)
    node=next(n for n in ast.parse(source).body if isinstance(n,ast.FunctionDef) and n.name==name)
    text=''.join(lines[node.lineno-1:node.end_lineno])
    for old,new in replacements:
        need(text.count(old)==1,'Frozen function adaptation differs: '+name+':'+old)
        text=text.replace(old,new,1)
    exec(compile(text,module.__file__+'[private0203_'+name+']','exec'),module.__dict__)
    return getattr(module,name)
