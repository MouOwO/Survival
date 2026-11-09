from __future__ import annotations
import ast, copy, hashlib, importlib, json, os, subprocess, sys, uuid
import re
from pathlib import Path
from release_packager.core import baseline, source_state, read, canonical, digest, write_new, atomic, git
from release_packager.templates import render, TEMPLATE, PROGRAM_AUTH

class Backend:

    def __init__(self, job):
        self.job = job
        self.root = job.project
        self.data = job.state.setdefault('context', {})
        self.version = job.config['version']
        self.identity = job.config['id']
        self.family = 'complete_delivery_pack_' + str(self.version) + '_' + self.identity[-6:]
        self.report = self.root / 'output/packager' / self.identity
        self.scope = self.report / 'scope'
        self.external = Path('D:/Survival_本地排演/compile_scope_20261103') / self.identity
        cursor = job.config['parent_cursor']
        parent_path = self.root / cursor['baseline']
        base_raw = parent_path.read_bytes()
        if digest(base_raw) != cursor['baseline_sha256']:
            raise ValueError('任务的原始父检查点已改变')
        base = json.loads(base_raw)
        parent_report = Path(base['complete_delivery']['report_path'])
        parent_raw = parent_report.read_bytes()
        if digest(parent_raw) != base['complete_delivery']['report_sha256']:
            raise ValueError('任务的原始父包回执已改变')
        lineage = read(self.root / 'output/release_lineage_20261101/state.json')
        if lineage.get('pending') is not None:
            raise ValueError('上传结果未确认，禁止重传，请先核对发行记录')
        if lineage['head']['sequence'] not in (base['parent_sequence'], self.version):
            raise ValueError('已有更新的正式版本，请重新打包')
        self.current = {'cursor': cursor, 'baseline': base, 'report': json.loads(parent_raw), 'lineage': lineage, 'journal_sha256': job.config['parent_journal_sha256']}
        self.content = Path(job.config['source']['roots']['content'])
        self.parent_report = self.current['report']
        self.parent_inputs = read(Path(self.current['baseline']['complete_delivery']['report_path']).with_name('pipeline_inputs.json'))
        self.parent_request = read(self.parent_inputs['collection_request']['path'])
        self.authority_relative = 'publishing/workshop/packager_' + self.identity + '_authority.json'
        self.authorization_relative = 'publishing/workshop/packager_' + self.identity + '_authorization.json'
        self.parent_authority = self.find_parent_authority()
        sys.path.insert(0, str(self.root / 'tools'))

    def find_parent_authority(self):
        wanted = self.current['cursor']['authority_sha256']
        for p in (self.root / 'publishing/workshop').glob('*.json'):
            if p.stat().st_size < 65536 and digest(p.read_bytes()) == wanted:
                return p
        raise ValueError('找不到已发布版本对应的原始发行策略')

    def keep(self, name, value):
        self.data[name] = value
        self.job.save()
        return value

    def pin(self, p):
        return {'path': str(p), 'sha256': digest(Path(p).read_bytes())}

    def fixed(self, p, value):
        p = Path(p)
        raw = canonical(value)
        if p.exists():
            if p.read_bytes() != raw:
                raise ValueError('保留已有不可变记录，请创建新任务：' + str(p))
        else:
            write_new(p, value)

    def install(self, target, raw, backup):
        target, backup = (Path(target), Path(backup))
        backup.parent.mkdir(parents=True, exist_ok=True)
        old = target.read_bytes() if target.exists() else None
        if backup.exists():
            if old not in (backup.read_bytes(), raw):
                raise ValueError('文件出现外部修改，未覆盖：' + str(target))
        elif old is not None:
            backup.write_bytes(old)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)

    def command(self, label, name, *args):
        return self.job.call(label, 'tools/' + self.family + '/' + name, *args)

    def ledger(self, label, p):
        self.job.call(label, 'tools/release_storage_ledger.py', 'record', '--receipt', p)

    def require_idle(self):
        q = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq dota2.exe', '/FO', 'CSV', '/NH'], capture_output=True, check=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if b'"dota2.exe"' in q.stdout.lower():
            raise ValueError('请先正常退出Dota和Tools，再继续打包；不会自动结束游戏进程')
        store = Path('D:/Survival_本地排演/complete_delivery_20261103')
        if store.exists():
            folders = [p for p in store.iterdir() if p.is_dir()]
            if len(folders) > 1024:
                raise ValueError('测试事务过多，请先核对未收口事务')
            for p in folders:
                if any(((p / name).exists() for name in ('transaction.json', 'installed.json', 'staged.json'))) and not self.transaction_closed(p):
                    raise ValueError('本地测试尚未恢复，工作区仍冻结：' + str(p))

    @staticmethod
    def transaction_closed(folder):
        """Require a matching terminal receipt, including the recorded 0503 recovery."""
        try:
            tx = read(folder / 'transaction.json')
            receipt = folder / 'restored.json'
            saved = read(receipt if receipt.exists() else folder / 'interrupted_recovery.json')
            status = saved.get('status', '')
            terminal = (re.fullmatch(r'ORIGINAL\d{4}_COMPLETE_SET_FULLY_RESTORED', status)
                        or status in ('COMPLETE_STAGE_NO_INSTALL_SWITCH_RECOVERED',
                                      'INTERRUPTED_NATIVE_REJECTED_ORIGINAL0104_FULLY_RECOVERED'))
            same = bool(tx.get('original_files')) and tx['original_files'] == saved.get('original_files')
            same = same and bool(tx.get('original_content_sha256')) and tx['original_content_sha256'] == saved.get('original_content_sha256')
            for key in ('package_report_sha256', 'content_sha256', 'signed_manifest_sha256'):
                if key in saved:
                    same = same and bool(tx.get(key)) and tx[key] == saved[key]
            return bool(terminal and same and saved.get('backups_preserved') is True)
        except (OSError, ValueError, TypeError, KeyError):
            return False

    def sync(self, label, paths_game=(), paths_content=()):
        records = {}
        for role, repo, paths in [('game', self.root, list(paths_game)), ('content', self.content, list(paths_content))]:
            if git(repo, 'diff', '--cached', '--name-only').strip():
                raise ValueError('暂存区已有其他修改，请先处理：' + role)
            record = {'before': git(repo, 'rev-parse', 'HEAD').decode().strip(), 'paths': paths, 'historical_stashes': git(repo, 'stash', 'list').decode()}
            changed = bool(paths and git(repo, 'status', '--porcelain', '--', *paths).strip())
            if changed:
                git(repo, 'stash', 'push', '--include-untracked', '-m', 'packager-' + self.identity + '-' + label + '-' + role, '--', *paths)
                record['stash'] = git(repo, 'rev-parse', 'refs/stash').decode().strip()
                atomic(self.job.folder / (label + '_' + role + '_git_receipt.json'), record)
            try:
                git(repo, 'pull')
            except Exception:
                if changed and git(repo, 'rev-parse', 'HEAD').decode().strip() == record['before']:
                    refs = [line.split()[0] for line in git(repo, 'stash', 'list', '--format=%gd %H').decode().splitlines() if line.split()[1] == record['stash']]
                    if len(refs) == 1:
                        git(repo, 'stash', 'pop', refs[0])
                        record['restored_after_pull_failure'] = True
                        atomic(self.job.folder / (label + '_' + role + '_git_receipt.json'), record)
                raise
            if changed:
                refs = [line.split()[0] for line in git(repo, 'stash', 'list', '--format=%gd %H').decode().splitlines() if line.split()[1] == record['stash']]
                if len(refs) != 1:
                    raise ValueError('无法定位本次stash，保留所有历史记录')
                git(repo, 'stash', 'pop', refs[0])
                record['pop_completed'] = True
                git(repo, 'add', '--', *paths)
                git(repo, 'diff', '--cached', '--check')
                staged = set(git(repo, '-c', 'core.quotepath=false', 'diff', '--cached', '--name-only').decode().splitlines())
                if not staged <= set(paths):
                    raise ValueError('暂存区混入非本次文件')
                if staged:
                    git(repo, 'commit', '-m', 'build(packager): ' + label + ' ' + str(self.version))
            record['head'] = git(repo, 'rev-parse', 'HEAD').decode().strip()
            self.job.state.setdefault('expected_heads', {})[role] = record['head']
            self.job.save()
            atomic(self.job.folder / (label + '_' + role + '_git_receipt.json'), record)
            git(repo, 'push')
            if record['head'] != git(repo, 'rev-parse', '@{u}').decode().strip():
                raise ValueError('远端分支核对失败：' + role)
            records[role] = record
            atomic(self.job.folder / (label + '_' + role + '_git_receipt.json'), record)
        self.job.state['expected_heads'] = {r: v['head'] for r, v in records.items()}
        self.job.save()
        return {**self.job.state['expected_heads'], 'operator': records['game']['head']}

    def environment(self):
        self.require_idle()
        if read(self.root / 'output/release_baselines/complete_active.json') != self.job.config['parent_cursor']:
            raise ValueError('已发布基线发生变化，请创建新任务')
        current = source_state(self.root, self.current['baseline'])
        if current['dirty_runtime']:
            raise ValueError('存在未提交的运行文件：' + ', '.join(current['dirty_runtime'][:20]))
        if not Path('D:/Survival_密钥/20261021_release_01/signing-key.pem').is_file():
            raise ValueError('找不到签名密钥，请检查本机签名环境')
        return {'runtime_changes': len(current['pending_sources'])}

    def existing(self):
        current = source_state(self.root, self.current['baseline'])
        if current['dirty_runtime'] or current['runtime_fingerprint'] != self.job.config['source']['runtime_fingerprint']:
            raise ValueError('运行源码已改变，请重新打包')
        import release_pipeline as pipeline
        auth = pipeline.authority()
        if auth.digest != self.current['cursor']['authority_sha256']:
            raise ValueError('当前策略不对应已发布版本，请继续未完成任务')
        builder = pipeline.recipe(auth)
        d = builder.dependencies()
        report = self.current['report']
        view = Path(report['candidate'])
        vpk = Path(report['output'])
        manifest, document, metadata = d.package.inc.metadata(view)
        policy, public = d.package.pack.handoff.trusted_policy(d.package.pack.handoff.POLICY)
        signed = d.package.pack.verify_signed_snapshot(manifest, document, public, policy['integrity']['minimum_release_sequence'], policy['integrity']['trusted_key_id'])
        if signed['release_sequence'] != self.current['baseline']['parent_sequence'] or digest(metadata[d.build.MANIFEST]) != self.current['baseline']['parent_manifest_sha256'] or manifest != report['full_manifest']:
            raise ValueError('当前包不匹配已完成官方下载验证的签名检查点')
        receipt = read(self.current['baseline']['complete_delivery']['receipt_path'])
        if digest(Path(self.current['baseline']['complete_delivery']['receipt_path']).read_bytes()) != self.current['baseline']['complete_delivery']['receipt_sha256'] or receipt['steam_manifest'] != self.current['baseline']['official_parent_manifest']:
            raise ValueError('官方下载回执已改变')
        d.package._full_tree(view, manifest, (d.build.MANIFEST, d.build.SIGNATURE))
        d.package.pack.verify_vpk(vpk, manifest)
        if d.package.pack.package_inventory(vpk) != report['package_files'] or d.package.inc.all_files(vpk.parent) != {row['name'] for row in report['package_files']}:
            raise ValueError('当前签包文件集合或字节已改变')
        d.package.pack.inventory_unchanged(view, metadata)
        return {'status': 'CURRENT_PACKAGE_REUSED', 'version': report['release_sequence'], 'package_directory': str(Path(report['output']).parent), 'message': '无运行改动；完整校验通过，已复用当前签名包，未重新编译或上传'}

    def bootstrap(self):
        self.require_idle()
        self.report.mkdir(parents=True, exist_ok=True)
        self.external.mkdir(parents=True, exist_ok=True)
        info = {'family': self.family, 'report_relative': self.report.relative_to(self.root).as_posix(), 'version': self.version, 'authorization_relative': self.authorization_relative}
        outputs = render(self.root, self.job.config['source']['heads']['game'], info, self.current)
        owned = []
        backup = self.job.folder / 'before_bootstrap'
        facts = []
        for name, raw in outputs.items():
            target = self.root / name
            if target.exists() and (not (backup / name).exists()) and (not name.startswith('tools/' + self.family + '/')) and git(self.root, 'status', '--porcelain', '--', name).strip():
                raise ValueError('构建入口已有未提交修改，未覆盖：' + name)
            self.install(target, raw, backup / name)
            owned.append(name)
            facts.append({'path': name, 'sha256': digest(raw)})
        attrs = self.root / '.gitattributes'
        p = backup / '.gitattributes'
        raw = p.read_bytes() if p.exists() else attrs.read_bytes()
        self.install(attrs, raw + ('\n# Packager ' + self.identity + '\ntools/' + self.family + '/*.py text eol=lf\n' + self.authority_relative + ' text eol=lf\n' + self.authorization_relative + ' text eol=lf\n').encode(), p)
        owned.append('.gitattributes')
        journal = self.root / 'output/four_accounts_20261022/steam_upload_state.json'
        snapshot = self.report / 'parent_journal.json'
        journal_raw = journal.read_bytes()
        if digest(journal_raw) != self.job.config['parent_journal_sha256']:
            raise ValueError('正式父journal已改变')
        if snapshot.exists():
            if snapshot.read_bytes() != journal_raw:
                raise ValueError('保留原始父journal快照')
        else:
            snapshot.write_bytes(journal_raw)
        self.fixed(self.report / 'baseline_package.json', {'schema': 1, 'release_sequence': self.current['baseline']['parent_sequence'], 'parent_manifest_sha256': self.current['baseline']['parent_manifest_sha256'], 'steam_manifest': self.current['baseline']['official_parent_manifest'], 'files': self.parent_report['package_files']})
        receipt = self.job.folder / 'operator_generation_receipt.json'
        self.fixed(receipt, {'kind': 'PACKAGER_OPERATOR_GENERATION_RECEIPT', 'status': 'VERSION_PARAMETERS_AND_COMPLETE_PARENT_BOUND', 'backup_directory': str(backup), 'source_root': str(self.external), 'source_revisions': self.job.config['source']['heads'], 'generated_files': facts, 'sdk_calls': 0})
        self.ledger('record_bootstrap', receipt)
        return self.keep('initial_pins', self.sync('operator_source', owned))

    def catalog(self):
        p = self.data['initial_pins']
        dest = self.report / 'catalog'
        self.job.call('catalog', 'tools/build_ui_static_catalog.py', '--source-revision', p['game'], '--content-source-revision', p['content'], '--operator-source-revision', p['operator'], '--atlas-reference-revision', '0056e2bf88106a2045b0575011196d15b7ee2383', '--output-directory', dest)
        self.require_idle()
        paths = []
        backup = self.job.folder / 'before_catalog'
        files = ['data/ui/ui_static_catalog_manifest.json', 'data/ui/ui_static_catalog_registry.json', 'panorama/src/scripts/custom_game/common/ui_static_catalog.js', 'scripts/vscripts/config/generated/ui_static_catalog_lookup.lua']
        for name in files:
            target = self.root / name
            saved = backup / name
            self.install(target, (dest / name).read_bytes(), saved)
            paths.append(name)
        for source in (dest / 'registry_history').glob('*.json'):
            target = self.root / 'data/ui/registry_history' / source.name
            if target.exists():
                if target.read_bytes() != source.read_bytes():
                    raise ValueError('目录历史摘要冲突')
            else:
                target.write_bytes(source.read_bytes())
                paths.append(target.relative_to(self.root).as_posix())
        mirror = 'panorama/scripts/custom_game/common/ui_static_catalog.js'
        target = self.content / mirror
        saved = backup / 'content' / mirror
        self.install(target, (dest / files[2]).read_bytes(), saved)
        receipt = self.job.folder / 'catalog_import_receipt.json'
        self.fixed(receipt, {'kind': 'PACKAGER_CATALOG_IMPORT_RECEIPT', 'status': 'ACTUAL_GENERATED_CATALOG_IMPORTED', 'backup_directory': str(backup), 'manifest': self.pin(dest / files[0]), 'source_root': str(self.external), 'sdk_calls': 0})
        self.ledger('record_catalog', receipt)
        return self.keep('producer_pins', self.sync('catalog_source', paths, [mirror]))

    def compile(self):
        p = self.data['producer_pins']
        full = self.scope / 'initial.json'
        scope = self.scope / 'compile_scope.json'
        plan = self.scope / 'compile_plan.json'
        proof_dir = self.scope / 'compiler_proof'
        self.command('scope_initial', 'scope_review.py', '--output', full)
        original = read(full)
        compiled_suffixes = {'.vjs_c', '.vcss_c', '.vxml_c', '.vtex_c', '.vsvg_c', '.vmdl_c', '.vpcf_c', '.vsnd_c', '.vmat_c', '.vsndevts_c', '.vpk'}
        if any((Path(row['resource']).suffix in compiled_suffixes for row in original['decisions'])):
            dynamic = self.scope / 'all_pending_scope.json'
            self.command('compile_scope', 'compile_scope.py', '--scope', full, '--scope-sha256', self.pin(full)['sha256'], '--game-source', p['game'], '--content-source', p['content'], '--operator-source', p['operator'], '--out', dynamic)
            selected = read(dynamic)
        else:
            selected = {'schema': 1, 'kind': 'PACKAGER_CATALOG_COMPILER_BINDING_SCOPE', 'observed_commits': {r: p[r] for r in ('game', 'content')}, 'original_scope': self.pin(full), 'decisions': []}
        catalog_resource = 'panorama/scripts/custom_game/common/ui_static_catalog.vjs_c'
        if not any((row['resource'] == catalog_resource for row in selected['decisions'])):
            selected['decisions'].append({'resource': catalog_resource, 'inventory_status': 'UNBOUND_COMPILED_ARTIFACT', 'review_decision': 'IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING', 'selection_reason': 'CURRENT_JOB_CATALOG_PRODUCER_BINDING'})
        self.fixed(scope, selected)
        self.job.call('compile_plan', 'tools/release_compile_scope.py', 'plan', '--scope', scope, '--scope-sha256', self.pin(scope)['sha256'], '--game-source', p['game'], '--content-source', p['content'], '--operator-source', p['operator'], '--out', plan)
        self.job.call('compile_official', 'tools/release_compile_scope.py', 'compile', '--plan', plan, '--plan-sha256', self.pin(plan)['sha256'], '--run-id', self.identity + '_c', '--proof-dir', proof_dir)
        proof = read(proof_dir / 'proof.json')
        if not proof['complete']:
            raise ValueError('官方编译未全部通过')
        self.ledger('record_compile', proof_dir / 'proof.json')
        self.keep('compiler', {'plan': str(plan), 'proof': str(proof_dir / 'proof.json'), 'pins': p})
        return {'resources': len(proof['results'])}

    def production(self):
        p = self.data['producer_pins']
        dest = self.external / 'production'
        self.command('production', 'production.py', '--source-revision', p['game'], '--content-source-revision', p['content'], '--operator-revision', p['operator'], '--output-directory', dest, '--build-protected')
        self.ledger('record_production', dest / 'production_preparation.json')
        self.keep('production', str(dest))
        return {'protected_modules': len(read(dest / 'production_preparation.json')['protection_selected'])}

    def item(self):
        p = self.data['producer_pins']
        result = self.command('item_generator', 'generator_binding.py', '--source-revision', p['game'], '--content-source-revision', p['content'], '--operator-source-revision', p['operator'], '--json-normalization', 'LF_TO_CRLF')
        self.fixed(self.scope / 'item_proof.json', result)
        return self.keep('item_proof', str(self.scope / 'item_proof.json'))

    def finalize_source(self):
        self.require_idle()
        proof = read(self.data['compiler']['proof'])
        paths = []
        backup = self.job.folder / 'before_compile_import'
        for row in proof['results']:
            name = row['resource']
            target = self.root / name
            p = backup / name
            raw = Path(row['artifact_path']).read_bytes()
            if digest(raw) != row['artifact']['sha256']:
                raise ValueError('编译资源摘要改变')
            self.install(target, raw, p)
            paths.append(name)
        receipt = self.job.folder / 'compile_import_receipt.json'
        self.fixed(receipt, {'kind': 'PACKAGER_OFFICIAL_COMPILE_IMPORT_RECEIPT', 'status': 'IMPORTED_AFTER_DOTA_EXIT', 'backup_directory': str(backup), 'proof': self.pin(self.data['compiler']['proof']), 'sdk_calls': 0})
        self.ledger('record_compile_import', receipt)
        auth = copy.deepcopy(read(self.parent_authority))
        for prefix, name in [('recipe', 'pipeline_recipe'), ('validator', 'publication_validator'), ('rehearsal', 'rehearsal'), ('download', 'verify_download'), ('native_admission', 'native_admission'), ('baseline_completion', 'complete_baseline')]:
            target = self.root / 'tools' / self.family / (name + '.py')
            auth[prefix + '_path'] = str(target)
            auth[prefix + '_sha256'] = digest(target.read_bytes())
        auth.update(release_sequence=self.version, reviewed_source_baseline_sha256=self.current['cursor']['baseline_sha256'], parent_authority_sha256=self.current['cursor']['authority_sha256'], report_directory=str(self.report), required_feature_ancestors={r: [v] for r, v in self.current['baseline']['source_anchors'].items()})
        self.fixed(self.root / self.authority_relative, auth)
        paths.append(self.authority_relative)
        hook = self.root / 'tools/release_sdk_lineage_hook.py'
        saved = backup / 'release_sdk_lineage_hook.py'
        tree = ast.parse(saved.read_bytes() if saved.exists() else hook.read_bytes())
        from release_packager.templates import set_assignment
        set_assignment(tree, 'AUTHORITY_FILE', 'ROOT / ' + repr(self.authority_relative))
        set_assignment(tree, 'AUTHORITY_SHA256', repr(digest((self.root / self.authority_relative).read_bytes())))
        ast.fix_missing_locations(tree)
        self.install(hook, (ast.unparse(tree) + '\n').encode(), saved)
        paths.append('tools/release_sdk_lineage_hook.py')
        return self.keep('final_pins', self.sync('compiled_source', paths))

    def review(self):
        p = self.data['final_pins']
        full = self.scope / 'final.json'
        prefix = self.scope / 'strict'
        self.command('scope_final', 'scope_review.py', '--output', full)
        self.command('exact_review', 'exact_review.py', '--game-revision', p['game'], '--content-revision', p['content'], '--operator-revision', p['operator'], '--scope', full, '--scope-sha256', self.pin(full)['sha256'], '--output-prefix', prefix)
        if read(str(prefix) + '_reference_scan.json')['runtime_read_blockers']:
            raise ValueError('存在未审阅的运行数据读取')
        return {'exact_inputs': len(read(str(prefix) + '_path_review.json')['reviews'])}

    def collect(self):
        p = self.data['final_pins']
        request = copy.deepcopy(self.parent_request)
        catalog = self.report / 'catalog/data/ui/ui_static_catalog_manifest.json'
        cat = read(catalog)
        compiler = self.data['compiler']
        prod = Path(self.data['production'])
        producer = self.data['producer_pins']
        request['source_revisions'] = p
        request['catalog'].update(manifest=self.pin(catalog), source_revisions=cat['source_revisions'], previous_registry_sha256=cat['source_hashes']['data/ui/ui_static_catalog_registry.json'])
        request['compiler_receipts'] = [{'plan': self.pin(compiler['plan']), 'proof': self.pin(compiler['proof']), 'source_revisions': compiler['pins']}]
        request['production'].update(receipt=self.pin(prod / 'production_preparation.json'), proof=self.pin(prod / 'protected_lua/_lua_protection_report.json'), source_revisions=producer)
        request['item_generator'].update(proof=self.pin(self.data['item_proof']), source_revisions=producer, python=sys.executable)
        request['exact_review'] = self.pin(self.scope / 'strict_path_review.json')
        request['reference_scan'] = self.pin(self.scope / 'strict_reference_scan.json')
        path = self.report / 'collect_request.json'
        self.fixed(path, request)
        artifacts = self.external / 'artifacts'
        unsigned = self.external / 'unsigned'
        collection = self.report / 'collection'
        self.command('collect', 'collect_inputs.py', '--request', path, '--request-sha256', self.pin(path)['sha256'], '--report-directory', collection, '--artifact-directory', artifacts, '--allowed-artifact-root', self.external, '--unsigned-directory', unsigned)
        config = copy.deepcopy(self.parent_inputs)
        config.update(source_revisions={r: p[r] for r in ('game', 'content')}, package_operator_revision=p['operator'], collection_request=self.pin(path), projection=self.pin(collection / 'projection.json'), unsigned_review=self.pin(collection / 'unsigned_review.json'), artifact_root=str(artifacts), unsigned_root=str(unsigned), allowed_artifact_root=str(self.external), allowed_unsigned_root=str(self.external), baseline_package=self.pin(self.report / 'baseline_package.json'), parent_root=self.parent_report['candidate'], parent_vpk=self.parent_report['output'], parent_trusted=self.parent_report['trusted_source'], native_admission_module=self.pin(self.root / 'tools' / self.family / 'native_admission.py'))
        prefix = self.identity
        config['candidate'] = {'output': str(Path('D:/Survival_工坊输出') / prefix), **{name: str(Path('D:/Survival_发布候选') / (prefix + '_' + name)) for name in ('overlay', 'trusted', 'view')}}
        self.fixed(self.report / 'pipeline_inputs.json', config)
        return {'runtime_files': read(collection / 'projection.json')['files']}

    def build(self):
        p = self.data['final_pins']
        args = ['--source-revision', p['game'], '--content-source-revision', p['content'], '--operator-revision', p['operator'], '--report', self.report]
        plan = self.job.call('plan', 'tools/release_pipeline.py', 'plan', *args)
        self.fixed(self.report / 'canonical_plan.json', plan)
        self.job.call('build', 'tools/release_pipeline.py', 'build', *args, '--reviewed-plan', self.report / 'canonical_plan.json', '--reviewed-plan-sha256', self.pin(self.report / 'canonical_plan.json')['sha256'], '--key', 'D:/Survival_密钥/20261021_release_01/signing-key.pem')
        self.ledger('record_package', self.report / 'package.json')
        report = read(self.report / 'package.json')
        self.job.state['runtime_fingerprint'] = source_state(self.root, self.current['baseline'])['runtime_fingerprint']
        self.job.save()
        return {'version': self.version, 'package_directory': str(Path(report['output']).parent)}

    def publish(self):
        self.require_idle()
        report = read(self.report / 'package.json')
        journal_path = self.root / 'output/four_accounts_20261022/steam_upload_state.json'
        journal = read(journal_path)
        lineage = read(self.root / 'output/release_lineage_20261101/state.json')
        if journal['release_sequence'] == self.version and journal.get('uploaded') and (lineage.get('pending') is None):
            if any((journal.get(key) != report.get(key) for key in ('content_sha256', 'vpk_sha256', 'package_files'))):
                raise ValueError('同版本的实际上传并非本任务签包，未继续')
            if lineage['head']['sequence'] != self.version or lineage['head']['canonical_journal_sha256'] != digest(journal_path.read_bytes()) or lineage['head'].get('manifest_sha256') != report['signed_manifest_sha256'] or (lineage['head'].get('source_revisions') != report['source_revisions']):
                raise ValueError('上传回执与发行记录不匹配')
            return {'already_uploaded': True}
        if lineage.get('pending') is not None:
            raise ValueError('上传结果未确认，禁止重传；保留原意图待核对')
        if digest(journal_path.read_bytes()) != self.job.config['parent_journal_sha256']:
            raise ValueError('正式父版本已改变，请重新打包')
        policy = {'schema': 1, 'kind': 'EXPLICIT_CURRENT_USER_UNLISTED_ONLINE_TEST_AUTHORIZATION', 'user_authorization': PROGRAM_AUTH, 'authorization_scope': 'UPLOAD_THIS_EXACT_SIGNED_PACKAGE_AND_VERIFY_OFFICIAL_DOWNLOAD', 'workshop_id': report['workshop_id'], 'visibility': 'unlisted', 'release_sequence': self.version, 'ordinary_production_acceptance': False, 'native_acceptance_status': 'PENDING_USER_ONLINE_TEST', 'source_revisions': report['source_revisions'], 'signed_manifest_sha256': report['signed_manifest_sha256'], 'content_sha256': report['content_sha256'], 'report_sha256': self.pin(self.report / 'package.json')['sha256'], 'parent_journal_sha256': digest(journal_path.read_bytes()), 'generation': lineage['generation'] + 1}
        path = self.root / self.authorization_relative
        self.fixed(path, policy)
        pins = self.sync('test_publication_authorization', [self.authorization_relative])
        request = {key: policy[key] for key in ('release_sequence', 'source_revisions', 'signed_manifest_sha256', 'content_sha256', 'report_sha256', 'parent_journal_sha256', 'generation')}
        request.update(publication_mode='EXPLICIT_UNLISTED_ONLINE_TEST_NATIVE_PENDING', publication_operator_revision=pins['game'], online_test_authorization_sha256=self.pin(path)['sha256'], plan_sha256=report['plan_sha256'])
        self.fixed(self.report / 'online_test_request.json', request)
        current = source_state(self.root, self.current['baseline'])
        if current['dirty_runtime'] or current['runtime_fingerprint'] != self.job.state.get('runtime_fingerprint'):
            raise ValueError('签包后运行源码发生改变，未上传旧绑定；请重新打包')
        self.job.call('publish', 'tools/release_pipeline.py', 'publish', '--request', self.report / 'online_test_request.json', '--request-sha', self.pin(self.report / 'online_test_request.json')['sha256'], '--apply')
        return {'uploaded': True}

    def download(self):
        result = self.job.call('official_download', 'tools/release_pipeline.py', 'download', '--apply', '--report-sha256', self.pin(self.report / 'package.json')['sha256'])
        if result.get('status') != 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED':
            raise ValueError('官方下载尚未核验完成，不会重传SDK')
        return self.keep('official_receipt', result['evidence'])

    def checkpoint(self):
        import release_pipeline as pipeline
        auth = pipeline.authority()
        builder = pipeline.recipe(auth)
        request = read(self.report / 'online_test_request.json')
        result = pipeline.pinned_module(auth, 'baseline_completion').record_verified_delivery(auth, builder, request, Path(self.data['official_receipt']))
        self.fixed(self.job.folder / 'checkpoint_receipt.json', result)
        status = self.job.call('delivery_status', 'tools/release_pipeline.py', 'delivery-status', '--download-receipt', self.data['official_receipt'], '--full', '--check')
        if not status.get('workshop_synchronized'):
            raise ValueError('完整待发清单尚未清零')
        receipt = self.job.folder / 'delivery_receipt.json'
        self.fixed(receipt, {'kind': 'PACKAGER_VERIFIED_DELIVERY_RECEIPT', 'status': 'WORKSHOP_SYNCED_NATIVE_TEST_PENDING', 'release_sequence': self.version, 'candidate': str(Path(read(self.report / 'package.json')['candidate'])), 'official_receipt': self.pin(self.data['official_receipt']), 'source_revisions': self.data['final_pins']})
        self.ledger('record_delivery', receipt)
        return {'steam_manifest': read(self.data['official_receipt'])['steam_manifest']}

