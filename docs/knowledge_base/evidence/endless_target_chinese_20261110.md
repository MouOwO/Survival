# 长青轮纹目标名称中文化（2026-11-10）

状态：已同步原游廊3824360109，版本2026111008，Steam manifest `5969054400022929926`；本轮未部署后台。

截图的 `endless training target` 来自 `building_endless_training_target` 的内部名回退：服务端 `training_room_service.spawn_target` 已设置“长青轮纹”，但 `unit_display_names.csv`、客户端固定名称表和本地化别名都缺这项；紧凑选中信息目录未收录“长青轮纹”，服务器的中文动态文字被标记未知。客户端于是去掉 `building_` 前缀、用空格替换下划线，正好产生截图中的英文。

已在权威CSV添加该单位并只重建对应 `unit_display_names.lua`，使固定目录生成器自动收录中文；HUD固定映射保证冷选中、没有快照或未知快照时仍显示“长青轮纹”。双仓四份本地化字典均补入原单位ID及 `npc_dota_unit_` 别名，不改变内部单位ID、血量、护甲、练功倍率、费用或入口规则。content原有本地化内容与game不同，已逐文件备份，仅补目标两个别名，保留既有差异。

没有新增循环、计时器、刷新或协议。现有名称字典增加一条O(1)查询，目录只在构建时登记一个中文值，单位数量变化不增加本轮运行成本。

树外证据：`D:/Survival_本地工具/runs/20261110_endless_target_name01`。`check_name.cjs` 使用真实HUD名称函数复现旧版断言失败；修改后覆盖4种冷快照/内部名情况、2个其他单位名称、8个原生本地化别名及真实静态选中目录。现有selected_static_seed 7组、compact_selected 9组通过；原生实机显示尚待新版本观察。原始源码及content独立字典备份回执已登记，未改玩家存档或后台。

首个1006候选通过2项官方编译及实际DATA名称/白名单核对，随后被旧发行本地化门禁拒绝，未调用上传SDK。原门禁固定只接纳两条历史英雄W描述的变化；本轮4份字典新增单位名使旧完整字节掩码不再一致。

现为下一候选更新固定打包模板：仅允许在原生Tokens开头插入完全一致的两条“长青轮纹”别名，缺一、重复、值错、位置错、单双仓不一致均拒绝。去掉这一个明确字节块后，仍必须匹配原有完整掩码和W描述值，其他字节变化继续拒绝。原证明schema/kind保持兼容，但实际双仓输入、完整输出和执行工具摘要继续绑定；未改写旧回执，也不将失败候选重绑定后强行继续。70项正负对照覆盖6份旧字典、4份新增别名及元数据篡改。新增处理仅在构建时对每份最大256KiB文本做O(L)检查，不进入游戏刷新。

1007的官方DATA继续通过，完整审查另发现 `unit_display_names.csv` 尚未在精确生成合同中登记，仍在上传前停止。现只补该CSV到既有真实 `build_configs.build()` 单文件合同：固定生成器摘要不变、一个输入读取、无其他CSV/模板读取、生成Lua全字节一致，篡改输出仍拒绝。完整8条未映射来源的内存诊断已通过（4条原生本地化映射、4条独立构建输入，运行读取阻断0），诊断不授予发行权限；下一不可变候选仍执行正式完整审查。两个失败任务和其编译证据保持原状，均未调用上传SDK。

交付任务 `pack_2026111008_d4c0a4f5` 已完成，完整正式流程约13分46秒。8条未映射来源（4条本地化映射及4条独立构建输入）正式审查通过，运行读取阻断0；2项官方编译DATA与作者源码一致，再次验证冷选中中文和目录白名单。准备入包的4份原生本地化文件均已核对两个别名，共8项；之后7056运行资源、5包文件签名及原条目SDK上传、官方完整下载逐文件一致。

- 固定运行来源：game `af91ef72310a8f1f61626f18f0b4de8caeb6b768` / content `825d9a20d11066effe32b7abc949958e2cb111c8`，operator `af91ef72310a8f1f61626f18f0b4de8caeb6b768`。双仓作者初始提交为game `d22d0e0ad54be6d2a0eee244ec0371315fb224d8`、content `7064a533c75be59be4f156f504d2607820589324`。
- 签包报告 `output/packager/pack_2026111008_d4c0a4f5/package.json`，SHA256 `6263bbb5da6fa1968b2101574636e468b351139aa4b099c30feb33bf22ea2806`；签名manifest `5aa42bce0639694f975d98fc03b27a9f5d33a8c078204d61cc28f49877a8549e`。
- 官方回执 `output/packager/pack_2026111008_d4c0a4f5/download_evidence/20261110T094702Z_9cd123eab52b4a7e85e025e604dc7c03/verification.json`，SHA256 `6abc2709294f9bf7b59bf9956c196ab2495cf4c63149c75ff073275868d06c7b`，状态 `OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED`；Steam manifest `5969054400022929926`。
- `delivery_status_1.stdout` 确认 `workshop_synchronized=true`，pending/blocking/historical_sources/dirty_runtime/pending_resources均0。源码push和诊断检查不是此交付状态的替代。
- game/dev、content/master分别按stash→pull→pop→commit→push同步；仅暂存本轮文件。保留game原有5项非运行改动（server的pyc/current.json及3个既有未跟踪工具），content干净。原有本地化差异没有被整份覆盖。
- 原始源文件、content字典、两份发行模板原始Git源和各轮实际编译DATA均有真实回执登记；1006/1007失败记录未覆盖。新增精确中文别名门禁70项及CSV真实单次读取/完整输出比较通过；普通客户端新版本视觉仍待用户确认，本轮无后台部署或玩家交易。
