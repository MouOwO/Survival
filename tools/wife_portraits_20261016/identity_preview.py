"""Make a read-only named contact sheet HTML, using unmodified master PNGs."""
from __future__ import annotations

import html
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/wife_portraits_20261016/identity_preview'


def main():
    manifest = json.loads((ROOT / 'data/ui/wife_portraits_v1.json').read_text(encoding='utf-8'))
    OUT.mkdir(parents=True, exist_ok=True)
    cards = []
    for ident, row in manifest['items'].items():
        image = (ROOT / 'panorama/src/images' / row['icon_path']).as_uri()
        label = html.escape(row['canonical_name'])
        series = html.escape(row['series'])
        cards.append(f'<article data-id="{ident}"><span class="id">{ident}</span><img src="{image}" alt="{label}"><strong>{label}</strong><span>{series}</span><small>{row["source_width"]}×{row["source_height"]} · {row["sha256"][:12]}</small></article>')
    old = []
    for ident in ('ex_01', 'ex_05', 'ex_27', 'ex_30'):
        image = (ROOT / f'panorama/src/images/custom_game/archive_portraits_v3/{ident}.png').as_uri()
        old.append(f'<figure><img src="{image}"><figcaption>既有画风 {ident} · 74px</figcaption></figure>')
    text = '''<!doctype html><meta charset="utf-8"><title>老婆头像 · 40人身份核对</title>
<style>*{box-sizing:border-box}body{margin:18px;background:#182229;color:#e9e8e1;font:16px "Microsoft YaHei",sans-serif}h1{margin:0;font-size:24px}p{margin:8px 0;color:#a5b4bd}.grid{display:grid;grid-template-columns:repeat(10,170px);gap:8px}article{position:relative;display:flex;flex-direction:column;align-items:center;background:#252f37;border:1px solid #4d626c;padding:8px;height:208px;text-align:center}article img{width:118px;height:118px;object-fit:contain;background:repeating-conic-gradient(#34404a 0% 25%,#28343d 0% 50%) 0/16px 16px}strong{font-size:15px;line-height:22px}article span:not(.id){font-size:12px;color:#c1d1da}small{font-size:10px;color:#8099a7}.id{position:absolute;left:4px;top:4px;font-size:10px;color:#a1b9c8}.old{display:flex;gap:36px;margin-top:12px}.old figure{margin:0;text-align:center}.old img{width:74px;height:74px;object-fit:contain}.old figcaption{font-size:11px;color:#99abb6}</style>
<h1>老婆头像：40个独立ID与正确人物</h1><p>静态核对页，图片直接读取原PNG；棋盘格表示透明背景。非游戏截图、不连接账号、不修改源图。</p><div class="grid">'''
    text += ''.join(cards) + '</div><div class="old">' + ''.join(old) + '</div>'
    (OUT / 'index.html').write_text(text, encoding='utf-8')
    print(json.dumps({'status': 'IDENTITY_PREVIEW_READY', 'cards': len(cards), 'path': str(OUT / 'index.html')}, ensure_ascii=False))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
