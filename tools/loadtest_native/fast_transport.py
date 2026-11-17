"""Generator-only bounded FastHTTP adapter. No automatic POST replay.
One client per synthetic actor;one request in flight. O(body bytes) JSON encoding,
constant timeout/headers state,no actor scans or new business calls.
"""
from __future__ import annotations
from locust import FastHttpUser
import gevent,json,math,socket

def install_budget(session):
    original=session.request
    def request(method,url,*args,**kwargs):
        timeout=kwargs.pop('timeout',35)
        if type(timeout)not in(int,float)or not math.isfinite(timeout)or not 0<timeout<=35:raise ValueError('loadtest_fast_timeout_invalid')
        if kwargs.get('max_retries',0)!=0:raise ValueError('loadtest_automatic_replay_forbidden')
        kwargs['max_retries']=0;kwargs['allow_redirects']=False
        body=kwargs.pop('json',None)
        if not kwargs.get('data')and body is not None:
            raw=json.dumps(body,allow_nan=False).encode('utf8');kwargs['data']=raw;headers=dict(kwargs.get('headers')or{});headers.setdefault('Content-Type','application/json');headers.setdefault('Accept','*/*');kwargs['headers']=headers
        with gevent.Timeout(float(timeout),socket.timeout('loadtest_fast_network_timeout')):
            return original(method,url,*args,**kwargs)
    session.request=request
class BudgetFastHttpUser(FastHttpUser):
    abstract=True;network_timeout=35;connection_timeout=35;max_retries=0;max_redirects=0;concurrency=1;insecure=False
    def __init__(self,environment):
        super().__init__(environment);install_budget(self.client)
