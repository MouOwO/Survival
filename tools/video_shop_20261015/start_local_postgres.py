import subprocess,json,sys
from pathlib import Path
root=Path('output/video_shop_20261015/postgres_test').resolve();binary=root/'portable/pgsql/bin';data=root/'data';log=root/'postgres.log'
flags=subprocess.CREATE_NO_WINDOW
if not (data/'PG_VERSION').exists():
 result=subprocess.run([str(binary/'initdb.exe'),'-D',str(data),'-U','postgres','-A','trust','--no-locale','-E','UTF8'],capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=flags)
 (root/'initdb.log').write_text(result.stdout+'\n'+result.stderr,encoding='utf8')
 if result.returncode: print(result.stdout,result.stderr);sys.exit(result.returncode)
if not (data/'postmaster.pid').exists():
 with (root/'startup.log').open('w',encoding='utf8') as output:
  result=subprocess.run([str(binary/'pg_ctl.exe'),'-D',str(data),'-l',str(log),'-o','-h 127.0.0.1 -p 54627 -F','-w','start'],stdout=output,stderr=subprocess.STDOUT,creationflags=flags,timeout=45)
 if result.returncode:sys.exit(result.returncode)
sys.path.insert(0,str(Path('output/video_shop_20261015/deps').resolve()))
import psycopg
with psycopg.connect('host=127.0.0.1 port=54627 dbname=postgres user=postgres',autocommit=True) as c:
 if not c.execute("select 1 from pg_database where datname='survival_bundle_test'").fetchone():c.execute('CREATE DATABASE survival_bundle_test')
 print(c.execute('select version()').fetchone()[0])
print('ISOLATED_POSTGRES_READY localhost:54627/survival_bundle_test')
