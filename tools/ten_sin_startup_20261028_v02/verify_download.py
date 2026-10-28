"""Pinned 2805 official download verification using the frozen SDK protocol."""
from pathlib import Path
import hashlib,importlib.util,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
need=lambda flag,message: None if flag else (_ for _ in ()).throw(ValueError(message))
need(hashlib.sha256(SOURCE.read_bytes().replace(b'\r\n',b'\n')).hexdigest()=='1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f','Frozen official protocol changed')
spec=importlib.util.spec_from_file_location('rebirth2805_official_protocol',SOURCE)
protocol=importlib.util.module_from_spec(spec);spec.loader.exec_module(protocol)
ITEM,SEQUENCE,FILE_COUNT='3824360109',2026102805,6658
CONTENT='549afe0f4125a5f880884f1f5a42d1a6ae307b7b7ea97ddacc400e34dcfd0776'
CANDIDATE=Path('D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v02_view')
TRUSTED=Path('D:/Survival_发布候选/20261028_ws4_ten_sin_startup_v02_overlay_trusted_source')
VPK=Path('D:/Survival_工坊输出/20261028_ws4_ten_sin_startup_v02/3824360109.vpk')
REPORT=ROOT/'output/ten_sin_startup_20261028_v02/package.json'
STATE=ROOT/'output/four_accounts_20261022/steam_upload_state.json'
OUTPUT=ROOT/'output/ten_sin_startup_20261028_v02/download_evidence'
MINIMUM_REMOTE_UPDATED=1793194307
REPORT_SHA='102bbeec95e21acc777ac2418473cc652e01246981adc162c3f0bb36f7a64155'
INDEX_SHA='d6d2f75f530539abe58f69457c41b31f01a362546b573034c860440c9afe8fcc'
TOTAL_BYTES=3767366244
for name in ('ITEM','SEQUENCE','FILE_COUNT','CONTENT','CANDIDATE','TRUSTED','VPK','REPORT','STATE','OUTPUT','MINIMUM_REMOTE_UPDATED'):setattr(protocol,name,globals()[name])
original=protocol.local_inputs
def local_inputs(require_success=False,*,full=False):
    need(hashlib.sha256(REPORT.read_bytes()).hexdigest()==REPORT_SHA,'Completed package report changed')
    result=original(require_success,full=full)
    need(result['report']['vpk_sha256']==INDEX_SHA and result['total']==TOTAL_BYTES,'Completed package identity mismatch')
    return result
protocol.local_inputs=local_inputs
if __name__=='__main__':raise SystemExit(protocol.main())
