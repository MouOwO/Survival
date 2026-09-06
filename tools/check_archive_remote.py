"""Read-only readiness probe. Credentials never leave the existing server process environment."""
import os
from pathlib import Path
import sys
database=Path(r'D:\survival_database')
for line in (database/'.env').read_text(encoding='utf-8-sig').splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1);os.environ[k.strip()]=v.strip()
sys.path.insert(0,str(database/'backend'))
from fishing_api.supabase import SupabaseRpcClient,SupabaseError
client=SupabaseRpcClient(os.environ['SUPABASE_URL'],os.environ.get('SUPABASE_SECRET_KEY') or os.environ['SUPABASE_SERVICE_ROLE_KEY'],20)
try:
    result=client.rpc('archive_resume',{'p_account':'0'*64,'p_id':'archive:readiness:probe'})
    if result.get('error')=='archive_operation_missing':print('ARCHIVE_REMOTE_SCHEMA_READY')
    else: print('ARCHIVE_REMOTE_SCHEMA_RESPONSE',result.get('ok'),result.get('error'))
except SupabaseError as error:
    print('ARCHIVE_REMOTE_SCHEMA_NOT_READY',error.code,error.detail)
    raise SystemExit(2)
