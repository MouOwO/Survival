const fs=require('fs'),base='file://{images}/custom_game/archive_kit/';let css=`/* Archive kit V1; 1002 x 758 design shell, one parent scale. */
#ArchiveScrim {width:100%;height:100%;background-color:#0000008c;z-index:10000;}
#ArchiveWindow {width:1002px;height:758px;align:center center;flow-children:none;padding:0px;background-image:url("${base}background_tiles/shell_body.png");background-size:100% 100%;background-color:transparent;border:0px solid transparent;border-radius:0px;box-shadow:none;z-index:10001;}
#ArchiveWindow Label {font-family:"Source Han Sans SC","Noto Sans CJK SC","Microsoft YaHei",sans-serif;text-shadow:none;}
#ArchiveHeader {position:0px 0px 0px;width:1002px;height:76px;flow-children:none;border:0px solid transparent;}
#ArchiveTitleBlock {position:320px 0px 0px;width:362px;height:75px;flow-children:down;padding:0px;}
#ArchiveWindow #ArchiveTitle {margin-top:4px;font-family:"Source Han Serif SC","Noto Serif CJK SC","SimSun",serif;font-size:38px;font-weight:bold;letter-spacing:5px;color:#fff1ce;}
#ArchiveSubtitle {visibility:visible;font-size:15px;color:#ebeee5;letter-spacing:2px;}
#ArchiveBook {position:276px 13px 0px;width:42px;height:42px;}
#ArchiveClose {position:925px 12px 0px;margin:0px;width:50px;height:50px;background-color:transparent;border:0px solid transparent;}
#ArchiveClose .ArchiveKitIcon {width:42px;height:42px;align:center center;}
#ArchiveBody {position:0px 76px 0px;width:1002px;height:682px;flow-children:none;padding:0px;}
#ArchiveTabs {position:7px 12px 0px;width:232px;height:660px;flow-children:down;padding:0px;overflow:squish scroll;}
.ArchiveTab {width:225px;height:70px;margin:0px 0px 3px 0px;padding:0px;background-image:url("${base}reusable/toggle_normal.png");background-size:100% 100%;background-color:transparent;border:0px solid transparent;border-radius:0px;transition-property:brightness;transition-duration:.1s;}
.ArchiveTab:hover {background-image:url("${base}reusable/toggle_hover.png");}
.ArchiveTab:selected,.ArchiveTab:selected:hover {background-image:url("${base}reusable/toggle_selected.png");border:0px solid transparent;background-color:transparent;}
.ArchiveTab:selected:hover {brightness:1.06;}
.ArchiveTab:disabled {opacity:.45;}
.ArchiveKitIcon {width:38px;height:38px;background-size:100% 100%;}
.ArchiveTab .ArchiveKitIcon {position:18px 16px 0px;}
.ArchiveTab Label {position:64px 0px 0px;width:155px;height:70px;vertical-align:center;text-align:left;font-size:21px;color:#f3eedb;}
.ArchiveTab:selected Label {color:#24424c;}
#ArchiveContent {position:240px 0px 0px;width:762px;height:682px;flow-children:none;padding:0px;}
#ArchivePageHeader {position:30px 19px 0px;width:702px;height:60px;flow-children:none;border:0px solid transparent;}
#ArchivePageTitle {font-family:"Source Han Serif SC","SimSun",serif;font-size:30px;font-weight:bold;color:#1f4355;}
#ArchiveSummary {position:0px 40px 0px;width:702px;font-size:16px;color:#536e79;}
#ArchiveHint {position:30px 82px 0px;width:702px;height:26px;font-size:15px;color:#4e6672;white-space:normal;}
#ArchiveFilters {position:30px 110px 0px;width:702px;height:37px;flow-children:right;}
#ArchiveFilters RadioButton {width:126px;height:34px;margin-right:10px;background-image:url("${base}reusable/button_normal.png");background-size:100% 100%;}
#ArchiveFilters .RadioBox {visibility:collapse;}
#ArchiveFilters Label {align:center center;font-size:17px;color:#35535f;}
#ArchiveFilters RadioButton:selected {background-image:url("${base}reusable/toggle_normal.png");}
#ArchiveFilters RadioButton:selected Label {color:#fff0cf;}
#ArchiveGrid {position:30px 154px 0px;width:710px;height:482px;flow-children:right-wrap;overflow:squish scroll;margin:0px;padding:0px;}
.ArchiveCard {width:162px;height:154px;margin:0px 12px 10px 0px;padding:0px;flow-children:none;background-image:url("${base}reusable/card_normal.png");background-size:100% 100%;background-color:transparent;border:0px solid transparent;}
.ArchiveCard:hover {background-image:url("${base}reusable/card_hover.png");}
.ArchiveCard.ArchiveSelected {background-image:url("${base}reusable/card_selected.png");}
.ArchiveArt {position:25px 8px 0px;width:112px;height:98px;border:0px solid transparent;background-color:transparent;background-size:contain;background-position:center;background-repeat:no-repeat;}
.ArchiveCompleted {saturation:1;brightness:1;}
.ArchiveCount {position:104px 6px 0px;width:52px;height:22px;horizontal-align:left;vertical-align:top;background-color:#294c5beF;border:1px solid #bdac82;border-radius:10px;padding:0px;text-align:center;font-size:15px;color:#f8f2e4;z-index:3;}
.ArchiveItemName {position:8px 106px 0px;width:146px;height:24px;margin:0px;text-align:center;color:#264a5b;font-size:17px;text-overflow:ellipsis;}
.ArchiveUnlockBadge {position:24px 130px 0px;width:114px;height:20px;text-align:center;font-size:14px;color:#fffaf0;background-size:100% 100%;}
.ArchiveUnlockBadge.Unlocked {background-image:url("${base}reusable/badge_unlocked.png");}
.ArchiveUnlockBadge.Locked {background-image:url("${base}reusable/badge_locked.png");}
.ArchiveFragmentLevel {position:8px 132px 0px;font-size:13px;color:#35535f;}
.ArchivePromote {position:56px 129px 0px;width:100px;height:23px;margin:0px;background-size:100% 100%;border:0px solid transparent;}
.ArchivePromote Label {color:#24424c;font-size:13px;}
.ArchiveWorkCost {position:8px 129px 0px;width:146px;height:22px;text-align:center;font-size:14px;color:#35535f;}
#ArchiveFooter {position:30px 644px 0px;width:702px;height:32px;flow-children:none;}
#ArchiveStatus {width:702px;height:30px;margin:0px;font-size:13px;white-space:normal;color:#546b74;}
#ArchiveEmpty {align:center center;color:#44616d;font-size:20px;}
#ArchiveDrawBar {position:30px 598px 0px;width:702px;height:44px;align:left top;margin:0px;padding:3px 8px;background-color:#e6e7df;border:0px solid transparent;}
#ArchiveContent.ArchiveHasDraw #ArchiveGrid {height:430px;margin:0px;}
#ArchiveTickets,#ArchiveDrawResult {color:#35535f;font-size:15px;}
#ArchiveDraw {height:36px;width:108px;}
#ArchiveDraw Label {color:#24424c;}
#ArchiveTooltip {z-index:100010;background-color:#213b46f8;border:1px solid #c9b386;}
#ArchiveTooltipName,#ArchiveTooltipEffect {font-family:"Source Han Sans SC","Microsoft YaHei",sans-serif;text-shadow:none;}
#ArchiveGrid VerticalScrollBar {width:6px;background-color:#c2cbd0;}
#ArchiveGrid VerticalScrollBar .ScrollThumb {background-color:#b9a77e;}
`;
for(const key of ['clear','void','points','weapon','spell','endless','friends','ex','blessing','close','book','hint']){for(const state of ['normal','hover','selected','disabled']){const sel=state==='normal'?`.KitIcon_${key}`:state==='selected'?`.ArchiveTab:selected .KitIcon_${key}`:state==='hover'?`Button:hover .KitIcon_${key},.ArchiveTab:hover .KitIcon_${key}`:`Button:disabled .KitIcon_${key},.ArchiveTab:disabled .KitIcon_${key}`;css+=`${sel} {background-image:url("${base}icons_rgba/${key}_${state}.png");}\n`;}css+=`.ArchiveTab:selected:hover .KitIcon_${key} {background-image:url("${base}icons_rgba/${key}_selected.png");}\n`;}
for(const n of ['01','02','03','04','05','06','10'])css+=`.KitArt_${n} {background-image:url("${base}art_tiles/art_${n}.png");}\n`;
for(const [state,pseudo] of [['normal',''],['hover',':hover'],['pressed',':active']])css+=`#ArchiveDraw${pseudo},.ArchivePromote${pseudo} {background-image:url("${base}reusable/button_${state}.png");background-size:100% 100%;background-color:transparent;border:0px solid transparent;}\n`;
fs.writeFileSync('panorama/src/styles/custom_game/archive_kit.css',css);
let js=fs.readFileSync('panorama/src/scripts/custom_game/archive.js','utf8');js=js.replace('        var title = categories.filter', '        done=rows.filter(function(item){return Number(item.completed)===1;}).length;\n        ownedTypes=rows.filter(function(item){return Number(item.count)>0;}).length;\n        var title = categories.filter');fs.writeFileSync('panorama/src/scripts/custom_game/archive.js',js);
let deploy=fs.readFileSync('tools/deploy_archive_panorama.ps1','utf8');deploy=deploy.replace("$files += @('styles/custom_game/archive_gothic.css')","$files += @('styles/custom_game/archive_kit.css', 'scripts/custom_game/ui_layers.js')");deploy=deploy.replace("$assets = @('images/custom_game/archive_moon/window.png', 'images/custom_game/archive_moon/tab.png', 'images/custom_game/archive_moon/tab_selected.png')","$kit = Join-Path $source 'images/custom_game/archive_kit'\n$assets = @(Get-ChildItem -LiteralPath $kit -File -Recurse | ForEach-Object { 'images/custom_game/archive_kit/' + $_.FullName.Substring($kit.Length + 1).Replace('\\','/') })");fs.writeFileSync('tools/deploy_archive_panorama.ps1',deploy);
