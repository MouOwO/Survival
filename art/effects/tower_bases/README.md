# 防御塔底座源资源

2026-10-01 收敛版位于 `source/particles/survival/towers/bases/`。生成器和 `source_manifest.json` 只列本版 29 个资源；上一级旧 15 个源和已编译资源保留，用于已验收版本与当前对局兼容。新 CSV 的资源名以 `bases/` 开头，服务端公共前缀保持 `particles/survival/towers/`。

本版 R/SR/SSR/UR 半径为 96/100/112/128；R 保持草地上的可见范围，进阶细纹放在核心图案内部。加法混合的 overbright 从 2.0 收为 1.2，职业透明度与进阶层透明度同时降低。防空改用 Valve `ping_world_crosshairs3` 圆形瞄准纹，移除飞弹方框；只有神秘塔使用 `witch_rune`。死亡、闪电、机械、多重、冰霜与防空的 SR/SSR 各有自己的内圈、方向或转速，红星 SSR/UR 保留小范围内圈流光。N 仍无底座。

普通 R/SR/SSR 分别为 1/2/2 个顶层粒子句柄，红星 SSR 和 UR 最多 3 个。计入核心 child 后，单塔最多 6 个 sprite，与旧版上限相同；没有新增持续发射器、伤害、订单、计时器或每帧服务器工作。D 仍由 CP0 跟随原实体，不重建同样式的底座；死亡、拆除、索引复用和换局的所有权规则保持不变。这些是源和模拟层的预算，不代表实测 FPS 提升。

生成与源验证：

```text
node tools/map_c6/build-tower-base-particles.cjs
python -c "from pathlib import Path; from tools.build_configs import build, OUT_ROOT; build(Path('data/csv/资源系统/tower_visual_profiles.csv'), OUT_ROOT/'tower_visual_profiles.lua')"
node tools/test_tower_base_sources.cjs
node tools/test_tower_visual_lifecycle.cjs
```

源预检核对本机 Valve 包中的 11 个纹理、29 个源的控制点/深度/子粒子关系、职业纹样与各阶预算；结果保存在 ignored 的 `output/tower_base_refine/source_preflight.json`。模拟测试覆盖 N 弹道、各职业分阶资源选择、D、职业切换、清理失败回收、死亡/拆除、实体索引复用与换局。

部署后运行 `node tools/map_c6/verify-visual-particles.cjs --family towers`，检查 source/content 一致、编译 DATA 和全部资源依赖。它只在完整 source/compiled 哈希及 CSV、service、manifest 哈希均匹配时保留本版实机验收；旧版截图仅留在 `previous_art_workshop`，不能当作新版通过。29 个资源现已同步 content、编译成功并通过该检查。草地实机视觉验收仍待重启 Tools 后的新局；需观察 R 可见性、SSR 内圈是否过密、移动跟随和死亡后清理，当前用户的暂停对局保留。
