# Git资源投影与发布代际门禁

本目录不签名、不上传、不启动游戏。`guard.py`是新公共SDK边界调用的隔离模块；生产策略、可信验证器及其固定SHA由Root另行审阅。没有已配置的真实验证器/生产验收时，发布保持拒绝，不能用一份手写READY JSON开启。

发布包仍是经过完整验证的五卷VPK目录。Git增量负责选择、合并与保全资源，Steam SDK是否去重上传字节由平台决定；这不是Lua热更新，也不承诺只上传几个文件。

## 实际资源基线优先于提交标签

正式0104是签名3102资源加六项准入投影，并非其`source_revision`所指Git提交的完整导出。该提交可能已经包含未发布的14项修复；单独`git diff(0104.source_revision,target)`会漏发它们。因此：

1. 可信validator核真实正式记录、签名manifest、完整VPK及官方回执，bootstrap固定原始canonical journal SHA与逐资源来源映射。来源未知的原行如实记`frozen_signed_resource`并绑定实际row SHA，不能伪造一个Git commit当已发布来源。
2. 两仓指定完整40位目标提交；父/功能祖先检查只证明Git继承，不证明整个祖先树曾发布。
3. `derive_payload_plan()`对**所有已审运行资源绑定**读取目标提交中的源/编译blob，与认证父manifest逐行SHA比较。Git diff另负责覆盖审计：未知新增、修改、删除均拒绝。只比较17个候选绑定不能自动证明完整资源闭包；目前已发现的其他历史源码差异必须由validator逐项分类/审阅，不能静默忽略。
4. 未变父row（含未知扩展字段、保护资源和准入）逐字保留，删除需要显式资源名批准。编译源与产物分别验证Git blob SHA，LF/CRLF及官方编译绑定继续由现有编译检查器执行。新行、变更行交原manifest构造器计算正式content身份，投影的普通JSON摘要不是Ed25519签名。

`non_runtime_paths`只接受逐路径分类，不隐式吞掉整个tools/docs目录。调用者须提供完整规则集及精确`parent_origins`映射；这个纯规划函数不授予发布权限。旧14已在Git祖先、但实际父row仍旧的反例已有领域测试，Git diff为空时仍能得到真实待发布资源。

## 公共API与策略

公共SDK应通过同一singleton导入`release_lineage_20261101.guard`，不要fresh私有导入另一份ContextVar。

```python
authority = guard.load_authority(AUTHORITY_FILE, COMMON_SDK_PINNED_AUTHORITY_SHA)
with guard.release_lease(authority, request) as lease:
    # Existing full production validator remains authoritative.
    receipt = existing_reviewed_publication()
    lease.mark_submitted(receipt)
```

策略schema=1，固定绝对路径`canonical_journal`、`lineage_state`、`publication_lock`、`validator_path`，并固定`validator_sha256`、`app_id`、`workshop_id`、`owner`、`repositories:{game,content}`及可选`required_feature_ancestors`。策略文件原始SHA硬固定在公共SDK入口，不由候选JSON选择；可信validator模块字节也必须匹配。当前只支持原条目更新，CreateItem/DeleteItem即使有lease也拒绝。

`publication_lock`必须恰为真实canonical journal绝对路径加`.lock`，与先前已启动发布器使用同一OS锁。不得在lease内再进入旧SDK的`publication_lock()`。`preflight_release(authority, request)`在相同锁下完成同一验证，返回深拷贝；不写pending、不设置`_ACTIVE`，返回JSON不授予SDK权限。实际发布仍重新验证，不能复用早先preflight结果替代。

request必含`release_sequence`、`generation`、`parent_journal_sha256`、`source_revisions:{game,content}`、`signed_manifest_sha256`、`report_sha256`、`plan_sha256`。validator内部必须重新认证真实签名、保护模块、账号、完整Git资源分类、编译及原生验收；不能只返回调用方声明。

- `validate_bootstrap(request)`返回`canonical_journal_sha256/release_sequence/content_sha256/source_revisions/parent_manifest_sha256/resource_origins_sha256/source_anchor_is_full_published_tree:false`。
- `validate_release(request)`返回与上述request七项严格相等的字段，另含`owner/app_id/workshop_id/content_sha256/authenticated_parent_content_sha256/authenticated_parent_manifest_sha256/parent_resource_origins_sha256/resource_origins_sha256/package_dir`。真实包、source ledger与原生验收由这个已固定字节的validator完成。

