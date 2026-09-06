from pathlib import Path
import sys
import re
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'server'))
from archive_backend.bundle import read_csv
rows=read_csv(root/'data/csv/玩家档案系统/player_gameplay_stats.csv')['rows']
lines=['-- Generated from player_gameplay_stats.csv. Adds missing columns; preserves existing data.','begin;']
for r in rows:
    key=r['field_id'];assert re.fullmatch('[a-z][a-z0-9_]*',key)
    kind='bigint' if r['storage_type']=='integer' else 'numeric'
    lines.append(f'alter table public.player_gameplay_stats add column if not exists "{key}" {kind} not null default {r["default_value"]};')
lines+=['commit;','']
(root/'server/migrations/202609060001_archive_stat_columns.sql').write_text('\n'.join(lines),encoding='utf-8')
print('ARCHIVE_STAT_COLUMNS_BUILT',len(rows))
