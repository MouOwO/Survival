"""Independently analyze one immutable native v2 CSV plus focus/screens metadata.

No game/process interaction. Output contains aggregates and source digests only,
never CSV rows, PIDs, window handles, swapchain addresses or authentication.
"""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import argparse,collections,csv,hashlib,json,math,statistics,struct

ROOT=Path(__file__).resolve().parents[2]
METRICS=('FrameTime','CPUBusy','CPUWait','GPUTime','GPUBusy','GPUWait','GPULatency')
THRESHOLDS=(16.7,25.0,33.3,50.0)


class Refused(ValueError):pass
def need(value,code):
    if not value:raise Refused(code)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path):return json.loads(path.read_bytes())
def finite(value):
    try:number=float(value)
    except (TypeError,ValueError):raise Refused('non_numeric_metric') from None
    need(math.isfinite(number),'non_finite_metric');return number


def quantile(values,probability):
    need(values and 0<=probability<=1,'invalid_quantile_input')
    values=sorted(values);position=(len(values)-1)*probability;lower=math.floor(position)
    upper=min(lower+1,len(values)-1)
    return values[lower]+(values[upper]-values[lower])*(position-lower)


def distribution(values):
    need(values,'empty_distribution')
    return dict(count=len(values),mean_ms=statistics.fmean(values),p50_ms=quantile(values,.5),
        p95_ms=quantile(values,.95),p99_ms=quantile(values,.99),max_ms=max(values))


def mean_fps(values):
    need(values and all(value>0 for value in values),'invalid_frame_duration')
    return 1000*len(values)/math.fsum(values)


def slow_tail(values,fraction=.01):
    need(0<fraction<=1 and values and all(value>0 for value in values),'invalid_tail_input')
    count=max(1,math.ceil(len(values)*fraction))
    tail=sorted(values,reverse=True)[:count]
    return dict(fraction=fraction,frame_count=count,mean_frame_time_ms=statistics.fmean(tail),
        fps=mean_fps(tail),selection='ceil(N*fraction) largest native frame intervals; whole frames, deterministic ties',
        formula='1000 / arithmetic_mean(selected_FrameTime_ms)',not_inverse_percentile=True)


def pearson(left,right):
    need(len(left)==len(right),'correlation_length_mismatch')
    if len(left)<2:return None
    mean_left,mean_right=statistics.fmean(left),statistics.fmean(right)
    x=[value-mean_left for value in left];y=[value-mean_right for value in right]
    denominator=math.sqrt(math.fsum(value*value for value in x)*math.fsum(value*value for value in y))
    return math.fsum(a*b for a,b in zip(x,y))/denominator if denominator else None


def summarize(frames):
    times=[row['FrameTime'] for row in frames]
    if not times:return dict(frames=0)
    return dict(frames=len(times),mean_fps=mean_fps(times),interval_sum_seconds=math.fsum(times)/1000,
        frame_time=distribution(times),over_ms={str(threshold):sum(value>threshold for value in times) for threshold in THRESHOLDS})


def frame_bins(frames,origin_ms,seconds,width):
    bins=[[] for _ in range(math.ceil(seconds/width))]
    for row in frames:
        elapsed=(row['CPUStartTime']-origin_ms)/1000
        need(0<=elapsed<seconds,'frame_timestamp_outside_requested_window')
        bins[math.floor(elapsed/width)].append(row)
    return [dict(start_second=index*width,end_second=min(seconds,(index+1)*width),**summarize(rows)) for index,rows in enumerate(bins)]


