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
LOTTERY_CSV_OUTPUTS = {
    'data/csv/抽奖系统/' + name + '.csv': 'scripts/vscripts/config/generated/' + name + '.lua'
    for name in ('lottery_pity_rules', 'lottery_pool_definitions', 'lottery_pool_updates', 'lottery_quality_weights')
}
LOTTERY_CSV_OUTPUTS['data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv'] = 'scripts/vscripts/config/generated/tower_skill_definitions.lua'

def extend_lottery_csv_review(tree):
    """Add reviewed exact generator projections without changing frozen operators.

    The existing review still executes the pinned build() on immutable inputs
    and checks every output byte. Unknown paths remain blocking.
    """
    matches = [i for i, node in enumerate(tree.body) if isinstance(node, ast.Assign)
               and any(isinstance(t, ast.Name) and t.id == 'CSV_OUTPUTS' for t in node.targets)]
    if len(matches) != 1:
        raise ValueError('exact CSV review template assignment changed')
    tree.body.insert(matches[0] + 1, ast.parse('CSV_OUTPUTS.update(' + repr(LOTTERY_CSV_OUTPUTS) + ')').body[0])

def extend_native_music_scope(tree):
    """Bind the one reviewed native-music event source without widening types.

    Compilation, dependency verification and immutable author checks remain in
    the existing compiler path. Every other scope mapping retains its template.
    """
    matches = [node for node in tree.body if isinstance(node, ast.FunctionDef)
               and node.name == 'author_paths']
    if len(matches) != 1:
        raise ValueError('exact author scope template function changed')
    function = matches[0]
    if [arg.arg for arg in function.args.args] != ['resource']:
        raise ValueError('exact author scope template signature changed')
    branch = ast.parse("if resource == 'soundevents/survival_background_music.vsndevts_c':\n"
                       "    return [('content', 'soundevents/survival_background_music.vsndevts')]\n").body[0]
    offset = 1 if function.body and isinstance(function.body[0], ast.Expr) and isinstance(function.body[0].value, ast.Constant) and isinstance(function.body[0].value.value, str) else 0
    function.body.insert(offset, branch)
    particle = ast.parse("if resource == 'particles/survival/skills/void_cyclone_smooth.vpcf_c':\n"
                         "    return [('content', 'particles/survival/skills/void_cyclone_smooth.vpcf'), "
                         "('game', 'art/effects/void_smooth/source/particles/survival/skills/void_cyclone_smooth.vpcf')]\n").body[0]
    function.body.insert(offset, particle)


