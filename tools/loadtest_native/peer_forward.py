"""Fixed one/four restricted peer forwards; O(F) startup, sample and close, F<=4.
Each actor uses the existing O(1) round-robin URL; no actor/process scans.
Only loopback listeners; every SSH targets the same authorized127.0.0.1:29567.
No SSH configuration mutation, multiplexing, connection retry or private export.
"""
from __future__ import annotations
import argparse,ctypes,hashlib,json,os,resource,signal,socket,subprocess,sys,time
from pathlib import Path
import psutil
ROOT=Path('/srv/survival-loadtest/peer_link_20261117_01')
KNOWN_SHA='d4e89ab46b72c540527f4895ef13aba42444c486025007c7b9b6771ac38ceb6b'
def need(v,c):
    if not v:raise ValueError(c)
def read_spec(path,digest):
    path=Path(path);need(path.is_relative_to('/srv/survival-loadtest')and hashlib.sha256(path.read_bytes()).hexdigest()==digest,'peer_spec_invalid');spec=json.loads(path.read_bytes())
    need(spec.get('execution_mode')=='linux-peer-ssh-v1'and spec['generator_host']=='47.116.11.179'and spec['backend_host']=='47.111.16.128','peer_identity_invalid')
    need(hashlib.sha256((ROOT/'known_hosts').read_bytes()).hexdigest()==KNOWN_SHA,'peer_known_hosts_changed')
    need((ROOT/'id_ed25519').is_file()and (ROOT/'id_ed25519').stat().st_mode&0o077==0,'peer_private_file_permissions_invalid')
    return spec
def ports(spec):
    value=spec.get('peer_forward_ports',[29567]);need(type(value)is list and all(type(port)is int for port in value)and value in([29567],list(range(29567,29571))),'peer_ports_invalid');return tuple(value)

def argv(port=29567):
    return ['/usr/bin/ssh','-F','/dev/null','-T','-N','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','HostKeyAlgorithms=ssh-ed25519','-o','UserKnownHostsFile='+str(ROOT/'known_hosts'),'-o','ConnectTimeout=10','-o','ServerAliveInterval=10','-o','ServerAliveCountMax=2','-o','ExitOnForwardFailure=yes','-o','Compression=no','-o','ControlMaster=no','-i',str(ROOT/'id_ed25519'),'-L','127.0.0.1:'+str(port)+':127.0.0.1:29567','root@47.111.16.128']
class _Forward:
    def __init__(self,spec,digest,stage,port):self.port=port;self.spec=Path(spec);self.digest=digest;self.stage=stage;self.proc=self.handle=None;self.identity=None;self.forced=False;self.exit_code=None;self.final=None
    def start(self):
        need(self.port in ports(read_spec(self.spec,self.digest)),'peer_port_not_bound')
        with socket.socket()as s:
            s.settimeout(.2);need(s.connect_ex(('127.0.0.1',self.port))!=0,'peer_forward_port_already_used')
        with(self.stage/('peer_forward_'+str(self.port)+'_stderr.log')).open('xb')as out:self.proc=subprocess.Popen([sys.executable,'-B',str(Path(__file__)),'--exec-forward','--spec',str(self.spec),'--spec-sha256',self.digest,'--local-port',str(self.port),'--parent-pid',str(os.getpid())],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=out,start_new_session=True)
        self.handle=psutil.Process(self.proc.pid);self.identity=self.handle.create_time();self.handle.cpu_percent(None)
        until=time.monotonic()+15
        while True:
            self.require_alive()
            with socket.socket()as s:
                s.settimeout(.2)
                if s.connect_ex(('127.0.0.1',self.port))==0:break
            need(time.monotonic()<until,'peer_forward_start_timeout');time.sleep(.1)
        need(self.handle.exe()=='/usr/bin/ssh'and self.handle.cmdline()==argv(self.port),'peer_forward_exec_identity_invalid')
    def require_alive(self):need(self.proc is not None and self.proc.poll()is None and self.handle.create_time()==self.identity,'peer_forward_lost')
    def sample(self):
        alive=self.proc is not None and self.proc.poll()is None
        row={'role':'data_ssh_tunnel','pid':None if self.proc is None else self.proc.pid,'running':alive,'create_time':self.identity,'local_port':self.port}
        if alive:
            self.require_alive();row.update(cpu_percent_one_core_scale=self.handle.cpu_percent(None),rss_bytes=self.handle.memory_info().rss,num_fds=self.handle.num_fds())
        return row
    def closed(self):return self.proc is None or self.proc.poll()is not None
    def close(self):
        if not self.closed():
            self.final=self.sample();self.require_alive();self.proc.terminate()
            try:self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:self.require_alive();self.forced=True;self.proc.kill();self.proc.wait(timeout=10)
        if self.proc is not None:self.exit_code=self.proc.returncode
        need(self.closed(),'peer_forward_cleanup_incomplete')
    def receipt(self):return {'kind':'EXACT_OWNED_RESTRICTED_LINUX_PEER_FORWARD','known_host_sha256':KNOWN_SHA,'backend_host':'47.111.16.128','local_bind':'127.0.0.1:'+str(self.port),'target_bind':'127.0.0.1:29567','data_ssh_processes':1,'pid':None if self.proc is None else self.proc.pid,'create_time':self.identity,'closed':self.closed(),'forced_kill':self.forced,'exit_code':self.exit_code,'final_sample':self.final,'private_key_exported':False,'new_authorization_mutations_by_this_controller':0}
