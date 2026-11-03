"""Extract exact cw/d native sizing samples from the closed isolated LAB log.

No engine process, network, SDK or player action. Full raw logs stay private;
the receipt includes only probe lengths, build identity and source digests.
"""
from pathlib import Path
import hashlib,json,math,re

ROOT=Path(__file__).resolve().parents[1]
LOG=ROOT/'output/network50_native_probe_20261103/run03/engine.log'
PROCESS=Path('D:/Survival_本地排演/network50_probe_20261103/run03/process.json')
DEST=ROOT/'output/network50_native_probe_20261103/native_budget.json'
EXPECTED=(0,1,8,16,24,28,32,40)

def main():
    if LOG.is_symlink() or not LOG.is_file() or LOG.stat().st_size>16*1024*1024:
        raise ValueError('bounded_regular_native_probe_log_required')
    # Parse ASCII engine diagnostics one byte per character. Unrelated native
    # names may contain truncated UTF-8; they must not change byte measurements.
    raw=LOG.read_bytes();text=raw.decode('latin1')
    if text.count('[N50_NATIVE_PROBE] BEGIN event=cw key=d')!=1 or text.count('[N50_NATIVE_PROBE] END sends=8 transactions=0')!=1:
        raise ValueError('exact_complete_native_probe_lifecycle_required')
    if 'ShutdownSource2Logging' not in text:raise ValueError('closed_native_probe_log_required')
    process=json.loads(PROCESS.read_bytes())
    if process.get('transactions')!=0 or process.get('workshop_install_written')is not False:
        raise ValueError('isolated_nontransactional_probe_required')
    header=None;event=False;matched=False;samples=[]
    for line in text.splitlines():
        found=re.search(r'\((\d+) bits/(\d+) bytes\):',line)
        if found:header=tuple(map(int,found.groups()));event=False;matched=False
        elif 'CUserMsg_CustomGameEvent [148]' in line:event=True
        elif event and 'event_name: "cw"' in line:matched=True
        elif event and matched and 'data:' in line:
            payload=re.search(r'\\000\\000\\001d\\000(A*)\\000\\013\\013',line)
            if not payload or not header:raise ValueError('exact_single_string_key_native_encoding_required')
            size=len(payload[1]);bits,native=header
            if math.ceil(bits/8)!=native:raise ValueError('native_bit_rounding_differs')
            samples.append(dict(value_bytes=size,native_bytes=native,native_bits=bits))
            event=False
    if tuple(row['value_bytes']for row in samples)!=EXPECTED:raise ValueError('complete_ordered_native_sample_sweep_required')
    overhead={row['native_bytes']-row['value_bytes']for row in samples}
    if overhead!={25}:raise ValueError('native_envelope_changed_no_budget_proof')
    build=re.search(r'\[Client\] Build: (\d+) \(revision (\d+)\)',text)
    if not build:raise ValueError('actual_native_engine_build_required')
    binary=ROOT.parents[1]/'bin/win64/networksystem.dll'
    with binary.open('rb')as stream:engine_hash=hashlib.file_digest(stream,'sha256').hexdigest()
    value=dict(method='net_showmsg',layer='CUserMsg_CustomGameEvent',event='cw',key='d',
        engine_build=build[1]+':'+build[2],networksystem_sha256=engine_hash,
        source_log_sha256=hashlib.sha256(raw).hexdigest(),samples=samples,
        fixed_native_ceil_bytes=25,value_budget=24,native_message_limit=50,max_admitted_native_bytes=49,
        native_probe=True,tools_only=True,ordinary_production_acceptance=False,
        layer_note='net_showmsg incoming message bits rounded to bytes; excludes UDP/IP/Steam transport packet headers',
        workshop_install_written=False,transactions=0)
    DEST.parent.mkdir(parents=True,exist_ok=True)
    with DEST.open('x',encoding='utf8',newline='\n')as stream:json.dump(value,stream,indent=2);stream.write('\n')
    print(json.dumps(value))

if __name__=='__main__':main()
