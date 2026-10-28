"""Pinned 2803 official download verification using the frozen SDK protocol."""
from pathlib import Path
import hashlib,importlib.util,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
need=lambda flag,message: None if flag else (_ for _ in ()).throw(ValueError(message))
need(hashlib.sha256(SOURCE.read_bytes().replace(b'\r\n',b'\n')).hexdigest()=='1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f','Frozen official protocol changed')
spec=importlib.util.spec_from_file_location('rebirth2803_official_protocol',SOURCE)
protocol=importlib.util.module_from_spec(spec);spec.loader.exec_module(protocol)
ITEM,SEQUENCE,FILE_COUNT='3824360109',2026102803,6658
CONTENT='7d39ab251f4c8f20d8338a49a8335b0447c0e4e8f6a196978312b40f8981ab96'
CANDIDATE=Path('D:/Survival_发布候选/20261028_ws4_rebirth_selection_v01_view')
TRUSTED=Path('D:/Survival_发布候选/20261028_ws4_rebirth_selection_v01_overlay_trusted_source')
VPK=Path('D:/Survival_工坊输出/20261028_ws4_rebirth_selection_v01/3824360109.vpk')
REPORT=ROOT/'output/rebirth_selection_20261028/package.json'
STATE=ROOT/'output/four_accounts_20261022/steam_upload_state.json'
OUTPUT=ROOT/'output/rebirth_selection_20261028/download_evidence'
MINIMUM_REMOTE_UPDATED=1793149392
REPORT_SHA='a9492685a24d871dc003a02bf08b2145952f7171409e3bc7088b44c5b21c2320'
INDEX_SHA='c293d9335610df50417f3f06b86e14e9f576cee4993892c166054b7b9ef78a2e'
TOTAL_BYTES=3767364782
for name in ('ITEM','SEQUENCE','FILE_COUNT','CONTENT','CANDIDATE','TRUSTED','VPK','REPORT','STATE','OUTPUT','MINIMUM_REMOTE_UPDATED'):setattr(protocol,name,globals()[name])
original=protocol.local_inputs
def local_inputs(require_success=False,*,full=False):
    need(hashlib.sha256(REPORT.read_bytes()).hexdigest()==REPORT_SHA,'Completed package report changed')
    result=original(require_success,full=full)
    need(result['report']['vpk_sha256']==INDEX_SHA and result['total']==TOTAL_BYTES,'Completed package identity mismatch')
    return result
protocol.local_inputs=local_inputs
if __name__=='__main__':raise SystemExit(protocol.main())
