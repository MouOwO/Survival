"""Generator-only pure decoding workers;original WireClient,HTTP and SQL unchanged.
Cold O(W*schema),W=2. Each reply O(B) private Unix IPC+original decoder.
Pending<=32;all PID samples O(W). No actor scan,authority cache or request retry.
The caller owns its counters and cache;only pure parsed results cross this socket.
"""
from __future__ import annotations
import argparse,ctypes,hashlib,io,json,os,pickle,re,signal,socket,struct,subprocess,sys,threading,time
from pathlib import Path
MAX_FRAME=32*1024*1024

def need(v,c):
    if not v:raise ValueError(c)
def packet(value):
    raw=pickle.dumps(value,protocol=5);need(len(raw)<=MAX_FRAME,'decode_IPC_frame_budget');return struct.pack('!I',len(raw))+raw
def read_exact(sock,n):
    parts=[];left=n
    while left:
        value=sock.recv(left);need(value,'decode_IPC_EOF');parts.append(value);left-=len(value)
    return b''.join(parts)
def receive(sock):
    n=struct.unpack('!I',read_exact(sock,4))[0];need(0<n<=MAX_FRAME,'decode_IPC_frame_budget');return data_only(read_exact(sock,n))
class DataOnlyUnpickler(pickle.Unpickler):
    def find_class(self,module,name):raise ValueError('decode_IPC_globals_forbidden')
    def persistent_load(self,pid):raise ValueError('decode_IPC_persistent_objects_forbidden')
def data_only(raw):
    stream=io.BytesIO(raw);value=DataOnlyUnpickler(stream).load();need(stream.read(1)==b'','decode_IPC_trailing_data');return value
def _decode(job):
    from loadtest_lab.wire_client import WireClient
    wire=WireClient(job['mode'],measure_routes=job['routes']);ctx=job['context'];error=None;value=None
    try:value=wire.decode(job['method'],job['path'],job['raw'],job['status'],request_body=job['request_body'],profile_context=ctx)
    except Exception as e:error=str(e)if isinstance(e,ValueError)and re.fullmatch('[a-zA-Z0-9_]{1,100}',str(e))else'loadtest_remote_decode_failed'
    updates=None if ctx is None else{k:ctx[k]for k in ('next_state','kind')if k in ctx}
    if ctx is not None and ctx.get('next_state')is not None and ctx.get('next_state')is ctx.get('baseline'):
        updates.pop('next_state');updates['reuse_baseline']=True
    return {'ok':error is None,'error':error,'value':value,'context':updates,'report':wire.report()}