只有bootstrap成功的lineage state可开始新发布。lease首先取得固定条目级OS锁，核整个真实parent journal SHA、代际、严格递增序号和两仓祖先，再调用可信validator一次；写PENDING intent后才开放SDK写入。未知pending不可清除或自动重放，必须独立查询与人工审阅的协调工具收口；本目录没有自动恢复或强制解锁。

## 中心SDK必须调用的门禁

```python
permit = guard.require_sdk_mutation(suffix, tuple(native_args_without_ugc),
    authority_sha256=COMMON_PIN)
result = native(*all_native_args)
permit.observe_result(result)
```

`Steam.fn`返回的真正调用闭包应在调用时检查，不仅取函数时检查；已提前保存的function在lease过期后仍会拒绝。StartItemUpdate结果绑定唯一handle，后续setter/Submit只能使用同handle，SetItemContent只能用validator认证的VPK目录。未知写入族（包括封面/metadata）在native之前拒绝；只有明确read/query/download不需要lease。native异常或未观察结果留下inflight/PENDING，false setter使lease失效，Submit开始即禁止重放。

canonical journal即使在第一次SDK调用前也禁止旧工具无lease覆盖。公共`journal()`须先设置`updated_at_utc`，然后在任何文件写前调用`before_journal_write(path,value,authority_sha256=PIN)`；其既有fsync+os.replace成功后调用`after_journal_write(path,actual_raw_sha,authority_sha256=PIN)`。非canonical诊断报告不变。owned写入必须保全全部历史及原parent身份，外部CAS变化拒绝；最终真实成功回执后才原子推进generation。异常保留原PENDING/备份，不假装上传成功。

这能防止项目中通过同一公共SDK的并发/过期工具意外覆盖；不声称防御有能力任意改Python、私钥或直接加载另一份SDK的人。旧冻结工具文件/签名包不改，但公共SDK hook变化会使旧辅助pin失效，旧发布路径应明确拒绝并迁移到新审阅流程，不能改旧pin维持旁路。

## 成本和测试

明确手动阶段运行一次：M约6917个认证父row、B个已审绑定、C条Git改动、P字节实际读取blob；索引/投影O(M+B+C+P)，空间O(M+B+C)，每个涉及blob读取一次级别。没有游戏计时器/场景查询。可信发布validator每lease调用一次，SDK入口另外执行既有完整签名/VPK检查；每个SDK写调用仅canonical/lineage控制JSON的CAS，不重新扫描文件树、8MB ledger或全包。

真实OS测试只使用自建临时锁文件与Python子进程：子进程持锁→第二进程拒绝、正常/异常退出后重新取得、已有空锁文件不误判；不调用SDK、网络、私钥或项目Git写入。其余测试覆盖旧工具/READY拒绝、提交未知保留pending、父CAS/代际/序号/祖先、失效permit、handle与目录绑定、历史保全、编译双pin、未知源码与删除，以及签名混合基线的旧14漏发反例。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 -m unittest discover -s tools/release_lineage_20261101 -p test_guard.py -v
```

## 唯一操作入口

`tools/release_pipeline.py`默认或`status`仅静态输出。`plan / prepare / build`委托公共SDK已固定authority中的`recipe_path/recipe_sha256`；`rehearsal`委托`rehearsal_path/rehearsal_sha256`。没有`--authority`、任意Python路径或READY旁路。构造输入包括game/content和operator三个不可变提交，prepare/build要求先前审阅plan的真实SHA；build还必须显式指定既有外部密钥，其自身仍不会上传。

`bootstrap / preflight / publish`仅接受recipe固定REPORT目录内的有界request文件及`--request-sha`。bootstrap必须显式运行且只能迁移真实已成功发布的父包；没有lineage时发布不会猜测基线。preflight只读，不初始化Steam或写派生listing。`publish`额外要求`--apply`，持有同一lease后派生listing、重新核完整SDK上传事实，使用真实Steam返回回执推进代际；未知失败保留intent，不能自动重放。

authority另外固定`listing_template_path/listing_template_sha256`。listing只更新目标content身份和release序号，保留标题、介绍、五账号、可见性和封面；相对封面仅允许文件名，其精确已核bytes在发布时复制到REPORT中的派生listing旁。SDK验证仍检查签名中的账号、地图、容量、支付声明和封面身份。文件投影只处理实际改变的运行资源；Steam SDK继续上传完整已验证的多卷VPK，不能称为游戏内热更新。

入口隔离测试运行`python -B -m unittest discover -s tools -p test_release_pipeline.py -v`。它使用真实guard与合成native回执验证发布成功、错误facts、未知Submit保留pending、过期parent在SDK/派生文件前拒绝及无嵌套SDK锁；不调用真实SDK、签名、安装或项目Git。
