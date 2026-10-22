# 隐藏测试包的官方 SDK 上传

`tools/steam_workshop_upload.py` 使用本机 Dota 的 `steam_api64.dll`，通过当前登录的 Steam 客户端调用官方 flat API。它不读取密码、Cookie 或令牌，不修改 Valve 二进制。默认只读；只有 `--apply` 才创建或更新一个**隐藏**条目。

本轮限定 Dota AppID 570、账号 `76561198845461206`、仓库清单中的四名测试者和已签名生产候选。当前 DLL 的 SHA256 及 UGC021/User023/Utils010 接口版本固定在工具中；Steam 更新 DLL 后须重新核对 ABI，不能直接取消检查。

先检查账号和已发布条目：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  tools/steam_workshop_upload.py --inspect
```

上传前先使用同一命令做只读验证：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  tools/steam_workshop_upload.py `
  --candidate 'D:/Survival_发布候选/20261022_four_accounts_v02' `
  --vpk 'D:/Survival_工坊输出/20261022_four_accounts_v02/1.vpk' `
  --build-report output/four_accounts_20261022/stream_vpk_build.json
```

确认本次外部发布已获得授权后，同一命令加 `--apply`。本轮用户已明确授权先隐藏上传再下载测试，原生测试尚未通过的事实仍保留；这不代表公开上线验收通过。

工具再次验证固定公钥签名、发布序号、生产配置、唯一地图、四账号名单、全部源文件哈希、VPK 的全部 entry/CRC/双哈希及三个 MD5、封面哈希和大小。上传目录只允许一个 VPK，恢复日志必须放在上传目录之外。

创建前检查拥有条目列表，并持有恢复文件的 Windows 排他锁。创建请求写日志在前，成功返回的真实工坊 ID 也先落盘，再重命名本地占位包并开始更新。日志默认为 `output/four_accounts_20261022/steam_upload_state.json`，不能删除它后盲目重试。无 ID 的 pending 请求、未知提交结果均停止，需先查询工坊确认。已确认的 ID 必须仍在当前账号拥有列表中。

创建和提交可能返回“需要接受 Steam 创意工坊协议”。工具会保留真实 ID 并停止，不自动替用户同意协议。传输成功后仍须查询条目可见性、下载校验、原生地图加载及四账号联机测试。隐藏可见性本身不能代替游戏服务端名单，也不保证另外三个账号可直接订阅。

ABI 来自 Valve 官方 [Steamworks flat 头文件](https://github.com/ValveSoftware/Proton/blob/proton_11.0/lsteamclient/steamworks_sdk_165/steam_api_flat.h) 及同目录 `isteamugc.h`。UGC021 的 `SetItemTags` 包含第四个 `bAllowAdminTags` 参数，工具显式传 `false`；`SteamUGCDetails_t` 使用 9784 字节新版缓冲。所需回调分别为 Query 3401/280 字节、Create 3403/24 字节、Submit 3404/16 字节。

发布过程对应官方 [ISteamUGC](https://partner.steamgames.com/doc/api/ISteamUGC) 和 [异步调用结果接口](https://partner.steamgames.com/doc/api/ISteamUtils#GetAPICallResult)。`Custom Game` 标签及 `<ID>.vpk` 路径有本机官方发布器的静态取证记录，但自定义游戏元数据和 Dota 原生大包兼容性仍需实机验证，不能凭通用 Steam 接口成功就视为可玩。