def install(wire,path):
    """Original validation in native children;atomic counter merge,one pure fallback."""
    from loadtest_lab import wire_client as wc
    original=wire.decode;counts={'calls':0,'worker_used':0,'fallback':0,'remote_errors':0}
    def decode(method,route,raw,status=200,*,request_body=None,profile_context=None):
        import socket
        counts['calls']+=1;began=time.perf_counter_ns()
        try:
            job={'mode':wire.mode,'routes':wire._routes is not None,'method':method,'path':route,'raw':raw,'status':status,'request_body':request_body,'context':profile_context}
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)as sock:
                sock.settimeout(20);sock.connect(path);sock.sendall(packet(job));v=receive(sock)
            r=v['report'];c=r['counters'];need(set(c)==set(wire._counts)and all(type(x)is int and x>=0 for x in c.values()),'decode_IPC_counters_invalid')
            need(c['requests']==c['business_requests']==c['control_requests']==c['negotiated_requests']==0 and c['responses']==1 and c['response_body_bytes']==len(raw),'decode_IPC_counter_scope_invalid')
            need(type(v['ok'])is bool and(v['ok']or type(v['error'])is str and re.fullmatch('[a-zA-Z0-9_]{1,100}',v['error'])),'decode_IPC_result_invalid')
            cache=r.get('profile_cache_v1');need(cache is None or set(cache)==set(wire._cache_stats)and all(type(x)is int and x>=0 for x in cache.values()),'decode_IPC_cache_counters_invalid')
            delta=None;target=None
            if wire._routes is not None:
                rows=r['route_bytes_v1']['rows'];need(len(rows)==1,'decode_IPC_route_invalid');delta=rows[0];target=wire._routes.row(method,route)
                need(set(delta)==set(target)and delta['id']==target['id']and delta['requests']==0,'decode_IPC_route_invalid')
                need(all(type(delta[k])is int and delta[k]>=0 for k in wc._ROUTE_SUM_FIELDS+wc._ROUTE_MAX_FIELDS)and len(delta['body_histogram'])==len(target['body_histogram'])and all(type(x)is int and x>=0 for x in delta['body_histogram']),'decode_IPC_route_invalid')
        except Exception:
            counts['fallback']+=1
            return original(method,route,raw,status,request_body=request_body,profile_context=profile_context)
        elapsed=time.perf_counter_ns()-began;c['decode_wall_ns']=c['max_decode_wall_ns']=elapsed
        for key,value in c.items():wire._counts[key]=max(wire._counts[key],value)if key=='max_decode_wall_ns'else wire._counts[key]+value
        if cache is not None:
            for key,value in cache.items():wire._cache_stats[key]+=value
        if delta is not None:
            delta['decode_wall_ns']=delta['max_decode_wall_ns']=elapsed
            for key in wc._ROUTE_SUM_FIELDS:target[key]+=delta[key]
            for key in wc._ROUTE_MAX_FIELDS:target[key]=max(target[key],delta[key])
            for i,value in enumerate(delta['body_histogram']):target['body_histogram'][i]+=value
        if profile_context is not None and type(v['context'])is dict:
            if v['context'].get('reuse_baseline')is True:
                need(type(profile_context.get('baseline'))is dict and v['context'].get('kind')=='unchanged','decode_IPC_baseline_invalid');profile_context['next_state']=profile_context['baseline']
            for key in ('next_state','kind'):
                if key in v['context']:profile_context[key]=v['context'][key]
        counts['worker_used']+=1
        if not v['ok']:counts['remote_errors']+=1;raise ValueError(v['error'])
        return v['value']
    wire.decode=decode;wire._decode_offload_snapshot=lambda:dict(counts,mode='original-WireClient-private-Unix-process2-data-v2',HTTP_replays=0,pure_fallback_only=True)

