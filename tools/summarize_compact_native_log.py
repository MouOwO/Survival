"""Aggregate native message sizes without exposing KV/account/auth payloads."""
from pathlib import Path
import argparse,base64,collections,hashlib,json,math,re
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('log',type=Path)
    args=parser.parse_args();path=args.log.resolve()
    if not path.is_relative_to((ROOT/'output').resolve()) or path.stat().st_size>128*1024*1024:
        raise ValueError('bounded_workspace_output_log_required')
    raw=path.read_bytes();text=raw.decode('latin1');events={};views={};header=None;name=None;bad=0
    for line in text.splitlines():
        found=re.search(r'\((\d+) bits/(\d+) bytes\):',line)
        if found:header=tuple(map(int,found.groups()));name=None
        elif 'CUserMsg_CustomGameEvent [148]'in line:name=''
        elif name is not None and 'event_name:'in line:
            event=re.search(r'event_name: "([A-Za-z0-9_]+)"',line)
            if event and header:
                name=event[1];bits,native=header
                if math.ceil(bits/8)!=native:raise ValueError('native_bit_rounding_differs')
                row=events.setdefault(name,dict(count=0,max_native_bytes=0,total_native_bytes=0))
                row['count']+=1;row['max_native_bytes']=max(row['max_native_bytes'],native);row['total_native_bytes']+=native
        elif name=='cw' and 'data:'in line:
            payload=re.search(r'\\000\\000\\001d\\000([A-Za-z0-9_-]+)\\000\\013\\013',line)
            if not payload:bad+=1;continue
            data=base64.urlsafe_b64decode(payload[1]+'='*(-len(payload[1])%4));offset=1;fields=[]
            for _ in range(7):
                value=0;shift=0
                while True:
                    byte=data[offset];offset+=1;value+=(byte&127)<<shift;shift+=7
                    if byte<128:break
                    if shift>35:raise ValueError('invalid_probe_varint')
                fields.append(value)
            view=fields[3];row=views.setdefault(str(view),dict(frames=0,full_frames=0,delta_frames=0,max_native_bytes=0,transactions=set()))
            row['frames']+=1;row['full_frames']+=data[0]==17;row['delta_frames']+=data[0]==16
            row['max_native_bytes']=max(row['max_native_bytes'],header[1]);row['transactions'].add(tuple(fields[:5]))
    for row in views.values():row['transactions']=len(row['transactions'])
    result=dict(status='NATIVE_LOG_AGGREGATE_NOT_FPS_OR_ORDINARY_ACCEPTANCE',
        log_sha256=hashlib.sha256(raw).hexdigest(),log_closed='ShutdownSource2Logging'in text,
        events=events,compact_views=views,compact_unparsed=bad,
        layer='CUserMsg_CustomGameEvent; UDP/IP/Steam headers excluded',
        raw_payloads_disclosed=False)
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
