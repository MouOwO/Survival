"""Read-only fingerprint of archive config registration and server schema."""
from pathlib import Path
import hashlib
import json
import sys

sys.path.insert(0, str(Path('/opt/goufayu/payments/current').resolve()))
from deploy import connection
with connection() as conn:
    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
    assert conn.info.dbname == 'goufayu_test'
    signature = 'public.archive_sync_config(text,jsonb)'
    definition = conn.execute('SELECT pg_get_functiondef(to_regprocedure(%s))', (signature,)).fetchone()[0]
    functions = {signature: dict(definition=definition, sha256=hashlib.sha256(definition.encode()).hexdigest())}
    tables = [r[0] for r in conn.execute("SELECT schemaname||'.'||tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1")]
    hashes = [r[0] for r in conn.execute('SELECT config_hash FROM public.archive_config_sets ORDER BY 1')]
    conn.rollback()
print(json.dumps(dict(status='READONLY_ARCHIVE_SCHEMA_PASS', functions=functions, tables=tables, registered_hashes=hashes, database_writes=0)))
