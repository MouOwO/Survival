# 流式 VPK 候选工具

`tools/stream_workshop_vpk.py` 将固定签名候选中的运行清单打成 `<WorkshopID>.vpk`；
总容器超过 `0x7fffffff` 字节时，自动生成小目录 VPK 和不超过 1 GiB 的 `<WorkshopID>_000.vpk` 等标准资源卷。
它不安装、不上传、不创建工坊条目，也不修改 Valve DLL。默认只读校验，显式 `--build` 才写新文件。

先创建位于 Dota 安装及候选目录之外的输出目录，替换下列真实路径及已经确认的条目 ID：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  tools/stream_workshop_vpk.py `
  --candidate 'D:/Survival_发布候选/已经签名的候选' `
  --output-dir 'D:/Survival_工坊输出/本次新目录' `
  --workshop-id 已确认的数字ID
```

同一命令添加 `--build` 才生成包。ID 尚未获得时可以显式使用一个数字作为本地小包测试文件名，
这不会创建、占用或验证对应工坊条目，不能拿该数字直接发起更新。
工具不接受外部公钥或跳过验签参数；可信公钥、指纹及最低发布序号来自本仓库固定发布策略。

先验证 Ed25519 签名、发布序号、全部清单的 SHA256/MD5/大小、运行文件白名单、唯一地图和四账号门禁，
再按每次 1 MiB 逐文件写入。复制过程中重新计算双哈希和 CRC32；随后独立解析写出的 VPK，
复核所有 entry、CRC、签名清单双哈希及 VPK 的三个 MD5。源清单、签名或运行文件在过程中变化会拒绝。
源文件字节不变，候选的签名、清单、文档和密钥不装入 VPK。

输出采用 VPK v2 的 28 字节 Header、18 字节目录项，零 preload、inline archiveIndex `0x7fff`，
archive MD5 section 为零、other MD5 section 为 48 字节、VPK RSA signature section 为零。
此布局与本机官方 `overthrow/maps/temple_quartet.vpk`、`mines_trio.vpk` 的分段布局一致；
新工具完整计算 tree、空 archive section、whole-prefix 三个 MD5，不复制样本中的摘要字节。
VPK 容器没有 RSA 签名；运行内容的真实性由打包前固定 Ed25519 清单校验提供。

数据区 offset/length 使用无符号 uint32，数据总量必须小于 4 GiB，文件 seek 使用 Python 宽整数。
大包目录项使用外部 archiveIndex 与卷内 offset，目录 VPK 的 inline data size 为零。
每个资源必须能完整放进一个 1 GiB 卷；过大的单项直接拒绝。逐卷验证大小、连续偏移、CRC和签名清单双哈希。
内存中只保留受限元数据与分块，清单最多 16 MiB、签名最多 64 KiB、目录树最多 16 MiB。
单包先写随机 `.part`；分卷先写临时目录，全部验证后用硬链接先发布数据卷、最后发布目录 VPK。
目标已存在或并发出现均拒绝覆盖，失败仅撤回本次实际创建的链接。
需要支持硬链接的本地文件系统，例如 NTFS。失败时不会发布半包。

回归命令：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  -m unittest tools/test_stream_workshop_vpk.py tools/test_publish_test_release.py
```

测试只写临时小候选，使用真实临时 Ed25519 密钥、固定测试信任策略、现有独立 Node VPK reader 逐项回读。
包括 CRC/哈希/目录/偏移/截断损坏拒绝、源变化、签名/回滚/额外文件拒绝、并发目标保护及 uint32 边界。
超过 `0x7fffffff` 的测试只构造目录元数据并做空文件 seek，不创建多 GiB 文件。

2026-10-23 已确认当前原生工具不能可靠读取该 3,766,823,010 字节单包。
已下载包与上传 SHA256 完全一致且所有容器摘要正确，Valve `resourceinfo.exe` 仍稳定返回
`Unknown read error 87` / `FATAL ERROR: Failed to read 16 bytes`。
仅改 v1 虽能枚举目录，读取原先超过 2 GiB 位置的资源仍失败，不能用于修复。
使用一个目录和四个 1 GiB 以内数据卷后，相同前部、跨 2 GiB 和末尾资源均返回原生读取 EXIT=0。
普通构建与上传验证现在拒绝超限 inline 包；旧包仅允许经过固定签名清单和发布 SHA256验证后无损分卷：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/repair_workshop_vpk.py `
  --source '已有下载目录/3824360109.vpk' `
  --candidate 'D:/Survival_发布候选/20261022_four_accounts_v02' `
  --output-dir '安装目录之外的新空目录' --expected-sha256 已发布整包SHA256 --build
```

修复工具只从原包复制字节，不读取或替换候选的运行代码，不把后续开发门禁混入旧签名版本。
上传器和下载验证器对目录与全部数据卷核对文件集合和 SHA256；额外、缺失或变动卷均拒绝。
已发布条目改包需明确 `--apply --update-existing` 并复用原 journal ID，不会自动创建另一条目。
分卷的 Steam 分发、完整原生地图和四机联机仍需独立验收。
工具始终返回 `ready_for_upload=false`、`native_over_2gib_read_test=NOT_RUN`，不能把构建成功当成上线验收。
Steamworks 的 [SetItemContent](https://partner.steamgames.com/doc/api/ISteamUGC#SetItemContent)
接受绝对内容目录，未在该接口说明通用 2 GiB 上限；这也不能证明 Dota 发布器没有自己的限制。
