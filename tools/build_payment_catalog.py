"""Validate editable shop CSVs and write the exact catalog that will be published."""
import argparse
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'server'))
from payment_backend.csv_catalog import build,canonical

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'output/payment_catalog.json')
    args=parser.parse_args()
    try:
        data=build(ROOT)
        for product in data['catalog']['products']:
            if not (ROOT/'panorama/src/images'/product['icon']).is_file():
                raise ValueError('商品图标文件不存在: '+product['sku']+' / '+product['icon'])
    except (ValueError,KeyError) as exc:raise SystemExit('SHOP_CSV_ERROR: '+str(exc)) from None
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(canonical(data))
    products=data['catalog']['products']
    print('SHOP_CSV_PASS: '+str(sum(p['enabled'] for p in products))+' enabled / '+str(len(products))+' total; '+data['catalog_hash'])

if __name__=='__main__':main()
