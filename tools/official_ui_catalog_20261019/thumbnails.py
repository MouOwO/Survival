"""Browser-only thumbnails. Original Valve exports stay byte-for-byte unchanged."""
import base64
import hashlib
import io
import json
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'design_refs/official_ui_catalog_20261019'
WORK = ROOT / 'output/official_ui_catalog_20261019'

def main():
    plan = json.loads((WORK / 'plan.json').read_text(encoding='utf-8'))
    records, failed = [], []
    for i, row in enumerate(plan['assets']):
        source = BASE / row['original']
        if not source.is_file() and source.with_suffix('.jpeg').is_file():
            source = source.with_suffix('.jpeg')
        if not source.is_file():
            failed.append({'id': row['id'], 'sourcePath': row['sourcePath'], 'reason': 'No decoder output'})
            continue
        try:
            blob = source.read_bytes()
            if row['format'] == 'SVG':
                text = blob.decode('utf-8-sig')
                view = re.search(r'viewBox=[\"\']([^\"\']+)', text)
                width = re.search(r'\bwidth=[\"\']([\d.]+)', text)
                height = re.search(r'\bheight=[\"\']([\d.]+)', text)
                dimensions = [float(x) for x in view[1].replace(',', ' ').split()] if view else [0, 0, 24, 24]
                w, h = float(width[1]) if width else dimensions[2], float(height[1]) if height else dimensions[3]
                # Native SVG payload stays exact; external references are not executed by an img.
                mime, preview, method = 'image/svg+xml', blob, 'exact_decoded_svg'
            else:
                with Image.open(source) as original:
                    w, h = original.size
                    thumb = original.convert('RGBA')
                    thumb.thumbnail((384, 240), Image.Resampling.LANCZOS)
                    stream = io.BytesIO()
                    thumb.save(stream, format='WEBP', lossless=w <= 384 and h <= 240, quality=86, method=3)
                    mime, preview, method = 'image/webp', stream.getvalue(), 'browser_thumbnail_only'
            records.append({'id': row['id'], 'sourcePath': row['sourcePath'], 'width': w, 'height': h,
                            'original': source.relative_to(BASE).as_posix(), 'format': source.suffix[1:].upper(),
                            'preview': 'data:' + mime + ';base64,' + base64.b64encode(preview).decode('ascii'),
                            'originalSha256': hashlib.sha256(blob).hexdigest(), 'previewMethod': method})
        except Exception as error:
            failed.append({'id': row['id'], 'sourcePath': row['sourcePath'], 'reason': str(error)})
        if (i + 1) % 500 == 0:
            print(f'OFFICIAL_UI_THUMBNAILS {i + 1}/{len(plan["assets"])}', flush=True)
    (WORK / 'thumbnails.json').write_text(json.dumps({'records': records, 'failed': failed}, ensure_ascii=False), encoding='utf-8')
    print(f'OFFICIAL_UI_THUMBNAILS_COMPLETE {len(records)} previews, {len(failed)} failures', flush=True)

if __name__ == '__main__':
    main()