class Decoder:
    def __init__(self,spec,digest,stage):self.spec=Path(spec);self.digest=digest;self.stage=stage;self.proc=None;self.handles={};self.ready=None;self.terminal=None;self.forced=False;self.path=None
    def start(self):
        import psutil
        cfg=json.loads(self.spec.read_bytes());self.root=Path('/srv/survival-loadtest/dc_'+cfg['run_id'][:12]);need(not self.root.exists(),'fresh_decode_root_required');self.root.mkdir(mode=0o700);self.path=str(self.root/'d.sock')
        with(self.stage/'decode_service_stdout.log').open('xb')as out:self.proc=subprocess.Popen([sys.executable,'-B',str(Path(__file__)),'--serve','--spec',str(self.spec),'--spec-sha256',self.digest,'--socket',self.path,'--stage',str(self.stage)],stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
        until=time.monotonic()+20;ready=self.stage/'decode_service_ready_receipt.json'
        while not ready.exists():need(self.proc.poll()is None and time.monotonic()<until,'decode_service_start_failed');time.sleep(.1)
        self.ready=json.loads(ready.read_bytes());ids=[{'pid':self.proc.pid,'role':'decode_service'}]+[{'pid':x['pid'],'role':'decode_worker'}for x in self.ready['lifecycle']['worker_identities']]
        for x in ids:
            handle=psutil.Process(x['pid']);self.handles[x['pid']]=(x['role'],handle,handle.create_time());handle.cpu_percent(None)
    def sample(self):
        rows=[]
        for pid,(role,handle,born)in self.handles.items():
            try:alive=handle.is_running()and handle.create_time()==born and handle.status()!='zombie'
            except Exception:alive=False
            row={'role':role,'pid':pid,'running':alive,'create_time':born}
            if alive:row.update(cpu_percent_one_core_scale=handle.cpu_percent(None),rss_bytes=handle.memory_info().rss)
            rows.append(row)
        return rows
    def require_alive(self):need(self.proc is not None and self.proc.poll()is None,'decode_service_lost')
    def closed(self):return self.proc is None or self.proc.poll()is not None
    def close(self):
        if not self.closed():
            self.require_alive();self.proc.terminate()
            try:self.proc.wait(timeout=35)
            except subprocess.TimeoutExpired:self.forced=True;self.proc.kill();self.proc.wait(timeout=10)
        p=self.stage/'decode_service_terminal_receipt.json'
        if p.exists():self.terminal=json.loads(p.read_bytes())
        need(self.closed()and self.terminal is not None and self.terminal['lifecycle']['closed']is True and self.terminal['lifecycle']['pending']==0 and self.terminal['lifecycle']['forced_workers']==0,'decode_service_cleanup_incomplete')
    def receipt(self):return {'kind':'EXACT_OWNED_GENERATOR_DECODE_SERVICE','socket':self.path,'ready':self.ready,'terminal':self.terminal,'closed':self.closed(),'forced_kill':self.forced,'generator_host':'47.116.11.179','backend_host_cost_excludes_decode':True}

def serve(args):
    import native_stage_proof as proof
    need(hashlib.sha256(Path(args.spec).read_bytes()).hexdigest()==args.spec_sha256,'decode_spec_changed');spec=json.loads(Path(args.spec).read_bytes());proof.configure(Path('/srv/survival-loadtest')/spec['run_id']);need(spec['client_decode_processes']==2,'decode_process_budget_invalid')
    parent=os.getppid();libc=ctypes.CDLL(None,use_errno=True);need(libc.prctl(1,signal.SIGTERM,0,0,0)==0 and os.getppid()==parent,'decode_parent_guard_failed')
    from player_web_auth.response_pool import ResponseEncoderPool
    from socketserver import ThreadingMixIn,UnixStreamServer,BaseRequestHandler
    pool=ResponseEncoderPool(workers=2,pending=16);slots=threading.BoundedSemaphore(32);stats={'requests':0,'completed':0,'errors':0};lock=threading.Lock();stage=Path(args.stage)
    class Handler(BaseRequestHandler):
        def handle(self):
            try:
                self.request.settimeout(20);job=receive(self.request)
                with lock:stats['requests']+=1
                need(pool._slots.acquire(timeout=2),'decode_worker_pending_full')
                with pool._lock:
                    future=pool._executor.submit(_decode,job);pool._pending[id(future)]=future;pool._counts['submitted']+=1;pool._counts['peak_pending']=max(pool._counts['peak_pending'],len(pool._pending))
                future.add_done_callback(pool._finished);value=future.result(timeout=18);self.request.sendall(packet(value))
                with lock:stats['completed']+=1
            except Exception:
                with lock:stats['errors']+=1
            finally:slots.release()
    class Server(ThreadingMixIn,UnixStreamServer):
        daemon_threads=True;request_queue_size=32
        def process_request(self,request,address):
            if not slots.acquire(timeout=2):self.shutdown_request(request);return
            try:super().process_request(request,address)
            except BaseException:slots.release();raise
    server=Server(args.socket,Handler);os.chmod(args.socket,0o600)
    ready={'kind':'PURE_ORIGINAL_DECODER_SERVICE_READY','pid':os.getpid(),'run_id':spec['run_id'],'lifecycle':pool.snapshot(),'server_business_requests':0,'private_IPC':'restricted-data-only-pickle5-v2'}
    with(stage/'decode_service_ready_receipt.json').open('x')as f:json.dump(ready,f)
    def stop(signum,frame):threading.Thread(target=server.shutdown,daemon=True).start()
    signal.signal(signal.SIGTERM,stop)
    try:server.serve_forever(poll_interval=.2)
    finally:
        server.server_close();pool.close(deadline=time.monotonic()+25);value={'kind':'PURE_ORIGINAL_DECODER_SERVICE_TERMINAL','run_id':spec['run_id'],'stats':stats,'lifecycle':pool.snapshot(),'business_HTTP_replays':0}
        with(stage/'decode_service_terminal_receipt.json').open('x')as f:json.dump(value,f)
        try:Path(args.socket).unlink()
        except FileNotFoundError:pass

def main():
    p=argparse.ArgumentParser();p.add_argument('--serve',action='store_true',required=True);p.add_argument('--spec',required=True);p.add_argument('--spec-sha256',required=True);p.add_argument('--socket',required=True);p.add_argument('--stage',required=True);serve(p.parse_args())
if __name__=='__main__':main()
