"""Pinned 2804 official download verification using the frozen SDK protocol."""
from pathlib import Path
import hashlib,importlib.util,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
need=lambda flag,message: None if flag else (_ for _ in ()).throw(ValueError(message))
need(hashlib.sha256(SOURCE.read_bytes().replace(b'\r\n',b'\n')).hexdigest()=='1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f','Frozen official protocol changed')
spec=importlib.util.spec_from_file_location('rebirth2804_official_protocol',SOURCE)
protocol=importlib.util.module_from_spec(spec);spec.loader.exec_module(protocol)
ITEM,SEQUENCE,FILE_COUNT='3824360109',2026102804,6658
CONTENT='71a5d2cb2413a427c5c919724ff8384281692700b1fbf48520245525814c4d9e'
CANDIDATE=Path('D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v01_view')
TRUSTED=Path('D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v01_overlay_trusted_source')
VPK=Path('D:/Survival_工坊输出/20261028_ws4_ten_sin_startup_v01/3824360109.vpk')
REPORT=ROOT/'output/ten_sin_startup_20261028/package.json'
STATE=ROOT/'output/four_accounts_20261022/steam_upload_state.json'
OUTPUT=ROOT/'output/ten_sin_startup_20261028/download_evidence'
MINIMUM_REMOTE_UPDATED=1793193858
REPORT_SHA='4ea5b673fdd21fd1753dfd08d627bff0a50313a324c5063cd73e4c820d511555'
INDEX_SHA='7de376afb1380df8003dc7a5b61728cc7483433d5421e3f235090331c273c4df'
TOTAL_BYTES=3767365890
for name in ('ITEM','SEQUENCE','FILE_COUNT','CONTENT','CANDIDATE','TRUSTED','VPK','REPORT','STATE','OUTPUT','MINIMUM_REMOTE_UPDATED'):setattr(protocol,name,globals()[name])
original=protocol.local_inputs
def local_inputs(require_success=False,*,full=False):
    need(hashlib.sha256(REPORT.read_bytes()).hexdigest()==REPORT_SHA,'Completed package report changed')
    result=original(require_success,full=full)
    need(result['report']['vpk_sha256']==INDEX_SHA and result['total']==TOTAL_BYTES,'Completed package identity mismatch')
    return result
protocol.local_inputs=local_inputs
if __name__=='__main__':raise SystemExit(protocol.main())