def read_frames(path,pid):
    need(path.stat().st_size<=64*1024*1024,'csv_over_64mib_budget')
    with path.open(encoding='utf-8-sig',newline='') as stream:
        reader=csv.DictReader(stream)
        need(set(('ProcessID','SwapChainAddress','CPUStartTime',*METRICS))<=set(reader.fieldnames or []),'required_v2_columns_missing')
        rows=list(reader)
    need(len(rows)>=3,'insufficient_raw_frames')
    need(all(int(row['ProcessID'])==pid for row in rows),'foreign_pid_in_csv')
    chains={row['SwapChainAddress'] for row in rows};need(len(chains)==1 and '' not in chains,'multiple_or_missing_swapchains')
    # Preserve the existing capture protocol's conservative first-row policy.
    # A positive first v2 interval is still discarded, not mislabeled invalid.
    first=dict(CPUStartTime=finite(rows[0]['CPUStartTime']),FrameTime=finite(rows[0]['FrameTime']))
    frames=[];previous=None
    for row in rows[1:]:
        parsed={key:finite(row[key]) for key in ('CPUStartTime',*METRICS)}
        need(parsed['FrameTime']>0 and all(parsed[key]>=0 for key in METRICS),'invalid_frame_metric')
        need(previous is None or parsed['CPUStartTime']>previous,'non_monotonic_frame_timestamp')
        previous=parsed['CPUStartTime'];parsed['PresentMode']=row.get('PresentMode','')
        parsed['SyncInterval']=row.get('SyncInterval','');frames.append(parsed)
    return rows,frames,first


def focus_summary(focus,pid,seconds,width,height):
    need(focus['target_pid']==pid,'focus_pid_mismatch')
    need(focus.get('all_game_foreground') is True and focus.get('validation',{}).get('valid') is True,'focus_helper_refused')
    samples=focus['samples'];need(len(samples)>=math.ceil(seconds)-1,'focus_sample_count_short')
    times=[finite(row['seconds']) for row in samples]
    need(all(a<b for a,b in zip(times,times[1:])),'focus_timestamps_not_monotonic')
    need(all(row['foreground_pid']==pid and row['foreground_hwnd']==focus['target_hwnd']
        and row.get('game_foreground') is True and row.get('foreground_iconic') is False
        and row.get('target_window_valid') is True and row.get('window_candidate_count')==1
        and row.get('target_client_width')==width and row.get('target_client_height')==height for row in samples),'focus_sample_identity_or_visibility_failed')
    duration=focus['observation_end_monotonic_seconds']-focus['observation_start_monotonic_seconds']
    gaps=[times[0],*[b-a for a,b in zip(times,times[1:])],duration-times[-1]]
    need(duration>=seconds-1.25 and min(gaps)>=0 and max(gaps)<=1.75,'focus_time_coverage_failed')
    return dict(samples=len(samples),duration_seconds=duration,first_sample_second=times[0],last_sample_second=times[-1],
        maximum_gap_seconds=max(gaps),all_observations_foreground=True,one_target_window=True,
        client_width=width,client_height=height,sampling_interval_seconds=1,
        continuous_foreground_proven=False,limitation='Once-per-second positive observations do not rule out changes between samples.')


def screenshot_summary(path,metadata,pid,width,height,created):
    need(metadata['capture_valid'] is True and metadata['ordinary_client_verified'] is True,'screenshot_helper_refused')
    need(metadata['process_created_utc']==created,'screenshot_process_generation_changed')
    raw=path.read_bytes();need(raw[:8]==b'\x89PNG\r\n\x1a\n' and raw[12:16]==b'IHDR','invalid_png_header')
    need(struct.unpack('>II',raw[16:24])==(width,height),'screenshot_png_size_changed')
    for key in ('before','after'):
        window=metadata[key]
        need(window['pid']==pid and window['foreground'] is True and window['visible'] is True
            and window['iconic'] is False and window['hung'] is False
            and (window['client_width'],window['client_height'])==(width,height),'screenshot_window_scope_changed')
        need(all(corner['owned'] is True and corner['pid']==pid for corner in window['corner_owners']),'screenshot_corner_owner_changed')
    return dict(png_sha256=sha(path),metadata_sha256=sha(path.with_suffix('.json')),
        started_utc=metadata['started_utc'],ended_utc=metadata['ended_utc'],width=width,height=height,
        foreground_nonminimized_verified=True)


