"""Bounded pure response encoding in fresh processes;no business/RPC replay.

Cold: W<=12 spawned workers import the immutable codec once,O(W*schema).
Each response: O(B) IPC plus exactly the original codec work,one fixed slot
and one future;pending<=48. No account index,DB/network call or periodic scan.
Small/large bodies,overload and worker faults retain the original inline path.
Close visits only W fixed children and <=48 futures under a real deadline.
"""
from __future__ import annotations
import hashlib
import os
import sys
from pathlib import Path
import threading
import time

_GATE=None

def _worker_init(ready,gate,parent_pid):
    global _GATE
    import ctypes,signal
    if os.getppid()!=parent_pid:os._exit(2)
    libc=ctypes.CDLL(None,use_errno=True)
    libc.prctl.argtypes=(ctypes.c_int,ctypes.c_ulong,ctypes.c_ulong,ctypes.c_ulong,ctypes.c_ulong)
    libc.prctl.restype=ctypes.c_int
    signal.signal(signal.SIGTERM,signal.SIG_DFL)
    if libc.prctl(1,signal.SIGTERM,0,0,0)!=0:raise RuntimeError('response_encoder_parent_guard_failed')
    if os.getppid()!=parent_pid:os._exit(2)
    from . import business_wire as codec
    _GATE=gate
    ready.put({'pid':os.getpid(),'codec_sha256':hashlib.sha256(Path(codec.__file__).read_bytes()).hexdigest()})

def _warm_worker():
    if not _GATE.wait(12):raise RuntimeError('response_encoder_warmup_deadline')
    return os.getpid()

def _encode_job(kind,body,value,advertised,deadline):
    from .business_wire import _pack_decoded_bytes,pack_bytes
    if time.monotonic()>=deadline:return False,None
    return True,(_pack_decoded_bytes(body,value,advertised)if kind=='decoded'else pack_bytes(body,advertised))

def _process_identity(pid):
    p=Path('/proc')/str(pid)/'stat'
    raw=p.read_text();parts=raw[raw.rfind(')')+2:].split()
    return {'pid':pid,'starttime_ticks':int(parts[19])}