def extend_business_wire_binding(tree, name):
    """Add one exact generated producer to new families, never frozen source.

    Original collector, source, protection and signing checks still execute.
    The helper is itself included in immutable operator identity/readsets.
    """
    roles = {'collect_inputs.py': 'collector', 'exact_review.py': 'exact_review', 'package.py': 'package'}
    if name not in roles:
        return
    helper = 'tools/business_wire_binding.py'
    generator = 'tools/seal_business_wire_catalog.py'
    if name == 'package.py':
        matches = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == '_loaded_paths']
        if len(matches) != 1:
            raise ValueError('exact package operator identity template changed')
        returns = [node for node in ast.walk(matches[0]) if isinstance(node, ast.Return)]
        if (len(returns) != 1 or not isinstance(returns[0].value, ast.Call)
                or not isinstance(returns[0].value.func, ast.Name) or returns[0].value.func.id != 'sorted'
                or len(returns[0].value.args) != 1 or not isinstance(returns[0].value.args[0], ast.Set)):
            raise ValueError('exact package loaded operator set template changed')
        returns[0].value.args[0].elts.extend([ast.Constant(helper), ast.Constant(generator)])
    if name == 'exact_review.py':
        mains = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'main']
        if len(mains) != 1:
            raise ValueError('exact review operator binding template changed')
        loops = [node for node in ast.walk(mains[0]) if isinstance(node, ast.For)
                 and isinstance(node.target, ast.Name) and node.target.id == 'path'
                 and isinstance(node.iter, ast.Tuple)
                 and any(isinstance(value, ast.Name) and value.id == 'TOOL' for value in node.iter.elts)]
        if len(loops) != 1:
            raise ValueError('exact review tool readset template changed')
        loops[0].iter.elts.extend([ast.Constant(helper), ast.Constant(generator)])
        loaded = [node for node in ast.walk(loops[0]) if isinstance(node, ast.Assign)
                  and any(isinstance(target, ast.Name) and target.id == 'loaded' for target in node.targets)
                  and isinstance(node.value, ast.Subscript) and isinstance(node.value.value, ast.Dict)]
        if len(loaded) != 1:
            raise ValueError('exact review loaded identity map template changed')
        mapping = loaded[0].value.value
        mapping.keys.extend([ast.Constant(helper), ast.Constant(generator)])
        mapping.values.extend([expression('_business_wire_binding.EXECUTED_SOURCE_LF_SHA256'),
                               expression('_business_wire_binding.SEAL_SOURCE_LF_SHA256')])
    statements = ast.parse('import business_wire_binding as _business_wire_binding\n'
                           + '_business_wire_binding.install(globals(), ' + repr(roles[name]) + ')\n').body
    # CLI entry must run after hooks are installed; normal module imports also
    # finish with the exact same hook installation before any signing call.
    mains = [index for index, node in enumerate(tree.body) if isinstance(node, ast.If)
             and any(isinstance(child, ast.Name) and child.id == '__name__' for child in ast.walk(node.test))]
    if len(mains) > 1:
        raise ValueError('ambiguous release module entry template')
    offset = mains[0] if mains else len(tree.body)
    tree.body[offset:offset] = statements

def expression(source):
    return ast.parse(source, mode='eval').body


