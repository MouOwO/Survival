"""Export the actual local server catalog compilers for a read-only UI audit."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.commerce_catalog import build_catalog as wallet_catalog
from payment_backend.csv_catalog import build as payment_catalog

out = ROOT / 'output/shop_icon_quality_20261017'
out.mkdir(parents=True, exist_ok=True)
result = {'wallet': wallet_catalog(ROOT), 'payment': payment_catalog(ROOT)['catalog']}
(out / 'catalogs.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({channel: len(value['products']) for channel, value in result.items()}))
