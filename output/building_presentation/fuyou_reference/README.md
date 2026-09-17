# 福佑大乱斗 T 传送参考

- 游戏：[Bless ARAM / 福佑大乱斗](https://steamcommunity.com/sharedfiles/filedetails/?id=2841152696)。
- 画面：[《福佑大乱斗—游戏可以输，小偷必须死》74–81 秒](https://www.bilibili.com/video/BV13H9PBAEUd/?t=74)。`teleport_sequence_0.jpg`、`teleport_sequence_1.jpg` 为该片段的对照帧。
- 可见特征：蓝白交叠光环、蓝色地面光圈、传送目标的虚影和完成后的显现。建筑适配使用同类形状和配色，并按实际占地缩放。
- 资源：本机 Dota `particles/items2_fx/teleport_end*.vpcf` 系列作为结构参考；项目重新编写粒子，仅引用 Dota 自带纹理与 `materials/particle/teleport_image_glow.vmat`。未导入第三方玩法脚本。
- 证据范围：确认了公开实录中的传送画面；未验证该游戏 T 技能的原始脚本调用，未在本项目实机验收效果。
- 角度字段依据：ValveResourceFormat 的 [C_INIT_InitFloat 实现](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/ValveResourceFormat/Particles/Initializers/InitFloat.cs) 将角度输入由度转换为弧度；本机原生传送粒子的 yaw 初始值也以度给出。因此 CP2.y 传入建筑 yaw 的度值。
