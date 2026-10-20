"""Compose original screenshots and integer nearest-neighbour font crops.

Run only after the root agent has frozen daily_stargold_final_native_20261019.png.
No production resources or screenshot source files are changed.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/daily_stargold_integration_20261019'
NATIVE=ROOT/'design_refs/menus_v10/work/native'
FONT=ROOT/'panorama/fonts/Radiance-Survival-SourceHanSansSC-Regular.otf'
MEDIUM=ROOT/'panorama/fonts/Radiance-Survival-SourceHanSansSC-Medium.otf'
BG='#0b100f'; PANEL='#121713'; GOLD='#e7c37c'; TEXT='#e4ddca'; MUTED='#a69c85'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def face(size,medium=False):
    return ImageFont.truetype(str(MEDIUM if medium else FONT),size)

def text(draw,xy,value,size=20,fill=TEXT,medium=False):
    draw.text(xy,value,font=face(size,medium),fill=fill)

def panel(canvas,box):
    ImageDraw.Draw(canvas).rectangle(box,fill=PANEL,outline='#675735',width=1)

def write_png(image,name):
    target=OUT/name
    image.save(target,optimize=True)
    return {'path':str(target.relative_to(ROOT)).replace('\\','/'),'size':list(image.size),'sha256':digest(target.read_bytes())}

def load_copy(source,name):
    raw=source.read_bytes(); target=OUT/name;target.write_bytes(raw)
    image=Image.open(target).convert('RGB')
    return image,{'source':str(source.relative_to(ROOT)).replace('\\','/'),'copy':name,'size':list(image.size),'sha256':digest(raw),'exactByteCopy':True}

def make_overall(preview,native):
    # Overview is intentionally downscaled. The font sheet below uses exact source pixels.
    canvas=Image.new('RGB',(1680,840),BG);draw=ImageDraw.Draw(canvas)
    text(draw,(32,20),'星穹鎏金 · 第 5 轮设计与游戏实机',28,GOLD,True)
    text(draw,(32,62),'本图用于比较布局与色调；请用下方字体对比或原图检查文字。',17,MUTED)
    for x,img,title,subtitle in [
        (32,preview,'设计预览 · R5','浏览器演示：累计签到 8 次'),
        (864,native,'游戏实机 · 正式接入','真实账号：累计签到 6 次')]:
        panel(canvas,(x,112,x+784,705));text(draw,(x+18,125),title,22,GOLD,True)
        text(draw,(x+18,162),subtitle,16,MUTED)
        thumb=img.resize((768,round(img.height*768/img.width)),Image.Resampling.LANCZOS)
        canvas.paste(thumb,(x+8,206))
    text(draw,(32,730),'正式图标遵循共享资源表，签到进度以真实账号为准；演示中的图标与 8 次进度仅用于设计。',18,TEXT)
    text(draw,(32,768),'保留 28 日历格、3 档月卡奖励、居中操作按钮；整体缩略图不用于给字体清晰度打分。',17,MUTED)
    return write_png(canvas,'预览与实机对比.png')

def make_font_sheet(serif,sans):
    # Each destination is exactly 2x its source region. No blur or sharpening is applied.
    crops=[
        ('标题字形',(690,110,910,155),'标题只比较真实字族与字重：宋体 Bold / 黑体 Medium。'),
        ('日期文字',(270,252,628,284),'两版小字同时由 16 调至 18；不应把差异全部归因于字族。'),
        ('累计签到次数',(837,201,1097,235),'保持原图位置和像素；数字与中文可一起观察。'),
        ('页脚说明',(688,771,1048,798),'页脚局部；未施加锐化、去噪或平滑。')]
    canvas=Image.new('RGB',(1600,1040),BG);draw=ImageDraw.Draw(canvas)
    text(draw,(28,18),'真实游戏字体对照 · 原像素局部 × 2',28,GOLD,True)
    text(draw,(28,63),'所有局部均为整数 2 倍最近邻；字体参数为界面设定字号，非屏幕测量值。',17,MUTED)
    text(draw,(28,95),'A → B 同时调整标题字族、字重和小字字号；此图是视觉对照，不是科学清晰度测试。',17,MUTED)
    text(draw,(28,145),'A · 思源宋体 Bold 36 / 小字 16',23,GOLD,True)
    text(draw,(828,145),'B · 思源黑体 Medium 36 / 小字 18',23,GOLD,True)
    results=[]
    for i,(name,box,note) in enumerate(crops):
        y=197+i*190
        for x,img in [(28,serif),(828,sans)]:
            panel(canvas,(x,y,x+744,y+176));text(draw,(x+10,y+8),name,19,TEXT,True)
            patch=img.crop(box).resize(((box[2]-box[0])*2,(box[3]-box[1])*2),Image.Resampling.NEAREST)
            canvas.paste(patch,(x+10,y+42))
        text(draw,(28,y+157),note,13,MUTED)
        results.append({'name':name,'sourcePixelBox':list(box),'integerScale':2,'resampling':'NEAREST','sharpening':False})
    text(draw,(28,985),'独立目视评审推荐 B：笔画更均匀、小字更易辨认；结论为视觉判断，无清晰度分数。',17,TEXT)
    return write_png(canvas,'字体原像素对比.png'),results

def make_html(sources):
    esc=html.escape
    # Exact original screenshots are copied alongside this file. Gallery scaling can be disabled.
    preview,native,serif,sans=sources
    source_cards=''.join(f'<article><h3>{esc(label)}</h3><p>{esc(note)}</p><a href="{esc(item["copy"])}" target="_blank"><img src="{esc(item["copy"])}" alt="{esc(label)}"></a></article>' for label,note,item in [
        ('R5 设计预览','浏览器构图，累计签到 8 次为演示数据。',preview),
        ('最终游戏实机','真实账号累计签到 6 次；图标使用正式共享资源表。',native)])
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>星穹鎏金 · 设计与实机对照</title><style>
*{box-sizing:border-box}body{margin:0;padding:24px;background:#0b100f;color:#e4ddca;font:16px/1.7 'Microsoft YaHei',sans-serif}h1,h2,h3{color:#e7c37c;font-weight:500}h1{margin:0 0 8px;font-size:28px}h2{margin:28px 0 12px;font-size:23px}h3{font-size:19px;margin:0}p{margin:6px 0;color:#b7ad95}a{color:#f0d49b}button{padding:9px 18px;color:#e7c37c;border:1px solid #887044;background:#182018;cursor:pointer;font:inherit}.tools{display:flex;gap:18px;align-items:center;flex-wrap:wrap;margin:18px 0}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.grid article{padding:14px;border:1px solid #675735;background:#121713;overflow:auto}img{display:block;max-width:100%;height:auto;margin-top:12px}.pixel-mode .grid img{max-width:none;width:1600px}.font-sheet{overflow:auto;border:1px solid #675735;padding:12px}.font-sheet img{width:1600px;max-width:none}.note{border-left:3px solid #8c7440;padding:8px 16px;background:#151a14}.links{display:flex;gap:18px;flex-wrap:wrap}@media(max-width:900px){.grid{grid-template-columns:1fr}} </style><body>
<h1>星穹鎏金 · 第 5 轮设计与游戏实机</h1>
<p>界面已接入游戏。下面保留设计原图、最终实机和两轮字体调试记录。</p>
<div class="note">实机图标按共享资源表调用，进度为真实账号签到 6 次；浏览器预览的 8 次进度仅用于设计演示。这里没有修改奖励配置。</div>
<div class="tools"><button id="pixel-toggle" aria-pressed="false">切换原始像素查看</button><span>整体缩略图比较构图；字体请看原始截图或下方整数放大局部。</span></div>
<div class="grid">'''+source_cards+'''</div>
<h2>字体原像素对比</h2><p>A：思源宋体 Bold 36 / 小字 16。B：思源黑体 Medium 36 / 小字 18。字号为界面设定值。</p>
<p>局部统一为原始像素 × 2 最近邻，没有锐化或平滑。A → B 同时调整字族、字重和字号，不能把差异只归因于更换字体。</p>
<div class="font-sheet"><img src="字体原像素对比.png" alt="标题、日期、累计签到、页脚的真实截图原像素对比"></div>
<p>目视评审推荐 B：笔画更均匀，小字更易辨认。此结论是视觉判断，没有科学清晰度分数。</p>
<h2>原图与对照文件</h2><div class="links">
<a href="预览与实机对比.png" target="_blank">布局对比图</a><a href="字体原像素对比.png" target="_blank">字体局部对比</a>
<a href="'''+esc(native['copy'])+'''" target="_blank">最终实机原图</a><a href="'''+esc(serif['copy'])+'''" target="_blank">A 宋体实机原图</a><a href="'''+esc(sans['copy'])+'''" target="_blank">B 黑体实机原图</a></div>
<script>document.querySelector('#pixel-toggle').onclick=function(){var active=document.body.classList.toggle('pixel-mode');this.setAttribute('aria-pressed',String(active));this.textContent=active?'恢复适应宽度':'切换原始像素查看';};</script></body></html>'''
    target=OUT/'对照.html';target.write_text(page,encoding='utf-8')
    return {'path':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':digest(target.read_bytes())}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--final-frozen',action='store_true',help='Explicitly acknowledge the parent has frozen the final native capture.')
    args=parser.parse_args()
    if not args.final_frozen:parser.error('Wait for the parent to freeze the final screenshot, then pass --final-frozen.')
    OUT.mkdir(parents=True,exist_ok=True)
    definitions=[
        (ROOT/'design_refs/daily_stargold_polish_20261019/R5_星穹鎏金.png','R5_设计预览原图.png',(1600,1000)),
        (NATIVE/'daily_stargold_final_native_20261019.png','最终游戏实机原图.png',(1600,900)),
        (NATIVE/'daily_stargold_serif_native_20261019.png','A_宋体实机原图.png',(1600,900)),
        (NATIVE/'daily_stargold_sans_native_20261019.png','B_黑体实机原图.png',(1600,900))]
    images=[];sources=[]
    for file,name,expected in definitions:
        image,record=load_copy(file,name);assert image.size==expected,(file,image.size)
        images.append(image);sources.append(record)
    overall=make_overall(images[0],images[1]);fonts,crops=make_font_sheet(images[2],images[3]);gallery=make_html(sources)
    report={'kind':'native_screenshot_visual_comparison_delivery','sources':sources,'outputs':[overall,fonts,gallery],'fontCrops':crops,'fontCropScale':2,'fontCropResampling':'NEAREST','fontCropEnhancement':False,'fontRecommendation':'B, visual assessment only; family, weight and small font size changed together','productionFilesChanged':False,'rewardConfigurationChanged':False,'notes':['Final screenshot copied only after parent freeze.','Native state is six sign-ins; browser eight-sign-in state is a fixture.','Official live icons follow the maintained shared resource table.','Overview uses LANCZOS reduction for composition only; font crops preserve source pixel detail.']}
    (OUT/'comparison_delivery.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'PASS','sources':len(sources),'outputs':[o['path'] for o in report['outputs']],'fontCropScale':2,'productionFilesChanged':False},ensure_ascii=False))

if __name__=='__main__':main()
