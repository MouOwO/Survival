"""One-pass native warning counts; byte totals are logged payloads, not FPS."""
import argparse,collections,json,re
from pathlib import Path

PATTERN=re.compile(r'^(\d\d/\d\d \d\d:\d\d:\d\d).*CUserMsg_CustomGameEvent.*?size (\d+) exceeded maximum message size (\d+)')

def analyze(path):
    path=Path(path)
    if not path.is_file() or path.is_symlink() or path.stat().st_size>64*1024*1024:
        raise ValueError('bounded_regular_native_log_required')
    sizes=collections.Counter();seconds=collections.Counter();limits=collections.Counter();total=0
    with path.open(encoding='utf8',errors='replace') as stream:
        for line in stream:
            found=PATTERN.search(line)
            if found:
                stamp,size,limit=found.groups();size=int(size)
                sizes[size]+=1;seconds[stamp]+=1;limits[int(limit)]+=1;total+=size
    ordered=sorted(seconds)
    return dict(status='NATIVE_LOG_WARNINGS_COUNTED',warning_count=sum(sizes.values()),
        logged_payload_bytes=total,by_payload_size=dict(sizes.most_common(15)),
        per_second_peak=seconds.most_common(10),first_warning=ordered[0]if ordered else None,
        last_warning=ordered[-1]if ordered else None,seconds_with_warnings=len(seconds),
        enforced_limits=dict(limits),actual_fps_measured=False,bandwidth_including_headers_measured=False,
        source_bytes=path.stat().st_size)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('log',type=Path)
    args=parser.parse_args();print(json.dumps(analyze(args.log),ensure_ascii=False,indent=2))
