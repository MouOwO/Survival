"""Read the closed, real Panorama C2S sweep; keep raw native logs private."""
from pathlib import Path
import hashlib,json,math,re
ROOT=Path(__file__).resolve().parents[1]
STORE=Path('D:/Survival_本地排演/network50_probe_20261103/run06')
LOG=ROOT/'output/network50_native_probe_20261103/run06/engine.log'
DEST=ROOT/'output/network50_native_probe_20261103/native_c2s_budget.json'
def main():
    if not LOG.is_file() or LOG.is_symlink() or LOG.stat().st_size>32*1024*1024:
        raise ValueError('bounded_regular_c2s_probe_log_required')
    raw=LOG.read_bytes();text=raw.decode('latin1')
    if 'ShutdownSource2Logging' not in text:raise ValueError('closed_native_log_required')
    process=json.loads((STORE/'process.json').read_bytes())
    if process.get('transactions')!=0 or process.get('workshop_install_written')is not False:
        raise ValueError('isolated_probe_process_required')
    header=None;event=False;matched=False;samples=[]
    for line in text.splitlines():
        found=re.search(r'\((\d+) bits/(\d+) bytes\):',line)
        if found:header=tuple(map(int,found.groups()));event=False;matched=False
        elif 'CClientMsg_CustomGameEvent [280]'in line:event=True
        elif event and 'event_name: "cw"'in line:matched=True
        elif event and matched and 'data:'in line:
            payload=re.search(r'\\000\\000\\001d\\000(A*)\\000\\013\\013',line)
            if not payload or not header:raise ValueError('exact_single_string_native_encoding_required')
            bits,native=header
            if math.ceil(bits/8)!=native:raise ValueError('native_bit_rounding_differs')
            samples.append(dict(value_bytes=len(payload[1]),native_bits=bits,native_bytes=native));event=False
    if tuple(row['value_bytes']for row in samples)!=(0,1,8,16,24,32):raise ValueError('complete_ordered_native_c2s_sweep_required')
    if {row['native_bytes']-row['value_bytes']for row in samples}!={25}:raise ValueError('native_c2s_envelope_not_equal_to25')
    build=re.search(r'\[Client\] Build: (\d+) \(revision (\d+)\)',text)
    if not build:raise ValueError('actual_engine_build_required')
    binary=ROOT.parents[1]/'bin/win64/networksystem.dll'
    with binary.open('rb')as stream:binary_sha=hashlib.file_digest(stream,'sha256').hexdigest()
    result=dict(method='net_showmsg',layer='CClientMsg_CustomGameEvent',direction='client_to_server',event='cw',key='d',
        engine_build=build[1]+':'+build[2],networksystem_sha256=binary_sha,source_log_sha256=hashlib.sha256(raw).hexdigest(),
        samples=samples,fixed_native_ceil_bytes=25,value_budget=24,max_admitted_native_bytes=49,native_message_limit=50,
        native_probe=True,tools_only=True,ordinary_production_acceptance=False,transactions=0,workshop_install_written=False,
        layer_note='net_showmsg incoming message bits rounded to bytes; excludes UDP/IP/Steam transport packet headers')
    with DEST.open('x',encoding='utf-8',newline='\n')as stream:json.dump(result,stream,indent=2);stream.write('\n')
    print(json.dumps(result))
if __name__=='__main__':main()
