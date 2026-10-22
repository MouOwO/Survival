# 流式 VPK 候选工具

`tools/stream_workshop_vpk.py` 将固定签名候选中的运行清单打成一个 `<WorkshopID>.vpk`。
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
内存中只保留受限元数据与分块，清单最多 16 MiB、签名最多 64 KiB、目录树最多 16 MiB。
输出先写随机 `.part`，全部验证后用同目录硬链接原子创建最终文件；目标已存在或并发出现均拒绝覆盖。
需要支持硬链接的本地文件系统，例如 NTFS。失败时不会发布半包。

回归命令：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 `
  -m unittest tools/test_stream_workshop_vpk.py tools/test_publish_test_release.py
```

测试只写临时小候选，使用真实临时 Ed25519 密钥、固定测试信任策略、现有独立 Node VPK reader 逐项回读。
包括 CRC/哈希/目录/偏移/截断损坏拒绝、源变化、签名/回滚/额外文件拒绝、并发目标保护及 uint32 边界。
超过 `0x7fffffff` 的测试只构造目录元数据并做空文件 seek，不创建多 GiB 文件。

**以上证明工具格式及小包回读，不证明 Dota 引擎能读取超过 2 GiB 的单个 VPK。**
无符号 32 位格式能表示大于 2 GiB 的值，与引擎或上传器是否使用有符号缓冲是不同问题。
本机官方参考 VPK 都小于 2 GiB，当前没有完成大包原生挂载、地图加载、工坊上传及下载测试。
工具始终返回 `ready_for_upload=false`、`native_over_2gib_read_test=NOT_RUN`，不能把构建成功当成上线验收。
Steamworks 的 [SetItemContent](https://partner.steamgames.com/doc/api/ISteamUGC#SetItemContent)
接受绝对内容目录，未在该接口说明通用 2 GiB 上限；这也不能证明 Dota 发布器没有自己的限制。
