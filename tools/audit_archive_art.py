"""Read-only provenance and transparency audit for the current generated batch."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BULK = ROOT / 'art/ui/development/remaining_ui_handoff_v1/bulk_art'


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def main():
    work = json.loads((BULK / 'prompts.json').read_text(encoding='utf-8'))
    result, issues, pending = [], [], []
    for row in work:
        file = ROOT / 'panorama/src/images' / row['icon_path']
        if not file.exists():
            pending.append(row['item_id'])
            continue
        receipt = BULK / 'receipts' / (row['item_id'] + '.json')
        record = json.loads(receipt.read_text(encoding='utf-8-sig')) if receipt.exists() else {}
        original = Path(record.get('source', ''))
        sha = digest(file)
        with Image.open(file) as image:
            alpha = image.getchannel('A') if image.mode == 'RGBA' else None
            transparent = alpha is not None and alpha.getextrema() == (0, 255)
            bounds = alpha.point(lambda a: 255 if a > 16 else 0).getbbox() if alpha else None
            corners = [alpha.getpixel(pos) for pos in [(0, 0), (image.width-1, 0), (0, image.height-1), (image.width-1, image.height-1)]] if alpha else []
            entry = dict(item_id=row['item_id'], category_id=row['category_id'], name=row['display_name'],
                         path=row['icon_path'], size=list(image.size), sha256=sha,
                         real_alpha=transparent, alpha_bounds=bounds, corner_alpha=corners,
                         original_bytes_preserved=original.is_file() and digest(original) == sha)
            # Some generator outputs have a single alpha=1 corner sample
            # (1/255 opacity). Record it, but distinguish quantization residue
            # from an opaque corner or a visibly clipped subject.
            if not transparent or any(value > 1 for value in corners) or image.width != image.height:
                issues.append(dict(item_id=row['item_id'], issue='canvas_or_alpha'))
            if bounds and (bounds[0] == 0 or bounds[1] == 0 or bounds[2] == image.width or bounds[3] == image.height):
                issues.append(dict(item_id=row['item_id'], issue='subject_touches_canvas_edge'))
            if not entry['original_bytes_preserved']:
                issues.append(dict(item_id=row['item_id'], issue='original_receipt_mismatch'))
            result.append(entry)
    hashes = {}
    for row in result:
        if row['sha256'] in hashes:
            issues.append(dict(item_id=row['item_id'], issue='duplicate_image', other=hashes[row['sha256']]))
        hashes[row['sha256']] = row['item_id']
    report = dict(total=len(work), completed=len(result), corner_alpha_tolerance=1, pending=pending, issues=issues, items=result)
    (BULK / 'art_audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(total=len(work), completed=len(result), pending=len(pending), issues=issues), ensure_ascii=True))


if __name__ == '__main__':
    main()