class ResponseEncoderPool:
    MIN_BODY=2048
    MAX_BODY=256*1024
    def __init__(self,*,workers=3,pending=24,wait_seconds=2):
        if (not sys.platform.startswith('linux') or type(workers)is not int or workers not in(2,3,6,12)
                or type(pending)is not int or pending!=workers*8
                or type(wait_seconds)not in(int,float)or wait_seconds!=2):
            raise ValueError('response_encoder_configuration_invalid')
        from concurrent.futures import ProcessPoolExecutor
        import multiprocessing as mp
        self._workers=workers;self._maximum=pending;self._wait=float(wait_seconds)
        self._lock=threading.RLock();self._slots=threading.BoundedSemaphore(pending)
        self._pending={};self._closed=False;self._module=None;self._originals=None
        self._children=();self._identities=[];self._tracker=None;self._forced=0;self._pidfds={};self._exit_confirmed=[];self._manager_joined=False
        self._counts=dict(submitted=0,completed=0,failed=0,cancelled=0,
                          inline=0,fallback=0,peak_pending=0,timeout=0,worker_results_used=0)
        context=mp.get_context('spawn');ready=context.Queue(maxsize=workers);gate=context.Event()
        self._executor=ProcessPoolExecutor(max_workers=workers,mp_context=context,
                                          initializer=_worker_init,initargs=(ready,gate,os.getpid()))
        try:
            warm=[self._executor.submit(_warm_worker)for _ in range(workers)]
            self._capture_children()
            deadline=time.monotonic()+12;records=[ready.get(timeout=max(.01,deadline-time.monotonic()))for _ in range(workers)]
            from . import business_wire as codec
            expected=hashlib.sha256(Path(codec.__file__).read_bytes()).hexdigest()
            if len({r['pid']for r in records})!=workers or any(r['codec_sha256']!=expected for r in records):
                raise RuntimeError('response_encoder_child_source_mismatch')
            # Startup-only bounded identities;never scan a process tree per reply.
            if len(self._children)!=workers or {p.pid for p in self._children}!={r['pid']for r in records}:
                raise RuntimeError('response_encoder_child_ownership_mismatch')
            from multiprocessing import resource_tracker
            if resource_tracker._resource_tracker._pid:self._tracker=_process_identity(resource_tracker._resource_tracker._pid)
            gate.set()
            if {f.result(timeout=max(.01,deadline-time.monotonic()))for f in warm}!={r['pid']for r in records}:
                raise RuntimeError('response_encoder_warmup_mismatch')
        except BaseException:
            gate.set()
            try:self._capture_children()
            except Exception:pass
            self.close(deadline=time.monotonic()+2)
            raise
        finally:
            ready.close();ready.join_thread()

    def _capture_children(self):
        children=tuple(self._executor._processes.values())if self._executor._processes else()
        if not self._children:self._children=children
        for child in children:
            if child.pid in self._pidfds:continue
            before=_process_identity(child.pid);fd=os.pidfd_open(child.pid,0)
            try:
                if _process_identity(child.pid)!=before:raise RuntimeError('response_encoder_identity_changed')
                self._pidfds[child.pid]=fd;self._identities.append(before)
            except BaseException:os.close(fd);raise

    def install(self,module):
        with self._lock:
            if self._closed or self._module is not None or getattr(module,'_response_encoder_owner',None)is not None:
                raise ValueError('response_encoder_installation_invalid')
            self._module=module;self._originals=(module._pack_decoded_bytes,module.pack_bytes)
            module._response_encoder_owner=self
            module._pack_decoded_bytes=self.pack_decoded_bytes;module.pack_bytes=self.pack_bytes

    def _inline(self,kind,body,value,advertised,*,fallback=False):
        with self._lock:
            self._counts['inline']+=1
            self._counts['fallback']+=int(fallback)
            original=self._originals[0 if kind=='decoded'else 1]if self._originals else None
        if original is None:
            from .business_wire import _pack_decoded_bytes,pack_bytes
            original=_pack_decoded_bytes if kind=='decoded'else pack_bytes
        return original(body,value,advertised)if kind=='decoded'else original(body,advertised)

    def _finished(self,future):
        with self._lock:
            if self._pending.pop(id(future),None)is None:return
            self._counts['cancelled'if future.cancelled()else'failed'if future.exception()is not None else'completed']+=1
        self._slots.release()

    def _transform(self,kind,body,value,advertised):
        from .business_wire import SCHEMA_HASH
        if type(body)is not bytes or not self.MIN_BODY<=len(body)<=self.MAX_BODY or advertised not in (SCHEMA_HASH,SCHEMA_HASH+";b2"):
            return self._inline(kind,body,value,advertised)
        deadline=time.monotonic()+self._wait
        if not self._slots.acquire(timeout=self._wait):return self._inline(kind,body,value,advertised,fallback=True)
        future=None
        try:
            with self._lock:
                if self._closed:raise RuntimeError('response_encoder_closed')
                future=self._executor.submit(_encode_job,kind,body,value,advertised,deadline)
                self._pending[id(future)]=future;self._counts['submitted']+=1
                self._counts['peak_pending']=max(self._counts['peak_pending'],len(self._pending))
            # Callback owns slot release even after a caller's timeout. Pending
            # never exceeds the declared cap while background work completes.
            future.add_done_callback(self._finished)
            used,result=future.result(timeout=max(.001,deadline-time.monotonic()))
            if used is not True:
                from concurrent.futures import TimeoutError
                raise TimeoutError('response_encoder_worker_deadline')
            if type(result)is not bytes or len(result)>8*1024*1024:raise RuntimeError('response_encoder_result_invalid')
            with self._lock:self._counts['worker_results_used']+=1
            return result
        except BaseException as exc:
            if future is None:self._slots.release()
            from concurrent.futures import TimeoutError
            with self._lock:self._counts['timeout']+=int(isinstance(exc,TimeoutError))
            if not isinstance(exc,Exception):raise
            return self._inline(kind,body,value,advertised,fallback=True)

    def pack_decoded_bytes(self,body,value,advertised):return self._transform('decoded',body,value,advertised)
    def pack_bytes(self,body,advertised):return self._transform('plain',body,None,advertised)

    def snapshot(self):
        with self._lock:return {'kind':'PURE_RESPONSE_ENCODER_POOL_V1','workers':self._workers,'max_pending':self._maximum,
            'wait_seconds':self._wait,'min_body_bytes':self.MIN_BODY,'max_body_bytes':self.MAX_BODY,
            'pending':len(self._pending),'closed':self._closed,'forced_workers':self._forced,
            'worker_identities':list(self._identities),'resource_tracker_identity':self._tracker,
            'worker_exit_confirmed':list(self._exit_confirmed),'manager_joined':self._manager_joined,
            'business_or_RPC_calls_added':0,**self._counts}

    def close(self,*,deadline=None):
        deadline=time.monotonic()+5 if deadline is None else deadline
        with self._lock:
            if self._closed:return
            self._closed=True
            module=self._module
            if module is not None and getattr(module,'_response_encoder_owner',None)is self:
                module._pack_decoded_bytes,module.pack_bytes=self._originals
                del module._response_encoder_owner
        import select,signal
        manager=self._executor._executor_manager_thread
        self._executor.shutdown(wait=False,cancel_futures=True)
        for fd in self._pidfds.values():
            if not select.select([fd],[],[],max(0,deadline-time.monotonic()))[0]:
                signal.pidfd_send_signal(fd,signal.SIGTERM);self._forced+=1
        confirmed=[]
        for fd in self._pidfds.values():
            gone=bool(select.select([fd],[],[],1)[0])
            if not gone:
                signal.pidfd_send_signal(fd,signal.SIGKILL)
                gone=bool(select.select([fd],[],[],1)[0])
            confirmed.append(gone);os.close(fd)
        self._pidfds={};self._exit_confirmed=confirmed
        if manager is not None:manager.join(timeout=max(0,deadline-time.monotonic()))
        self._manager_joined=manager is None or not manager.is_alive()
