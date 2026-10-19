"""Encode review-only images. Authored game assets and official exports are read-only."""
from pathlib import Path
import base64
import hashlib
import io
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'output/lottery_five_official_20261019'

def main():
    jobs = json.loads((WORK / 'image_jobs.json').read_text(encoding='utf-8'))
    result = {}
    for job in jobs:
        file = ROOT / job['source']
        blob = file.read_bytes()
        if file.suffix.lower() == '.svg':
            encoded, mime, dimensions = blob, 'image/svg+xml', job.get('size', [24, 24])
            preview_size = dimensions
        else:
            with Image.open(file) as image:
                dimensions = list(image.size)
                image = image.convert('RGBA')
                image.thumbnail(tuple(job.get('maxSize', [2048, 1152])), Image.Resampling.LANCZOS)
                stream = io.BytesIO()
                image.save(stream, format='WEBP', lossless=dimensions[0] <= 1024 and dimensions[1] <= 1024,
                           quality=94, method=4)
                encoded, mime, preview_size = stream.getvalue(), 'image/webp', list(image.size)
        result[job['key']] = {'preview': 'data:' + mime + ';base64,' + base64.b64encode(encoded).decode('ascii'),
                              'originalSize': dimensions, 'previewSize': preview_size,
                              'originalSha256': hashlib.sha256(blob).hexdigest(), 'source': job['source']}
    (WORK / 'prepared_images.json').write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
    print(f'FIVE_LOTTERY_REVIEW_IMAGES_READY {len(result)}')

if __name__ == '__main__':
    main()
