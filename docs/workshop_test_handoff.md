# 四账号工坊测试交接

`tools/publish_test_release.py` 将已经签名的运行候选交接到新的独立 addon。
它不上传，不修改 Steam 设置，不覆盖开发 addon，也不创建工坊条目。
默认只校验并显示计划；显式 `--apply` 才安装。

## 前提

1. 向用户确认四个真实、互异的 SteamID64，以及首次创建还是更新已有条目。
   更新必须使用本项目已确认的 Workshop ID，不能使用参考地图的 ID。
2. 候选 `addoninfo.txt` 的 `maps` 只能是 `template_map`，该地图 `MaxPlayers` 为 `4`。
3. 候选内 `scripts/vscripts/config/test_access.lua` 必须已经启用四账号名单，
   游戏服务端必须实际执行准入拒绝；修改名单后须重新构建、签名。
4. 按发布保护流程生成新的外部候选；交接工具只使用仓库内受信策略、固定公钥和最低发布序号。

四台物理电脑不能由 SteamID64 白名单严格识别。本方案限制四个 Steam 账号。
工坊的好友可见范围也不能单独保证只有这四人能够进入游戏。

开发配置可以保持 `enabled=false`。交接工具遇到此配置、空名单、缺失名单或少于四项都会拒绝，
不会自动加入当前登录账号，也不会提供可上传状态。
游戏服务端使用 `PlayerResource` 提供的真实账号。Steam 身份尚未就绪时暂缓准入和数据获取；
确认账号不在名单后断开连接。连接、角色、请求分发和档案异步回调均会复查，不能靠延迟踢人取得奖励。

## 准备名单并校验

在 addon 外准备 JSON，例如 `D:/Survival_测试配置/testers.json`，结构为：

```json
{"steamids": ["第一个真实SteamID64", "第二个真实SteamID64", "第三个真实SteamID64", "第四个真实SteamID64"]}
```

上例是格式说明，不能直接用于构建。候选 Lua 使用同样四个真实字符串：

```lua
return {
    enabled = true,
    allowed_steamids = { "真实SteamID64一", "真实SteamID64二", "真实SteamID64三", "真实SteamID64四" },
}
```

替换实际路径和新 addon 名，首次创建条目的只读交接检查：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  tools/publish_test_release.py `
  --candidate 'D:/Survival_发布候选/本次新候选' `
  --addon-name survival_test_20261021_v01 `
  --testers-json 'D:/Survival_测试配置/testers.json' `
  --publish-mode create
```

addon 名必须为 `survival_test_` 加小写英文字母、数字、下划线。
更新已有工坊条目时使用 `--publish-mode update --workshop-id 已确认的数字ID`。
名单 JSON、候选内名单和条目操作有任何不确定项，应保留为待填，不要构造假数据执行。

## 安装与审核

校验通过后，对同一命令添加 `--apply`，工具才创建：

- `game/dota_addons/<新addon名>`：仅清单中的运行文件；复制时逐项校验，落盘后再次全量校验。
- `content/dota_addons/<新addon名>`：空的对应目录，避免 Tools 重编译开发源覆盖保护后的 Lua。
- 开发项目的 `output/release_test_handoff/<新addon名>`：清单、签名和交接记录，放在上传目录外。

任何已存在的目标目录都会导致拒绝；失败不删除已有文件。
复制中断留下的点号开头 staging 目录不能用于上传，应先检查故障再单独整理。

候选原有的 `_release_manifest.json`、`_release_signature.json`、构建报告、
明文 CSV、源图、文档和密钥均不会进入新的 game addon。
最终运行文件的哈希应与签名清单一致；手工改动后必须重新构建和交接，不能沿用旧签名。
门禁模块与入口接线共七个文件由当前已审阅源码校验，不能仅放入一份未被执行的名单配置。
若这些模块后续纳入 Lua 混淆，需要把交接检查改为绑定保护报告中的对应输出哈希。

## 在官方工具中测试、上传

本机已找到 `game/bin/win64/tools/workshopmanager.dll`，Steam 与 Dota 进程也存在。
没有读取 Steam 凭据，未发现本项目已确认的发布 ID，也未发现 SteamCMD。

启动官方 Workshop Tools 后，需实际检查新 addon 是否可选、Workshop Manager 是否关联正确目录。
当前对空 content 目录的 GUI 识别尚未完成实机验证；如工具不识别，应停止并检查元数据，
不要改为选择开发用 `survival`，也不要把整个候选或开发目录直接上传。

本轮遵循用户明确要求的顺序：先完成签名、全文件校验和四账号门禁，再受限上传，随后由测试账号下载做原生测试。
这不等于公开上线验收通过；缺少真实名单或正确条目操作时仍不上传。上传时明确选择四账号测试条目的可见范围及正确条目 ID；
本工具没有验证账号发布权限、商业授权、内容审核结果或下载后的运行状态。
成功安装只输出 `INSTALLED_FOR_NATIVE_TEST_ONLY`，始终保持 `ready_for_upload=false`。

服务端账号白名单、原生运行测试、上传后由测试账号下载的联机测试必须分别验证。
具体官方发布入口参见 [Dota 2 自定义地图发布](https://www.dota2.com.cn/wiki/Dota_2_Workshop_Tools/Addon_Overview/Publishing_Addons.htm)。
