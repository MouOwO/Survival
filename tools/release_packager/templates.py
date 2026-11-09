"""Render version-specific operators from the verified0901 template, never edit gameplay."""
from __future__ import annotations
import ast, json
from pathlib import Path
from release_packager.core import git, canonical, digest
TEMPLATE = 'complete_delivery_release_20261109'
TEMPLATE_RELEASE = 2026110901
TEMPLATE_PARENT = 2026110804
TEMPLATE_REPORT = 'output/complete_delivery_release_20261109_v01'
PROGRAM_AUTH = '用户通过专用打包工具明确执行发布测试包'

def expression(source):
    return ast.parse(source, mode='eval').body

def set_assignment(tree, name, value):
    for node in tree.body:
        if isinstance(node, ast.Assign):
            if any((isinstance(t, ast.Name) and t.id == name for t in node.targets)):
                node.value = expression(value)
                return
            if len(node.targets) == 1 and isinstance(node.targets[0], ast.Tuple) and isinstance(node.value, ast.Tuple):
                for index, target in enumerate(node.targets[0].elts):
                    if isinstance(target, ast.Name) and target.id == name:
                        node.value.elts[index] = expression(value)
                        return
    raise ValueError('打包模板字段缺失：' + name)

class Values(ast.NodeTransformer):

    def __init__(self, version, parent):
        self.version, self.parent = (version, parent)

    def visit_Constant(self, node):
        if type(node.value) is int:
            if node.value == TEMPLATE_RELEASE:
                return ast.copy_location(ast.Constant(self.version), node)
            if node.value == TEMPLATE_PARENT:
                return ast.copy_location(ast.Constant(self.parent), node)
        if isinstance(node.value, str):
            value = node.value.replace('ORIGINAL0804', 'ORIGINAL' + str(self.parent)[-4:]).replace('original0804', 'original' + str(self.parent)[-4:]).replace('actual0804', 'actual' + str(self.parent)[-4:]).replace('immutable0804', 'immutable' + str(self.parent)[-4:]).replace('发布一个游廊包试一下', PROGRAM_AUTH)
            return ast.copy_location(ast.Constant(value), node)
        return node

class Families(ast.NodeTransformer):

    def __init__(self, family):
        self.family = family

    def visit_Compare(self, node):
        self.generic_visit(node)
        if len(node.ops) != 1 or len(node.comparators) != 1:
            return node
        value = node.comparators[0]
        if isinstance(value, ast.Tuple) and value.elts and all((isinstance(n, ast.Constant) and isinstance(n.value, str) and n.value.startswith('complete_delivery_') for n in value.elts)) and any((n.value == TEMPLATE for n in value.elts)):
            if not any((n.value == self.family for n in value.elts)):
                value.elts.append(ast.Constant(self.family))
        elif isinstance(node.left, ast.Name) and node.left.id == 'family' and isinstance(node.ops[0], ast.NotEq) and isinstance(value, ast.Constant) and (value.value == TEMPLATE):
            node.ops = [ast.NotIn()]
            node.comparators = [ast.Tuple(elts=[ast.Constant(TEMPLATE), ast.Constant(self.family)], ctx=ast.Load())]
        return node

def render(project, revision, job, current):
    project = Path(project)
    base = current['baseline']
    report = current['report']
    family = job['family']
    relative = job['report_relative']
    outputs = {}
    names = git(project, 'ls-tree', '-r', '--name-only', revision, 'tools/' + TEMPLATE).decode().splitlines()
    for old in names:
        if not old.endswith('.py'):
            continue
        name = Path(old).name
        raw = git(project, 'show', revision + ':' + old).decode('utf8').replace(TEMPLATE_REPORT, relative).replace(TEMPLATE, family)
        tree = Values(job['version'], base['parent_sequence']).visit(ast.parse(raw))
        if name in ('pipeline_recipe.py', 'build_release.py'):
            set_assignment(tree, 'REPORT', 'ROOT / ' + repr(relative))
        if name == 'pipeline_recipe.py':
            for key, value in {'SEQUENCE': repr(job['version']), 'BASE_SEQUENCE': repr(base['parent_sequence']), 'BASE_CONTENT': repr(base['parent_content_sha256']), 'BASE_REPORT': 'ROOT / ' + repr(Path(base['complete_delivery']['report_path']).relative_to(project).as_posix()), 'BASE_REPORT_SHA': repr(base['complete_delivery']['report_sha256']), 'BASELINE_RECORD': 'ROOT / ' + repr(current['cursor']['baseline']), 'BASELINE_RECORD_SHA': repr(current['cursor']['baseline_sha256'])}.items():
                set_assignment(tree, key, value)
            for node in ast.walk(tree):
                if isinstance(node, ast.keyword) and node.arg == 'reuse' and isinstance(node.value, ast.Constant) and (node.value.value == 'copy'):
                    node.value = ast.Constant('hardlink')
        elif name == 'parent_pending.py':
            values = {'BASELINE': 'ROOT / ' + repr(current['cursor']['baseline']), 'BASELINE_SHA256': repr(current['cursor']['baseline_sha256']), 'PARENT_MANIFEST': 'Path(' + repr(str(Path(report['candidate']) / '_release_manifest.json')) + ')', 'PARENT_AUTHORITY_SHA256': repr(current['cursor']['authority_sha256']), 'JOURNAL_RECORD': 'ROOT / ' + repr(relative + '/parent_journal.json'), 'JOURNAL_RECORD_SHA256': repr(current['journal_sha256'])}
            for key, value in values.items():
                set_assignment(tree, key, value)
        elif name == 'publication_validator.py':
            set_assignment(tree, 'ONLINE_TEST_POLICY', repr(job['authorization_relative']))
        ast.fix_missing_locations(tree)
        source = (ast.unparse(tree) + '\n').encode()
        compile(source, name, 'exec')
        outputs['tools/' + family + '/' + name] = source
    if len(outputs) != 20:
        raise ValueError('发行模板文件集发生变化，需先升级打包工具')
    for name in ('tools/release_pipeline.py', 'tools/release_workflow_diagnostics.py'):
        tree = Families(family).visit(ast.parse(git(project, 'show', revision + ':' + name)))
        ast.fix_missing_locations(tree)
        outputs[name] = (ast.unparse(tree) + '\n').encode()
    return outputs