def run(job):
    backend = Backend(job)
    actual = {r: git(Path(root), 'rev-parse', 'HEAD').decode().strip() for r, root in job.config['source']['roots'].items()}
    if actual != job.state.get('expected_heads'):
        raise ValueError('工作分支已发生外部变更，请新建打包任务；原产物保留')
    if job.config['no_runtime_changes']:
        backend.require_idle()
        job.stage('source_sync', '核对并同步双仓来源', lambda: backend.sync('source_refresh'))
        job.state.get('stages', {}).pop('reuse', None)
        result = job.stage('reuse', '校验并复用当前包', backend.existing)
        job.state.update(status='done', result=result)
        job.save()
        return result
    for name, title, action in [('environment', '检查环境和正式基线', backend.environment), ('bootstrap', '建立不可变构建任务', backend.bootstrap), ('catalog', '收集变更与生成目录', backend.catalog), ('compile', '官方编译变化资源', backend.compile), ('production', '生产转换与数值校验', backend.production), ('item', '验证物品生成来源', backend.item), ('source', '导入编译资源并固定来源', backend.finalize_source), ('review', '审查全部运行和构建输入', backend.review), ('collect', '准备完整运行文件', backend.collect), ('build', '签名和整包校验', backend.build)]:
        job.stage(name, title, action)
    report = read(backend.report / 'package.json')
    result = {'status': 'BUILT', 'version': backend.version, 'package_directory': str(Path(report['output']).parent), 'message': '签名包已生成并核验；没有上传'}
    if job.config['mode'] == 'publish-test' or job.state.get('publication_requested'):
        job.stage('publish', '上传原游廊测试条目', backend.publish)
        job.stage('download', '验证官方完整下载', backend.download)
        check = job.stage('checkpoint', '收口全部待发来源', backend.checkpoint)
        result.update(status='WORKSHOP_SYNCED', steam_manifest=check['steam_manifest'], message='测试包已同步游廊，实机验收待测')
    job.state.update(status='done', result=result)
    job.save()
    return result
