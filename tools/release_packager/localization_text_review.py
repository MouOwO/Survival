"""Extend new release families with this round's exact, immutable text review.

The existing historical files and receipts remain unchanged. Every token value
comes from the reviewed Git commits; Chinese skills must also equal their CSV
description. Bytes outside those named tokens retain a full-file mask binding.
"""
import ast
import csv
import hashlib
import io
import re
from pathlib import Path

from release_packager.core import git

GAME_REVIEW = '91d132f204300653730b336b63a1517047c65c40'
CONTENT_REVIEW = '4d325921af79bf3a165e52aaab571ad57bace467'
PATHS = ('resource/addon_english.txt', 'resource/addon_schinese.txt',
         'resource/localization/addon_english.txt', 'resource/localization/addon_schinese.txt')


def extend(tree, project):
    project = Path(project)
    content = project.parents[2] / 'content/dota_addons/Survival'
    # Load only the frozen pure localization functions and baseline constants.
    identity = ast.Module(body=tree.body, type_ignores=[])
    scope = {'__file__': __file__}
    exec(compile(identity, __file__ + '[frozen projection]', 'exec'), scope)
    baselines = scope['BASELINES'].copy()
    old_tokens = tuple(scope['TOKENS'])
    token_sets, approved = {}, {}
    skills = {}
    for name, hero in [('英雄系统/hero_skill_definitions.csv', True),
                       ('建筑与工人系统/防御塔/tower_skill_definitions.csv', False)]:
        raw = git(project, 'show', GAME_REVIEW + ':data/csv/' + name)
        for row in csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))):
            if row['skill_id'].startswith('#'):
                continue
            token = 'DOTA_Tooltip_ability_' + (row['ability_name'] if hero else row['skill_id']) + '_Description'
            value = row['description'].replace('全属性总和', '全属性').replace('等级', 'LV').replace(' LV', '<br>LV')
            if hero and row['skill_id'].startswith('proto_'):
                value = '全属性＝力量＋敏捷＋智力。<br>' + value
            skills[token] = value
    if len(skills) != 102:
        raise ValueError('reviewed_102_skill_inventory_changed')
    for path, previous in baselines.items():
        language = path.rsplit('_', 1)[1][:-4]
        if path not in PATHS:
            token_sets[path] = old_tokens
            approved[path] = scope['APPROVED_VALUE_SHA256'][language]
            continue
        tokens = tuple(sorted(set(old_tokens) | {'addon_game_name'} |
                              (set(skills) if language == 'schinese' else set())))
        token_sets[path] = tokens
        next_baseline, values = {}, None
        for role, repo, revision in [('game', project, GAME_REVIEW), ('content', content, CONTENT_REVIEW)]:
            raw = git(repo, 'show', revision + ':' + path)
            if b'\r' in raw or b'\x00' in raw:
                raise ValueError('reviewed_localization_requires_git_lf')
            masked = scope['_without_training_name'](raw)
            actual = {}
            for token in tokens:
                pattern = rb'(?m)^([ \t]*"' + re.escape(token.encode()) + rb'"[ \t]+")((?:\\.|[^"\\\r\n])*)("[ \t]*$)'
                matches = list(re.finditer(pattern, masked))
                if len(matches) != 1:
                    raise ValueError('reviewed_single_localization_token_required:' + token)
                value = matches[0].group(2)
                if token == 'addon_game_name' and value.decode() != '我在dota2苟发育':
                    raise ValueError('reviewed_game_name_changed')
                if language == 'schinese' and token in skills and value.decode() != skills[token]:
                    raise ValueError('reviewed_skill_description_differs_from_csv:' + token)
                actual[token] = hashlib.sha256(value).hexdigest()
                masked = re.sub(pattern, lambda match: match[1] + b'__REVIEWED_HERO_W_DESCRIPTION__' + match[3], masked)
            if values is not None and values != actual:
                raise ValueError('reviewed_dual_localization_values_differ')
            values = actual
            next_baseline[role] = {'revision': revision, 'sha256': hashlib.sha256(raw).hexdigest(),
                                   'masked_sha256': hashlib.sha256(masked).hexdigest()}
        baselines[path] = next_baseline
        approved[path] = values
    # Keep the original proof schema. Only new families receive these additional
    # exact values; arbitrary text outside the reviewed tokens still fails.
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == 'BASELINES':
                    node.value = ast.parse(repr(baselines), mode='eval').body
        if isinstance(node, ast.FunctionDef) and node.name == '_mask':
            node.args.args.append(ast.arg(arg='path'))
            node.args.defaults.append(ast.Constant(None))
            for item in ast.walk(node):
                if isinstance(item, ast.For) and isinstance(item.iter, ast.Name) and item.iter.id == 'TOKENS':
                    item.iter = ast.parse('TOKENS_BY_PATH.get(path, TOKENS)', mode='eval').body
        if isinstance(node, ast.FunctionDef) and node.name in ('verify_projection', 'validate_metadata'):
            for item in ast.walk(node):
                if isinstance(item, ast.Call) and isinstance(item.func, ast.Name) and item.func.id == '_mask':
                    item.args.append(ast.Name(id='path', ctx=ast.Load()))
                if isinstance(item, ast.Subscript) and isinstance(item.value, ast.Name) and item.value.id == 'APPROVED_VALUE_SHA256':
                    item.value.id = 'APPROVED_VALUES_BY_PATH'
                    item.slice = ast.Name(id='path', ctx=ast.Load())
    tree.body.extend(ast.parse('TOKENS_BY_PATH = ' + repr(token_sets) + '\nAPPROVED_VALUES_BY_PATH = ' + repr(approved)).body)
    ast.fix_missing_locations(tree)
