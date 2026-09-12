# 仙境宝箱抽奖 UI

按用户三张参考图接入游戏：主页面、单抽大卡片、十连两行五张卡片。文字、品质、效果、数量和按钮均为 Panorama 实时控件，背景只包含风景和宝箱。

## 文件与部署

- 布局片段：`panorama/src/layout/custom_game/lottery_window.xml`
- 主题：`panorama/src/styles/custom_game/lottery_celestial.css`（在现有 lottery.css 之后加载，保留 HUD 入口和 tooltip 样式）
- 交互：`panorama/src/scripts/custom_game/lottery_ui.js`
- 素材：`panorama/src/images/custom_game/lottery_celestial/home.png`、`results.png`，1672×941。两张均为不透明背景，无透明切图依赖。
- 部署：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy_lottery_panorama.ps1`；只替换当前 content HUD 中的 LotteryWindow 片段并追加主题引用，不覆盖其他 HUD 源码。写入前备份当前 HUD 到 `ui/lottery_celestial/backups/`。
- 检查：`node tools/test_lottery_ui.js`；部署脚本支持 `-CheckOnly`。

## 功能对应

主界面保留四个奖池、余额加号、购买抽奖券、首充礼包、开奖公告、奖池详情、抽奖记录、跳过动画、单抽、十连、礼包特权、返回、刷新和关闭。结果页提供确认、再开一次/十次、跳过和关闭。

现有单抽和十连仍通过 `ui_lottery_draw_request` 提交 request_id、pool_id、count。服务器负责扣券、保底、发奖和重复转积分；客户端不改变结果，也不添加任何支付/发券请求。
地图池视觉标题为“地图宝箱”；其他奖池名称与保底标签直接采用快照配置，包括现有“龙骑宝箱”，不把参考图中未配置的奖池名称或权益冒充实际功能。

购买、首充、礼包特权入口保留但明确显示暂未开放。当前没有免费单抽权益接口，所以单抽显示“开启1个”和实际券消耗，不标成免费。
奖池详情展示当前快照已有道具、效果、期限和重复积分，不向客户端额外投影服务端权重表。
开奖公告先展示真实奖池保底规则，活动公告内容待接入。
抽奖记录仅保留本次客户端会话收到的最近30次抽奖结果，明确说明跨局历史尚未接入。

服务器成功返回后开始展示动画：0～0.4秒福签汇入提示，0.4～1秒星轨蓄光，1～1.6秒星光显现，1.6秒展示卡背，2.2秒开始每0.14秒依次揭晓，十连4.2秒结束、单抽2.6秒结束。使用 Panorama 光环、卡背与显隐动画，是参考分镜的控件实现，并非逐帧重制原画视频。勾选跳过动画或点击跳过直接展示已经收到的全部结果，不再请求抽奖。

正在请求、切池、动画期间会锁定抽奖按钮。关闭窗口取消动画回调，但不会撤回已发送的抽奖；迟到结果保留，重新打开可以查看。重复响应不重复计入本局历史。未揭晓卡片不显示 tooltip。

## 验证与限制

已通过 Node 模拟 Panorama 测试：单抽/十连、连点保护、重复响应、再抽次数、错误/余额不足、延迟快照、跳过/关闭动画、真实效果显示及所有 XML 回调。
资源由 Dota resourcecompiler 编译通过。本轮未进行游戏内点击与视觉验收，需重载测试地图检查不同画面比例、特长物品说明、音画效果和实际图标。
字体使用 Source Han Serif SC / Noto Serif CJK SC / SimSun 回退栈；没有宣称思源字体已在引擎内生效。

## 2026-09-07 十连崩溃排查

本机 `game/bin/win64/dota2_2026_0907_194229_0_breakpoint.mdmp` 对应 survival / template_map，含本次十连日志。读取转储异常流得到 `0x80000003`，异常地址位于 `v8_libbase.dll + 0x570a0`；转储还包含 `API fatal error handler returned after process out of memory` 字符串。此证据表明有 V8 原生致命错误，但尚不能确定具体分配失败原因，也不能仅凭字符串判断物理内存不足。没有完整符号栈和游戏内复现，不能把某一脚本调用认定为已证实的根因。

结果回调中新增的 `Date.toLocaleTimeString()` 位于原有 `result_count` 日志之前，该日志没有出现在用户提供的崩溃片段中。本轮针对这一可疑的原生 locale/Intl 依赖，替换为 `getHours/getMinutes/getSeconds` 与数字拼接；保留本局历史时间、所有奖励与动画。新增 `result_received`、`cards_ready`、`reveal_ready` 阶段日志，便于复测定位。重复背包绑定日志暂未证明是根因，未据此修改背包与服务端发奖。

Node 回归使用禁用 locale 格式化、无 Intl 的运行环境，验证十连完整显示与历史 `09:04:02`，并覆盖单抽、跳过、关闭、重复响应、再抽和资源不足。模拟测试不能替代 Dota 原生复测；应重启测试地图后检查单抽、十连、连续再开十次，以及跳过动画的十连。如仍崩溃，结合新增阶段日志与新的 mdmp 继续分析。

## 素材生成

通过内置 image_gen 编辑本次用户参考图，未使用 API/CLI。采用的最终提示词如下。

主背景：Edit reference image 1 (the full landscape lottery home UI, NOT the storyboard or single reward image). Create its production background artwork ONLY. Preserve original 16:9 composition and illustrated atmosphere as closely as possible: blue teal misty floating Chinese fantasy palaces, waterfalls, giant ornate ivory and champagne gold open treasure chest on the RIGHT, glowing astrolabe gold rings, flying scrolls, white flowers. Dark quiet left half for live hero title, pale sky right. REMOVE ALL text, labels, tabs, UI buttons, badges, counters, icons, checkbox, top and bottom UI bars. No words or lettering anywhere. Keep thin delicate gold outer decorative corner ornament if possible. Entire image opaque, no checkerboard, no transparent cutouts. 1920x1080 landscape. This is a full scene background behind actual interactive Panorama controls; the chest and world are painted, all UI will be code.

结果背景：Use user's SINGLE REWARD reference (获得奖励 with central card, floating castles, left teal hanging tapestry and foreground books) to produce ONLY its empty 16:9 environment background, 1920x1080. Preserve the composition, pale pearl blue floating palace cliffs/waterfalls, soft sunlit atmosphere, left teal tapestry with subtle gold celestial pattern, parchment and armillary sphere at bottom left, dark teal cloth and crystal books bottom right, reflective stone circular platform. REMOVE the central card and all rings around the card to leave an unobtrusive open central stage for real single/ten reward panels. REMOVE all text, letters, labels, buttons and interface controls. Keep central 70% subdued and lower contrast behind cards; scenic details concentrate on the outer edges. Match original highly detailed ivory gold teal Chinese fantasy RPG style, no redesign. Opaque background, NO checkerboard, no text anywhere.
