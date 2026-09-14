"""Synchronize declared column defaults/bounds without rewriting player values."""
from pathlib import Path
import re
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'server'))
from archive_backend.bundle import read_csv
rows=read_csv(root/'data/csv/玩家档案系统/player_gameplay_stats.csv')['rows']
sql=['-- Generated from player_gameplay_stats.csv; existing player values are preserved.','begin;']
for row in rows:
    name=row['field_id'];assert re.fullmatch('[a-z][a-z0-9_]*',name)
    default=row['default_value'];kind='bigint' if row['storage_type']=='integer' else 'numeric'
    sql.append(f'alter table public.player_gameplay_stats add column if not exists "{name}" {kind} not null default {default};')
    sql.append(f'alter table public.player_gameplay_stats alter column "{name}" set default {default};')
    constraint=('player_gameplay_stats_'+name+'_check')[:63]
    sql.append(f'alter table public.player_gameplay_stats drop constraint if exists "{constraint}";')
    checks=[f'"{name}"::text not in (\'NaN\',\'Infinity\',\'-Infinity\')']
    for key,op in [('min_value','>='),('max_value','<=')]:
        if key in row: checks.append(f'"{name}" {op} {row[key]}')
    if kind=='bigint':checks.append(f'"{name}"=trunc("{name}")')
    sql.append(f'alter table public.player_gameplay_stats add constraint "{constraint}" check ('+' and '.join(checks)+');')
sql.append('commit;')
(root/'server/migrations/202609140002_gameplay_stats_csv_bounds.sql').write_text('\n'.join(sql)+'\n',encoding='utf-8')
print('GAMEPLAY_STATS_SQL_BUILT fields='+str(len(rows)))
