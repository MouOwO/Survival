# 挑战阶段30分钟时限

进入通关后的存档挑战阶段时，由服务器记录游戏时间截止点（1800秒）。所有玩家共用同一截止点，重复开始请求、选中建筑、切换挑战或玩家退出不会重置。游戏暂停时按游戏时间暂停计时。

HUD原波次位置显示“挑战剩余 30:00”，服务端每秒推送剩余时间；重新获取私有UI快照也能恢复当前倒计时。

归零后标记全部玩家结束，取消无尽、移除未完成挑战BOSS与入口建筑，调用原通关胜利结束接口。已完成奖励继续沿用原存档保存流程；到期强制结束不等待手动结束所检查的pending状态。清理和截止瞬间的击杀不会额外发奖励，截止后的无尽续波也被拒绝。全部玩家提前手动结束时取消倒计时，胜利只触发一次。

配置：archive_challenge_rules.csv 的 phase_duration_seconds=1800。

验证：test_archive_challenge_timer.lua（包括真实无尽模块截止边界）、test_archive_challenge_hub_positions.lua、test_personal_wave_projection.lua（4人私有快照逐秒刷新）、test_hud_wave_counter.cjs 均通过。HUD编译13项成功、0失败。尚未实机等待30分钟验证；重新开局加载服务。
