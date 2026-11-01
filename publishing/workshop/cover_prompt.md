# 孤城逐晓工坊封面

## 当前使用｜2026-11-01 用户提供的“苟发育”封面

用户指定使用原图“苟发育.png”，画面主标题为“我在刀塔2苟发育”。原图1672×941、RGB，字节完整保存为`gou_fayu_cover_master.png`；同尺寸上传版`gou_fayu_workshop.jpg`采用JPEG质量94、4:4:4、优化编码，936610字节。仅做文件格式转换，没有重新生成图像、裁切、缩放或改字。两份素材与`gou_fayu_cover_20261101.json`配套保存在game/content仓库，旧封面文件保留为历史素材。

原游廊条目3824360109已通过官方SDK仅更新primary preview，SubmitItemUpdate回调EResult=1；官方新预览URL下载回来的936610字节JPEG与上传版SHA256完全一致。主图SHA256为`7d4bbd0865782c8469b964b75a9c299b8f150d95ac59246511e3c49b65b8c351`，上传/远端JPEG为`00714bb69b9c400231f88112673b2fd881d50680a0a76ab63a1792256b679aa1`。本次没有提交候选游戏包；条目标题/说明/可见性/标签/内容大小等保护字段更新前后一致。普通游廊缩略图缓存的原生UI尚未另行采样，不能把CDN一致写成客户端每个缩略图已刷新。

`test_listing.json`仅更新cover相关七个字段，后续发布沿用新封面。历史发行JSON不回写。专用工具`tools/workshop_cover/update_preview.py`默认只读，`--inspect`查询、`--apply`仅替换封面、`--verify`重新下载核验。工具固定本次预览SHA及原条目/发布者，使用项目既有安全工具Python环境；提交前写独立恢复记录，已有请求（包括成功）禁止自动重传。完整验证与边界见知识库`evidence/workshop_cover_20261101.md`。

以下保留旧版封面的生成过程，仅用于历史追溯。

生成方式：内置 `imagegen`，2026-10-21。参考图为项目现有的 `panorama/src/images/custom_game/loading/dawnward_citadel_background.png`；没有复制《守望轮回谷》的封面、标志或角色。主图为1254×1254 PNG，上传副本为同尺寸JPEG、质量90、605055字节；JPEG仅转换编码，没有裁切、缩放或改字。

原图另存于 content 仓库的 `publishing/workshop/gucheng_zhuxiao_cover_master.png`。本目录的图片是工坊页面素材，不进入游戏运行资源白名单。

使用的完整提示词：

> Use case: ads-marketing. Asset type: original Steam Workshop square game cover, 1024 x 1024 composition. Create a finished premium Chinese fantasy cooperative tower-defense survival game cover for the game named exactly 「孤城逐晓」. The attached local image is a reference for this project's actual dawn-lit besieged mountain citadel, violet enemy portals, cool dark blue mountain valley, and warm amber defending towers. Compose a new original dynamic square promotional illustration with a clearly readable central medieval-fantasy fortress and a winding approach crowded by incoming monsters, four small defending heroic silhouettes in the foreground (an armored builder with hammer, an archer, a mage and a warrior), defensive towers firing magic toward the approaching wave, sunrise breaking behind the castle. Evoke the dramatic high-fantasy valley-defense mood of a classic Dota custom game promotional cover, polished painterly PC game key art with strong silhouettes and controlled detail, no UI screenshot, no copied logos or existing third-party poster. Put the exact FOUR Chinese title characters 「孤城逐晓」 in large crisp elegant pale-gold embossed calligraphic lettering occupying the lower quarter, strongly readable even as a small thumbnail; no frame around the whole image. Under it put only the small exact subtitle 「协作塔防 · 无尽生存」. Preserve adequate safe margins on every side; keep all title text inside the central 82% width. Bright warm gold focal point against cool blue-violet environment, dramatic depth, accurate clean typography, no watermark, no Dota logo, no payment/currency/marketing claims, no 'official' label.

## 2026-10-22 官方发布器4:3版

实机发布对话框明确将图片缩放为1024×768，因此用内置imagegen对原图重新构图为4:3，保留原主题和文字，避免拉伸方图。新原图 `gucheng_zhuxiao_cover_4x3_master.png` 为1448×1086；上传文件 `gucheng_zhuxiao_workshop_1024x768.jpg` 等比缩小为1024×768、JPEG质量92、412015字节。前述方图保留为原始设计，当前实际上传预览使用4:3版。

编辑提示词：

> Edit the provided original game cover into a LANDSCAPE 4:3 composition for a Steam Workshop cover that will be displayed at exactly 1024x768. Preserve the same game identity, painterly high fantasy style, dawn-lit fortress, violet portals, incoming monster waves, four defending heroes, blue-gold palette, and exact gold Chinese title 「孤城逐晓」 with exact subtitle 「协作塔防 · 无尽生存」. Expand/recompose the sides naturally to form a 4:3 landscape image; do NOT stretch, squash or distort the castle, characters or typography. Keep the complete title and subtitle crisp and comfortably inside a 10% safe margin, in the lower quarter. Keep the fortress as clear central focal point and the four heroes visible along the lower foreground, with the title clearly separated beneath them. This is a practical aspect-ratio adaptation of the approved existing artwork, no new branding, no decorative outer frame, no additional text, no watermark, no Dota logo. Output 4:3 landscape artwork, suitable to scale proportionally to 1024x768.
