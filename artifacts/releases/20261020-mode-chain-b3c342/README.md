本目录保存本次模式前置链发布的不可变产物，Bundle 为 `b3c342e1de0de5d8c5b21471eb87a6af288a177e88d1875e43d9fcae24c3af93`。实际部署状态由对应 operator 日志记录；本目录记录验证时的代码和证据。

仅需 Python 标准库即可在新 clone 中离线复核，无需 `output/` 中的历史文件、数据库或远程连接：

```powershell
python artifacts/releases/20261020-mode-chain-b3c342/reproduce.py
```

复核会从固定父 Bundle 重算新 Bundle，并从保存的两个原始 Python 文件重建模式判断和抽奖兼容对，逐字节比较已验证发布包。需要取回精确增量文件时：

```powershell
python artifacts/releases/20261020-mode-chain-b3c342/reproduce.py --output output/reproduced_mode_chain
```

增量对应 `20261020-archive-caps-v1`，保留其限额、商城、抽奖目录和所有既有兼容对；修改两个 Python 文件、两个 Lua source，新增迁移 004。已经执行的 002、003 保持原始哈希。发布应使用核对现场指纹的 operator，避免泛用旧打包入口覆盖本次新增兼容对。

`inputs/` 是本次只读导出的最小复现输入，不修改其他任务的 canonical `unique_points.py`。压缩包保留验证时的完整候选与旧 Bundle；其中 SQL 仅为函数和迁移定义，没有玩家数据、密钥、账户记录或数据库 dump。校验值、时间与范围见 `release_proof.json`。