def analyze(folder,screen_folder,visual=None):
    capture,focus,prior,identity=[load(folder/name) for name in ('capture.json','focus.json','analysis.json','identity_signature.json')]
    pid=capture['pid'];seconds=finite(capture['seconds']);delay=finite(capture['delay'])
    need(1<=seconds<=600 and delay>=0,'capture_duration_outside_budget')
    need(capture['read_only_etw'] is True and capture['tools'] is False and capture['script_injection'] is False
        and capture['account_operations']==0,'capture_scope_changed')
    need(identity['pid']==pid and identity['tools'] is False and identity['signature']=='Valid'
        and 'O=Intel Corporation' in identity['signer'],'collector_identity_or_signature_changed')
    csv_path=folder/'frames.csv';need(sha(csv_path)==capture['frame_csv_sha256'],'csv_hash_changed')
    raw,frames,first=read_frames(csv_path,pid)
    window=focus['target_window'];width,height=window['client_width'],window['client_height']
    focused=focus_summary(focus,pid,seconds,width,height)
    snapshots={}
    for side in ('before','after'):
        path=screen_folder/(capture['label']+'_'+side+'.png');metadata=load(path.with_suffix('.json'))
        snapshots[side]=screenshot_summary(path,metadata,pid,width,height,identity['created_utc'])
    before_end=datetime.fromisoformat(snapshots['before']['ended_utc'])
    after_start=datetime.fromisoformat(snapshots['after']['started_utc'])
    focus_start=datetime.fromtimestamp(focus['observation_start_unix_seconds'],timezone.utc)
    focus_end=datetime.fromtimestamp(focus['observation_end_unix_seconds'],timezone.utc)
    need(before_end<focus_start<focus_end<after_start,'screens_do_not_bracket_focus_window')
    need(visual is None or (visual['before_png_sha256']==snapshots['before']['png_sha256']
        and visual['after_png_sha256']==snapshots['after']['png_sha256']),'visual_review_images_changed')
    times=[row['FrameTime'] for row in frames];metrics={name:distribution([row[name] for row in frames]) for name in METRICS}
    need(prior['valid'] is True and len(prior['groups'])==1 and prior['groups'][0]['process_id']==pid,'prior_analysis_scope_changed')
    old=prior['groups'][0]
    need(old['raw_rows']==len(raw) and old['accepted_frame_rows']==len(frames) and old['discarded_first_row']==1,'independent_row_count_differs')
    need(abs(old['mean_fps']-mean_fps(times))<1e-8,'independent_mean_fps_differs')
    for key in METRICS:
        for statistic in ('mean_ms','p50_ms','p95_ms','p99_ms','max_ms'):
            need(abs(old['metrics'][key][statistic]-metrics[key][statistic])<1e-7,'independent_distribution_differs')
    cpu_errors=[abs(row['FrameTime']-row['CPUBusy']-row['CPUWait']) for row in frames]
    interval_errors=[abs(right['CPUStartTime']-left['CPUStartTime']-left['FrameTime']) for left,right in zip(frames,frames[1:])]
    by_slow={}
    for label,predicate in [('over_25ms',lambda row:row['FrameTime']>25),('at_most_25ms',lambda row:row['FrameTime']<=25)]:
        selected=[row for row in frames if predicate(row)]
        by_slow[label]=dict(frames=len(selected),means_ms={key:statistics.fmean(row[key] for row in selected) for key in METRICS}) if selected else dict(frames=0)
    result=dict(schema=1,status='INDEPENDENT_NATIVE_OPENING_CAPTURE_ANALYSIS_PASS',capture_label=capture['label'],
        requested_seconds=seconds,delay_seconds=delay,read_only=True,tools=False,real_account_operations=0,script_injection=False,
        source_sha256={name:sha(folder/name) for name in ('frames.csv','capture.json','analysis.json','focus.json','identity_signature.json')},
        scope=dict(clients_observed=1,width=width,height=height,single_pid=True,single_swapchain=True,
            scenario='ordinary Workshop3102 pre-wave opening, as recorded by operator and manually reviewed screenshots',
            native_frame_metrics=True,os_cpu_gpu_utilization_measured=False),
        first_row_policy=dict(discarded_rows=1,raw_first_interval_positive=first['FrameTime']>0,
            reason='Conservative existing capture protocol; positive first v2 interval is not claimed invalid'),
        raw_frames=len(raw),accepted_frames=len(frames),**summarize(frames),metrics=metrics,
        native_slowest_one_percent=slow_tail(times),focus=focused,screenshots=snapshots,visual_review=visual,
        timing=dict(capture_started_utc=capture['started_utc'],focus_started_utc=focus_start.isoformat(),focus_ended_utc=focus_end.isoformat(),
            screenshot_bracket_seconds=(after_start-before_end).total_seconds(),
            focus_after_capture_start_seconds=(focus_start-datetime.fromisoformat(capture['started_utc'])).total_seconds(),
            first_accepted_cpu_start_ms=frames[0]['CPUStartTime'],last_accepted_cpu_start_ms=frames[-1]['CPUStartTime'],
            accepted_timestamp_span_seconds=(frames[-1]['CPUStartTime']-frames[0]['CPUStartTime'])/1000,
            absolute_etw_wall_clock_alignment_certified=False),
        consistency=dict(prior_independent_analysis_matches=True,frame_time_cpu_busy_plus_wait_max_error_ms=max(cpu_errors),
            cpu_start_next_interval_max_error_ms=max(interval_errors)),
        frame_time_correlations={name:pearson(times,[row[name] for row in frames]) for name in METRICS if name!='FrameTime'},
        frame_groups=by_slow,present_modes=dict(collections.Counter(row['PresentMode'] for row in frames)),
        sync_intervals=dict(collections.Counter(row['SyncInterval'] for row in frames)),
        per_second=frame_bins(frames,delay*1000,seconds,1),per_five_seconds=frame_bins(frames,delay*1000,seconds,5),
        per_minute=frame_bins(frames,delay*1000,seconds,60),
        slowest_ten_frames=[dict(second=(row['CPUStartTime']-delay*1000)/1000,**{key:row[key] for key in METRICS})
            for row in sorted(frames,key=lambda row:row['FrameTime'],reverse=True)[:10]],
        limits=[f'One local{width}x{height} client and one{seconds:g}s pre-wave sample; no battle, multiplayer or cross-machine comparison.',
            '1%low is inverse mean duration of ceil(N*.01) slowest whole native frame intervals, not inverseP99.',
            'FrameTime=CPUBusy+CPUWait creates definitional correlation; these are ETW durations, not thread attribution or OS utilization.',
            'CPU/GPU association alone cannot identify portrait worlds, prewarming, shaders or Lua as a cause.',
            'Focus is sampled1Hz; two screenshots bracket running countdown progress, not continuous proof of no intervening pause.',
            'No evidence here establishes that188portrait worlds exist or cause the observed long frames.'])
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-dir',type=Path,required=True)
    parser.add_argument('--screens-dir',type=Path)
    parser.add_argument('--visual-review',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();need(args.output.resolve().is_relative_to(ROOT),'output_outside_workspace')
    need(not args.output.exists(),'new_analysis_output_required')
    result=analyze(args.capture_dir,args.screens_dir or args.capture_dir.parent/'screens',load(args.visual_review) if args.visual_review else None)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf8',newline='\n') as stream:json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps(dict(status=result['status'],frames=result['accepted_frames'],mean_fps=result['mean_fps'],
        p95_ms=result['frame_time']['p95_ms'],p99_ms=result['frame_time']['p99_ms'],
        slowest_one_percent_fps=result['native_slowest_one_percent']['fps'],over_ms=result['over_ms'])))


if __name__=='__main__':main()
