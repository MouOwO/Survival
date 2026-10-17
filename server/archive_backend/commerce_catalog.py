"""Validate wallet and cash bundles against identical server-owned capabilities."""
from pathlib import Path
from payment_backend.csv_catalog import SOURCES
from payment_backend.commerce_bundles import MEMBER_TABLE,EMPTY_MEMBERS,compile_commerce
from payment_backend.ucoin_catalog import COMMERCE_TABLES

def build_catalog(root):
    base=Path(root)/'data/csv';directory=base/'商城兑换系统'
    tables={name:((directory/(name+'.csv')).read_text(encoding='utf-8-sig')
        if (directory/(name+'.csv')).is_file() else EMPTY_MEMBERS if name==MEMBER_TABLE else '') for name in COMMERCE_TABLES}
    result=compile_commerce(tables,{name:(base/name).read_text(encoding='utf-8-sig') for name in SOURCES},
        (base/'商城支付系统/payment_categories.csv').read_text(encoding='utf-8-sig'))
    for product in result['products']:
        if not (Path(root)/'panorama/src/images'/product['icon']).is_file():raise ValueError('commerce_icon_missing:'+product['sku'])
    return result