class PeerForward:
    def __init__(self,spec,digest,stage):
        value=read_spec(spec,digest);self.ports=ports(value)
        self.children=[_Forward(spec,digest,stage,port)for port in self.ports]
    def start(self):
        try:
            for child in self.children:child.start()
        except BaseException:
            self.close();raise
    def require_alive(self):
        for child in self.children:child.require_alive()
    def sample(self):return [child.sample()for child in self.children]
    def closed(self):return all(child.closed()for child in self.children)
    def close(self):
        failures=[]
        for child in reversed(self.children):
            try:child.close()
            except Exception as exc:failures.append(type(exc).__name__)
        need(not failures and self.closed(),'peer_group_cleanup_incomplete')
    def receipt(self):
        rows=[child.receipt()for child in self.children]
        return {'kind':'EXACT_OWNED_RESTRICTED_LINUX_PEER_FORWARD_GROUP','known_host_sha256':KNOWN_SHA,'backend_host':'47.111.16.128','local_ports':list(self.ports),'target_bind':'127.0.0.1:29567','data_ssh_processes':len(rows),'forwards':rows,'closed':self.closed(),'forced_kill':any(row['forced_kill']for row in rows),'private_key_exported':False,'new_authorization_mutations_by_this_controller':0}

def main():
    p=argparse.ArgumentParser();p.add_argument('--exec-forward',action='store_true',required=True);p.add_argument('--spec',required=True);p.add_argument('--spec-sha256',required=True);p.add_argument('--local-port',type=int,required=True);p.add_argument('--parent-pid',type=int,required=True);a=p.parse_args();spec=read_spec(a.spec,a.spec_sha256);need(a.local_port in ports(spec),'peer_port_not_bound')
    parent=a.parent_pid;need(os.getppid()==parent and parent>1,'peer_parent_identity_lost');libc=ctypes.CDLL(None,use_errno=True);need(libc.prctl(1,signal.SIGTERM,0,0,0)==0 and os.getppid()==parent,'peer_parent_death_setup_failed');soft,hard=resource.getrlimit(resource.RLIMIT_NOFILE);target=min(hard,65535)if hard!=resource.RLIM_INFINITY else 65535;need(target>=16384,'peer_forward_fd_limit_insufficient');resource.setrlimit(resource.RLIMIT_NOFILE,(target,hard));os.execv('/usr/bin/ssh',argv(a.local_port))
if __name__=='__main__':main()