def extend_public_admission(tree, name):
    """New families bind one exact policy extension; frozen families stay intact."""
    if name == 'package.py':
        functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
        adapter = functions['admission_adapter']
        saved = [node for node in adapter.body if isinstance(node, ast.Assign)
                 and any(isinstance(t, ast.Name) and t.id == 'saved' for t in node.targets)]
        if len(saved) != 1 or not isinstance(saved[0].value, ast.DictComp):
            raise ValueError('exact admission save/restore template changed')
        names = saved[0].value.generators[0].iter
        if not isinstance(names, ast.Tuple):
            raise ValueError('exact admission saved fields tuple changed')
        names.elts.append(ast.Constant('configured_ids'))
        inserted = False
        for block in adapter.body:
            if isinstance(block, ast.Try):
                for index, node in enumerate(block.body):
                    if (isinstance(node, ast.Assign) and len(node.targets) == 1
                            and isinstance(node.targets[0], ast.Attribute)
                            and node.targets[0].attr == 'steamids'):
                        block.body.insert(index + 1, ast.parse('h.configured_ids = lambda candidate: _public_launch_projection.configured_ids(api, candidate, approved)').body[0])
                        inserted = True
                        break
        if not inserted:
            raise ValueError('exact admission adapter assignment changed')
        index = next(i for i, node in enumerate(tree.body) if isinstance(node, ast.Assign)
                     and any(isinstance(t, ast.Name) and t.id == 'TOOL' for t in node.targets))
        tree.body.insert(index, ast.parse('import public_release_projection as _public_launch_projection').body[0])
        reports = [node for node in ast.walk(functions['sign_package'])
                   if isinstance(node, ast.Dict) and any(isinstance(v, ast.Constant)
                   and v.value == 'SIGNED_COMPLETE_DYNAMIC_CANDIDATE_REQUIRES_NATIVE_AND_PUBLICATION_ADMISSION' for v in node.values)]
        if len(reports) != 1:
            raise ValueError('exact signed report public-mode anchor changed')
        reports[0].keys.extend([ast.Constant('public_admission_enabled'), ast.Constant('fallback_account_count')])
        reports[0].values.extend([expression('_public_launch_projection.requested(selected_sources)'), ast.Constant(5)])
        return
    if name != 'production.py':
        return
    helper = 'tools/public_release_projection.py'
    probe = 'tools/public_launch/production_policy_probe.lua'
    assignments = {node.targets[0].id: node for node in tree.body
                   if isinstance(node, ast.Assign) and len(node.targets) == 1
                   and isinstance(node.targets[0], ast.Name)}
    tools = assignments['TOOL_INPUTS']
    if not isinstance(tools.value, ast.Tuple):
        raise ValueError('production tool tuple template changed')
    tools.value.elts.extend([ast.Constant(helper), ast.Constant(probe)])
    position = tree.body.index(assignments['OVERRIDES'])
    tree.body.insert(position, ast.parse('import public_release_projection as _public_launch_projection').body[0])
    loaded = assignments['LOADED_OPERATOR_LF_HASHES'].value
    if not isinstance(loaded, ast.Dict):
        raise ValueError('production loaded identity template changed')
    loaded.keys.append(ast.Constant(helper))
    loaded.values.append(expression('_public_launch_projection.EXECUTED_SOURCE_LF_SHA256'))
    functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
    changed = set()
    for node in ast.walk(functions['transform_overrides']):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id == 'need' and len(node.args) == 2 and isinstance(node.args[1], ast.Constant):
            reason = node.args[1].value
            if reason == 'admission_logic_changed_outside_reviewed_preview_removal':
                node.args[0] = expression('original == text or _public_launch_projection.validate_admission(source, parent)')
                changed.add('policy')
            elif reason == 'approved_account_roster_changed':
                node.args[0] = expression('lf(source[ACCESS]) == lf(parent[ACCESS]) or _public_launch_projection.validate_roster(source[ACCESS], parent[ACCESS])')
                changed.add('roster')
        if (isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                and node.func.value.id == 'reviews' and node.func.attr == 'append'
                and len(node.args) == 1 and isinstance(node.args[0], ast.Call)
                and any(key.arg == 'removed_dependency' for key in node.args[0].keywords)):
            node.args[0] = expression('_public_launch_projection.review(source, parent)')
            changed.add('review')
    probes = functions['run_probes']
    for node in ast.walk(probes):
        if isinstance(node, ast.Constant) and node.value == 'tools/admission_five_20261101/test_projected_policy.lua':
            # Replace through its containing call argument, without touching the
            # original constant-policy/client-entry probes below it.
            for call in ast.walk(probes):
                if isinstance(call, ast.Call):
                    for index, argument in enumerate(call.args):
                        if argument is node:
                            call.args[index] = expression("_public_launch_projection.probe_path(ctx['source'])")
                            changed.add('probe')
        if isinstance(node, ast.Return) and isinstance(node.value, ast.Call):
            node.value.keywords.append(ast.keyword(arg='public_account_engine_io_simulation',
                                                   value=expression("_public_launch_projection.requested(ctx['source'])")))
            changed.add('proof')
    if changed != {'policy', 'roster', 'review', 'probe', 'proof'}:
        raise ValueError('exact public admission extension anchors changed: ' + repr(changed))

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
        elif name == 'rehearsal.py':
            set_assignment(tree, 'BASE_MANIFEST', repr(base['official_parent_manifest']))
        elif name == 'publication_validator.py':
            set_assignment(tree, 'ONLINE_TEST_POLICY', repr(job['authorization_relative']))
        elif name == 'exact_review.py':
            extend_lottery_csv_review(tree)
        elif name == 'scope_review.py':
            extend_native_music_scope(tree)
        elif name == 'compile_scope.py':
            for node in ast.walk(tree):
                if isinstance(node, ast.Attribute) and node.attr == 'KEEPER_PARTICLES':
                    node.attr = 'PARTICLE_AUTHORS'
        elif name == 'localization_projection.py':
            from release_packager.localization_text_review import extend
            extend(tree, project)
        extend_business_wire_binding(tree, name)
        extend_public_admission(tree, name)
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
