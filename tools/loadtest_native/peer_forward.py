"""One indexed,restricted Linux peer forward. O(1) startup and each5s sample.
No process/actor discovery, SSH multiplexing, SSH configuration mutation or retry.
The parent owns one exact PID; its exec child retains PID and parent-death signal.
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
def argv():
    return ['/usr/bin/ssh','-F','/dev/null','-T','-N','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','HostKeyAlgorithms=ssh-ed25519','-o','UserKnownHostsFile='+str(ROOT/'known_hosts'),'-o','ConnectTimeout=10','-o','ServerAliveInterval=10','-o','ServerAliveCountMax=2','-o','ExitOnForwardFailure=yes','-o','Compression=no','-o','ControlMaster=no','-i',str(ROOT/'id_ed25519'),'-L','127.0.0.1:29567:127.0.0.1:29567','root@47.111.16.128']
class PeerForward:
    def __init__(self,spec,digest,stage):self.spec=Path(spec);self.digest=digest;self.stage=stage;self.proc=self.handle=None;self.identity=None;self.forced=False;self.exit_code=None;self.final=None
    def start(self):
        read_spec(self.spec,self.digest)
        with socket.socket()as s:
            s.settimeout(.2);need(s.connect_ex(('127.0.0.1',29567))!=0,'peer_forward_port_already_used')
        with(self.stage/'peer_forward_stderr.log').open('xb')as out:self.proc=subprocess.Popen([sys.executable,'-B',str(Path(__file__)),'--exec-forward','--spec',str(self.spec),'--spec-sha256',self.digest],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=out,start_new_session=True)
        self.handle=psutil.Process(self.proc.pid);self.identity=self.handle.create_time();self.handle.cpu_percent(None)
        until=time.monotonic()+15
        while True:
            self.require_alive()
            with socket.socket()as s:
                s.settimeout(.2)
                if s.connect_ex(('127.0.0.1',29567))==0:break
            need(time.monotonic()<until,'peer_forward_start_timeout');time.sleep(.1)
        need(self.handle.exe()=='/usr/bin/ssh','peer_forward_exec_identity_invalid')
    def require_alive(self):need(self.proc is not None and self.proc.poll()is None and self.handle.create_time()==self.identity,'peer_forward_lost')
    def sample(self):
        alive=self.proc is not None and self.proc.poll()is None
        row={'role':'data_ssh_tunnel','pid':None if self.proc is None else self.proc.pid,'running':alive,'create_time':self.identity}
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
    def receipt(self):return {'kind':'EXACT_OWNED_RESTRICTED_LINUX_PEER_FORWARD','known_host_sha256':KNOWN_SHA,'backend_host':'47.111.16.128','local_bind':'127.0.0.1:29567','target_bind':'127.0.0.1:29567','data_ssh_processes':1,'pid':None if self.proc is None else self.proc.pid,'create_time':self.identity,'closed':self.closed(),'forced_kill':self.forced,'exit_code':self.exit_code,'final_sample':self.final,'private_key_exported':False,'new_authorization_mutations_by_this_controller':0}
def main():
    p=argparse.ArgumentParser();p.add_argument('--exec-forward',action='store_true',required=True);p.add_argument('--spec',required=True);p.add_argument('--spec-sha256',required=True);a=p.parse_args();read_spec(a.spec,a.spec_sha256)
    parent=os.getppid();libc=ctypes.CDLL(None,use_errno=True);need(libc.prctl(1,signal.SIGTERM,0,0,0)==0 and os.getppid()==parent,'peer_parent_death_setup_failed');soft,hard=resource.getrlimit(resource.RLIMIT_NOFILE);target=min(hard,65535)if hard!=resource.RLIM_INFINITY else 65535;need(target>=16384,'peer_forward_fd_limit_insufficient');resource.setrlimit(resource.RLIMIT_NOFILE,(target,hard));os.execv('/usr/bin/ssh',argv())
if __name__=='__main__':main()
