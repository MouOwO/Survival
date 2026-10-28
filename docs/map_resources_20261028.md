# 2026-10-28 主地图资源更新

原游廊条目 `3824360109`，发布序号 `2026102802`，版本标记 `WS4-MAP-RESOURCES-01`。在已验证的 2801 包上只替换 `maps/template_map.vpk`，保留原生多人、登录、独立测试存档、支付、二维码及布局代码。可见性保持不公开列出，仍限制四个获准测试账号。

## 源码与编译

- content 源码：`maps/template_map.vmap`，72,574,022 字节，SHA256 `4e62350c1bf08e663f5217885f26652918c2e09296a829f29a987ba8a14dccdc`。
- 编译前的 game 地图仍对应旧源码：包 SHA256 `5f1dedad67c05440eee9b915924f10dbc12503b059809f007139d1570bf0221d`，嵌入源码 CRC `736803486`。本次没有将它冒充新版上传。
- 使用既有 `tools/map_c6/compile-main.ps1` 编译当前 Hammer 保存文件，没有传入快照、运行旧生成器或改写源码。Valve Resource Compiler 返回 `302 compiled, 0 failed, 1 skipped`，耗时约 4 分 5 秒。
- 新地图包：65,142,294 字节，MD5 `0b90294d0a36aca75e9c86231255bad5`，SHA256 `f868f295a01b78f63dbeb9fe9edfc6a7591b3889ace84f0892f595ac46f22186`。
- 307 条内部资源 CRC 全部匹配，嵌入源码 CRC 与当前原始源码均为 `3557144492`。证明 `output/map_resources_20261028/package_verification.json`，SHA256 `ddcd2dd519777e56e7fca1d5ee8849f58d8939bbe0c795aaa36e5f5636ba777f`。
- 本轮编译日志 `output/map_resources_20261028/compile.log`，SHA256 `be9a1899a5f39ada3bef977e5d53a77f0da794efa8464f7f083b6947878450c4`。

四个建造者出生点、四个出怪点、十二个存档建筑标记均完整、唯一，坐标与 HEAD 源码一致。overview、四种 valley 材质和 valley_spawn 粒子已在 2801 包内，字节相同；本轮无需重复加入。源码外部资源引用集合无新增或删除。依赖审计见 `output/map_resources_20261028/audit.json`。

## 签名与资源包

完整包包含 6,658 份资源，5 个 VPK 共 3,767,361,725 字节，仅重建第 0 卷，复用其余三卷，无资源迁卷。保留 180 个受保护模块和 16 份审阅源码；未把可编辑地图、密钥、运行日志或本机缓存放入运行包。

- 内容 SHA256：`310aad0a33116f29304d9ea7251524b4c1721bd5fb2b7952610d63cca2ac09d5`。
- VPK 索引 SHA256：`b3dbe2351798561cd8d585449a7e304822d62f0706689527285c7f41658359f8`。
- 签包报告：`output/map_resources_20261028/package.json`，SHA256 `4b701bce2b41d30ffe4bc5d3628dd44180778e52d70085b58ea7bde801c6a368`。
- 构建工具 13 项测试、下载验证器 19 项测试通过；包含真实临时签名及 VPK 往返、源码/CRC 证明拒绝检查。签名、完整资源哈希、VPK 校验及冻结 2801 基线不变检查均通过。

为给官方完整下载校验留出空间，按逐文件审计回收了旧 MP10r2 的独立单链接 `3824360109_001.vpk` 打包缓存，释放 1,068,730,788 字节。旧版完整 loose 资源与审阅源码保留，未改动 2705、2709、2801 发布链。回执：`output/map_resources_20261028/cache_reclamation.json`。

## 发布与验收状态

原条目实际上传成功；Steam 官方重新下载校验通过，manifest 字符串为 `2226754158672105621`，6658 份签名资源及 180 份保护模块均匹配。回执 `output/map_resources_20261028/download_evidence/20261028T010453Z_f4ad7619af99475c859dad247cb377d3/verification.json`，SHA256 `5babf60a6c7c06bd3867dfb45f9defae57d477ac3728bedea66394ab03f3b948`。随后从普通 Steam 的原游廊条目建立主机房间并载入正式地图，实际画面显示建造者、地图和 HUD，难度显示 N4。主机载图检查通过；本轮未执行完整玩法、全图通行或双人布局验收。证据 `output/map_resources_20261028/native_map_smoke.json`。

加入方此前反馈 Steam 反复重新下载，在本轮地图发布前仍未解决；这不是该机已安装新版的证明。加入方只读报告现已确认：58 次任务均为旧 manifest 的 0 文件更新校验，1.25TB 空间充足，无对应 I/O 错误；完整重启 Steam 后仍提示更新，缓存或账号版本视角的具体原因待当前账号新鲜查询。现有只读排查提示词在 `output/map_resources_20261028/第二台更新排查提示词.txt`。

## 两仓同步范围

本轮已按 stash → pull → pop 完成两仓同步并恢复原字节。game 提交新地图包、专用发布/下载验证工具和发布记录；content 只提交当前可编辑地图，沿用现有 LFS 属性。原 game 102 份资源、UI、缓存和服务端 bundle 改动逐字节保留，不纳入本次提交。
