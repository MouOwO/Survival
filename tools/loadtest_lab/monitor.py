"""Bounded, read-only Linux/PG aggregates for one attested isolated lab.

One initialization indexes one filesystem block device and default IPv4 NIC.
Each >=5-second sample reads fixed proc/sysfs counters and two aggregate SQL
queries. The activity view scales with bounded DB connections, never registered
accounts; no player rows, query text, credentials, process arguments, or logs
are collected. Memory is O(1); output grows O(duration / interval).
"""
from __future__ import annotations

import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys
import time

from .guard import dsn, load, marker_guard, need, production_host_guard, read_json, write_new

PROC, SYS = Path('/proc'), Path('/sys')
ACTIVITY_SQL = """SELECT count(*),
 count(*) FILTER (WHERE state='active'),
 count(*) FILTER (WHERE state='active' AND wait_event_type IS NOT NULL),
 count(*) FILTER (WHERE wait_event_type='Lock'),
 count(*) FILTER (WHERE state='idle in transaction')
 FROM pg_catalog.pg_stat_activity
 WHERE datid=(SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database())
 AND pid<>pg_backend_pid()"""
DATABASE_SQL = """SELECT xact_commit,xact_rollback,blks_read,blks_hit,
 temp_files,temp_bytes,deadlocks,blk_read_time,blk_write_time,stats_reset
 FROM pg_catalog.pg_stat_database WHERE datname=current_database()"""
DATABASE_FIELDS = ('xact_commit', 'xact_rollback', 'blks_read', 'blks_hit',
                   'temp_files', 'temp_bytes', 'deadlocks', 'blk_read_time_ms',
                   'blk_write_time_ms', 'stats_reset')
BLOCK_FIELDS = ('reads', 'reads_merged', 'read_sectors', 'read_ms', 'writes',
                'writes_merged', 'write_sectors', 'write_ms', 'inflight',
                'io_busy_ms', 'weighted_io_ms')


class ScopeError(ValueError):
    pass


def _utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _text(path, budget=65536):
    with path.open('rb') as stream:
        raw = stream.read(budget + 1)
    need(len(raw) <= budget, 'monitor_counter_budget_exceeded')
    return raw.decode('ascii')


def _devices(root):
    device = os.stat(root).st_dev
    block = SYS / 'dev/block' / (str(os.major(device)) + ':' + str(os.minor(device))) / 'stat'
    nic = None
    try:
        routes = []
        for line in _text(PROC / 'net/route').splitlines()[1:]:
            row = line.split()
            if (len(row) >= 8 and row[1] == '00000000' and int(row[3], 16) & 1
                    and row[0] != 'lo' and re.fullmatch('[A-Za-z0-9_.:-]{1,64}', row[0])):
                routes.append((int(row[6]), row[0]))
        nic = min(routes)[1] if routes else None
    except (OSError, ValueError, UnicodeError):
        pass
    return block, nic


def _host(root, block, nic):
    result, errors = {}, []
    try:
        # Only the aggregate first row is needed, independent of CPU/core count.
        with (PROC / 'stat').open('rb') as stream:
            row = stream.readline(4097).decode('ascii').split()
        need(row[0] == 'cpu' and 9 <= len(row) <= 12, 'monitor_cpu_invalid')
        ticks = [int(value) for value in row[1:9]]
        need(min(ticks) >= 0, 'monitor_cpu_invalid')
        result['cpu_ticks'] = ticks
    except (OSError, ValueError, IndexError, UnicodeError):
        errors.append('cpu_unavailable')
    try:
        wanted = {'MemTotal:', 'MemAvailable:', 'SwapTotal:', 'SwapFree:'}
        values = {}
        for line in _text(PROC / 'meminfo').splitlines():
            row = line.split()
            if row and row[0] in wanted:
                need(len(row) == 3 and row[2] == 'kB', 'monitor_memory_invalid')
                values[row[0][:-1] + '_bytes'] = int(row[1]) * 1024
        need(len(values) == 4 and min(values.values()) >= 0, 'monitor_memory_invalid')
        result['memory'] = values
    except (OSError, ValueError, UnicodeError):
        errors.append('memory_unavailable')
    try:
        values = [int(value) for value in _text(block, 4096).split()]
        need(len(values) >= 11 and min(values) >= 0, 'monitor_block_invalid')
        result['block'] = dict(zip(BLOCK_FIELDS, values[:11]))
    except (OSError, ValueError, UnicodeError):
        errors.append('filesystem_block_counters_unavailable')
    try:
        stat = os.statvfs(root)
        result['filesystem'] = {'size_bytes': stat.f_blocks * stat.f_frsize,
                                'available_bytes': stat.f_bavail * stat.f_frsize}
    except (OSError, AttributeError):
        errors.append('filesystem_space_unavailable')
    try:
        need(nic is not None, 'monitor_default_interface_missing')
        base = SYS / 'class/net' / nic / 'statistics'
        values = {key: int(_text(base / key, 128).strip()) for key in ('rx_bytes', 'tx_bytes')}
        need(min(values.values()) >= 0, 'monitor_network_invalid')
        result['network'] = values
    except (OSError, ValueError, UnicodeError):
        errors.append('network_counters_unavailable')
    return result, errors


def _rates(previous, current, elapsed):
    result = {}
    if previous is None or elapsed <= 0:
        return result
    old, new = previous.get('cpu_ticks'), current.get('cpu_ticks')
    if old and new:
        delta = [b - a for a, b in zip(old, new)]
        total = sum(delta)
        if min(delta) >= 0 and total > 0:
            result.update(cpu_busy_pct=100 * (total - delta[3] - delta[4] - delta[7]) / total,
                          cpu_iowait_pct=100 * delta[4] / total, cpu_steal_pct=100 * delta[7] / total)
        else:
            result['cpu_counter_reset_or_no_ticks'] = True
    for group, fields, suffix in (('network', ('rx_bytes', 'tx_bytes'), '_per_second'),
                                  ('block', ('read_sectors', 'write_sectors'), '_per_second')):
        if group not in previous or group not in current:
            continue
        for key in fields:
            delta = current[group][key] - previous[group][key]
            if delta < 0:
                result[group + '_counter_reset'] = True
            else:
                factor = 512 if group == 'block' else 1
                name = key.replace('sectors', 'bytes') + suffix
                result[group + '_' + name] = delta * factor / elapsed
    return result


class _Connection:
    def __init__(self, connection, counts):
        self.connection, self.counts = connection, counts

    def execute(self, sql):
        need(sql.lstrip().upper().startswith(('SELECT ', 'SHOW ')), 'monitor_read_only_query_required')
        self.counts['sql_calls_attempted'] += 1
        return self.connection.execute(sql)

    def close(self):
        self.connection.close()


def _connect(cfg, private, counts):
    import psycopg
    counts['connection_attempts'] += 1
    raw = psycopg.connect(dsn(cfg, private, admin=True), autocommit=True,
        connect_timeout=3, application_name='survival_isolated_loadtest_monitor',
        options='-c default_transaction_read_only=on -c statement_timeout=1500 -c lock_timeout=500')
    connection = _Connection(raw, counts)
    try:
        marker_guard(connection, cfg, private, seeded=True)
        need(connection.execute('SHOW transaction_read_only').fetchone() == ('on',),
             'monitor_read_only_session_required')
    except ValueError as error:
        try:
            connection.close()
        except Exception:
            pass
        raise ScopeError('database_scope_or_read_only_guard_failed') from error
    except Exception as error:
        try:
            connection.close()
        except Exception:
            pass
        if getattr(error, 'sqlstate', None) in {'42P01', '3F000', '42501'}:
            raise ScopeError('database_scope_or_read_only_guard_failed') from error
        raise
    counts['connections_verified'] += 1
    return connection


def _postgres(connection):
    activity = connection.execute(ACTIVITY_SQL).fetchone()
    database = connection.execute(DATABASE_SQL).fetchone()
    need(activity is not None and len(activity) == 5 and database is not None and len(database) == 10,
         'monitor_pg_aggregate_missing')
    statistics = dict(zip(DATABASE_FIELDS, database))
    reset = statistics['stats_reset']
    statistics['stats_reset'] = reset.isoformat() if reset is not None else None
    return {'activity': dict(zip(('connections_excluding_monitor', 'active', 'active_waiting',
                                 'waiting_for_lock', 'idle_in_transaction'), activity)),
            'database': statistics}


# Opt-in fixed-process observations. No import-time native/filesystem work.
PID_SCOPE_KEYS = frozenset(('schema','id','run_id','manifest_sha256','processes','postgres_container_name'))
PID_ID_KEYS = frozenset(('pid','starttime_ticks','boot_id_sha256','exe_sha256'))
PID_PROC_KEYS = frozenset(('stat','status','io','cgroup'))
PID_IMAGE = 'public.ecr.aws/docker/library/postgres@sha256:639ab7ceb90e13123085b741fb31ef493fba25463002f6da665352e7b534b652'
PID_IMAGE_ID = '248efd5e58cd743f2a0e0daec8ea4649e5580145ec2a12e2345bc710d4a77201'
PID_IO_KEYS = ('rchar','wchar','syscr','syscw','read_bytes','write_bytes','cancelled_write_bytes')
PID_CPU_KEYS = ('usage_usec','user_usec','system_usec','nr_periods','nr_throttled','throttled_usec')
PID_CGROUP_FILES = frozenset(('cpu.stat','cpu.max','memory.current','memory.max','memory.events','pids.current','pids.max','io.stat'))
PID_INSPECT_TEMPLATE = ('{"id":{{json .ID}},"name":{{json .Name}},"image_id":{{json .Image}},'
 '"run_id":{{json (index .Config.Labels "survival.run_id")}},"running":{{json .State.Running}},'
 '"paused":{{json .State.Paused}},"restarting":{{json .State.Restarting}},"pid":{{json .State.Pid}},'
 '"restart_count":{{json .RestartCount}},"memory":{{json .HostConfig.Memory}},'
 '"nano_cpus":{{json .HostConfig.NanoCpus}},"cpu_quota":{{json .HostConfig.CpuQuota}},'
 '"cpu_period":{{json .HostConfig.CpuPeriod}},"network_mode":{{json .HostConfig.NetworkMode}}}')


def _pm_digest(raw):return hashlib.sha256(raw).hexdigest()
def _pm_hex(v):return type(v)is str and re.fullmatch('[a-f0-9]{64}',v)is not None

def _pm_int(v,minimum=0):
    need(type(v)is int and v>=minimum,'process_counter_integer_invalid');return v

def _pm_boot_hash():
    raw=_text(PROC/'sys/kernel/random/boot_id',128).strip()
    need(re.fullmatch('[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}',raw)is not None,'process_boot_identity_invalid')
    return _pm_digest(raw.encode())


class _CounterDirectory:
    def __init__(self,path,allowed,counts):
        self.path,self.allowed,self.counts=Path(path),allowed,counts;self.fd=None
    def __enter__(self):
        self.fd=os.open(self.path,os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC|os.O_NOFOLLOW)
        self.counts['directory_opens']+=1
        st=os.fstat(self.fd);self.identity=(st.st_dev,st.st_ino)
        return self
    def __exit__(self,*args):
        if self.fd is not None:os.close(self.fd);self.fd=None
    def read(self,name,budget=8192):
        need(name in self.allowed,'process_counter_file_not_allowlisted')
        self.counts['counter_reads']+=1
        fd=os.open(name,os.O_RDONLY|os.O_CLOEXEC|os.O_NOFOLLOW,dir_fd=self.fd)
        try:
            with os.fdopen(fd,'rb')as stream:raw=stream.read(budget+1)
        except BaseException:
            # fdopen owns fd after construction; do not close a reused descriptor.
            raise
        need(len(raw)<=budget,'process_counter_read_budget_exceeded');self.counts['counter_bytes']+=len(raw);return raw
    def exe(self,hash_content=False):
        # Only the kernel's fixed exe link is followed, never argv/environment.
        self.counts['exe_metadata_reads']+=1
        fd=os.open('exe',os.O_RDONLY|os.O_CLOEXEC,dir_fd=self.fd)
        try:
            st=os.fstat(fd);fingerprint=(st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns)
            if not hash_content:return None,fingerprint
            need(0<st.st_size<=64*1024*1024,'process_executable_budget_exceeded')
            h=hashlib.sha256();length=0
            while True:
                raw=os.read(fd,1024*1024)
                if not raw:break
                length+=len(raw);need(length<=64*1024*1024,'process_executable_budget_exceeded');h.update(raw)
            after=os.fstat(fd);need(fingerprint==(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns),'process_executable_changed_during_hash')
            need(length==st.st_size,'process_executable_size_changed');self.counts['exe_bytes_hashed']+=length
            return h.hexdigest(),fingerprint
        finally:os.close(fd)


def _pm_open(path,allowed,counts):return _CounterDirectory(path,allowed,counts)
def _pm_counts():return dict(directory_opens=0,counter_reads=0,counter_bytes=0,exe_metadata_reads=0,exe_bytes_hashed=0,podman_inspect_calls=0)


def _pm_stat(raw,pid):
    # comm may contain whitespace, non-ASCII and ')'; it is never retained.
    left=raw.find(b'(');right=raw.rfind(b')');need(0<left<right,'process_stat_invalid')
    need(int(raw[:left].strip())==pid,'process_stat_pid_mismatch');row=raw[right+1:].split();need(len(row)>=22,'process_stat_fields_missing')
    result={'state':row[0].decode('ascii'),'utime_ticks':int(row[11]),'stime_ticks':int(row[12]),
        'cutime_ticks':int(row[13]),'cstime_ticks':int(row[14]),'threads':int(row[17]),'starttime_ticks':int(row[19])}
    need(result['state']in('R','S','D','Z','T','t','X','x','K','W','P','I'),'process_state_invalid')
    for k,v in result.items():
        if k!='state':_pm_int(v)
    return result


def _pm_capture(pid,boot_hash,counts):
    need(type(pid)is int and 1<=pid<=4194304,'process_pid_invalid')
    with _pm_open(PROC/str(pid),PID_PROC_KEYS,counts)as directory:
        a=_pm_stat(directory.read('stat'),pid);digest,fingerprint=directory.exe(True);b=_pm_stat(directory.read('stat'),pid)
        need(a['starttime_ticks']==b['starttime_ticks']and b['state']not in('Z','X','x'),'process_identity_unstable')
        return {'pid':pid,'starttime_ticks':b['starttime_ticks'],'boot_id_sha256':boot_hash,'exe_sha256':digest},directory.identity,fingerprint


def capture_process_identity(pid=None):
    """Once-only public identity for runtime; no argv/env, no retained descriptors."""
    return _pm_capture(os.getpid()if pid is None else pid,_pm_boot_hash(),_pm_counts())[0]


def _pm_validate_identity(value):
    need(type(value)is dict and set(value)==PID_ID_KEYS,'process_identity_shape_invalid')
    need(type(value['pid'])is int and 1<=value['pid']<=4194304 and type(value['starttime_ticks'])is int and value['starttime_ticks']>=0
         and _pm_hex(value['boot_id_sha256'])and _pm_hex(value['exe_sha256']),'process_identity_invalid')


def _pm_scope(cfg,value):
    need(type(value)is dict and set(value)==PID_SCOPE_KEYS and type(value['schema'])is int and value['schema']==1
         and value['id']=='pid-v1'and value['run_id']==cfg['run_id'],'process_scope_shape_or_run_invalid')
    manifest=_pm_digest(json.dumps(cfg,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode())
    need(value['manifest_sha256']==manifest,'process_scope_manifest_mismatch')
    need(value['postgres_container_name']=='survival-loadtest-'+cfg['run_id'][:12],'process_scope_container_name_invalid')
    rows=value['processes'];need(type(rows)is list and 1<=len(rows)<=2,'process_scope_count_invalid');roles=[];pids=[]
    for row in rows:
        need(type(row)is dict and set(row)==PID_ID_KEYS|{'roles'},'process_scope_process_invalid')
        _pm_validate_identity({k:row[k]for k in PID_ID_KEYS});r=row['roles']
        need(type(r)is list and 1<=len(r)<=2 and all(x in('frontend','backend')for x in r)and len(r)==len(set(r)),'process_scope_roles_invalid')
        roles+=r;pids.append(row['pid'])
    need(sorted(roles)==['backend','frontend']and len(pids)==len(set(pids)),'process_scope_duplicate_roles_or_pids')
    topology=cfg.get('process_topology');topology='same-v1'if topology is None else topology
    need(topology in('same-v1','split-v1'),'process_scope_topology_required')
    need(len(rows)==(1 if topology=='same-v1'else 2),'process_scope_topology_pid_count_mismatch')
    return value


def _pm_status(raw):
    wanted={b'VmRSS':('rss_bytes',1024),b'VmHWM':('lifetime_peak_rss_bytes',1024),b'Threads':('threads',1),
            b'voluntary_ctxt_switches':('voluntary_context_switches',1),b'nonvoluntary_ctxt_switches':('nonvoluntary_context_switches',1)}
    out={}
    for line in raw.splitlines():
        if b':'not in line:continue
        key,value=line.split(b':',1)
        if key not in wanted:continue
        name,factor=wanted[key];fields=value.split();need(len(fields)==(2 if factor==1024 else 1),'process_status_value_invalid')
        if factor==1024:need(fields[1]==b'kB','process_status_unit_invalid')
        need(name not in out,'process_status_duplicate_field');out[name]=_pm_int(int(fields[0]))*factor
    need(len(out)==len(wanted),'process_status_field_missing');return out


def _pm_key_values(raw,keys):
    out={}
    for line in raw.splitlines():
        fields=line.replace(b':',b' ').split();need(len(fields)==2,'process_key_value_invalid');key=fields[0].decode('ascii')
        if key not in keys:continue
        need(key not in out,'process_duplicate_counter');out[key]=_pm_int(int(fields[1]))
    need(set(out)==set(keys),'process_counter_fields_missing');return out


def _pm_deltas(old,new):
    if old is None or new is None:return None,'first_or_missing_sample'
    need(set(old)==set(new),'process_counter_set_changed');delta={k:new[k]-old[k]for k in new}
    if any(v<0 for v in delta.values()):return None,'counter_reset'
    return delta,None


class _ObservedProcess:
    def __init__(self,descriptor,boot_hash,counts):
        self.public={k:descriptor[k]for k in PID_ID_KEYS};self.roles=list(descriptor['roles']);self.counts=counts;self.previous=None;self.terminal=None
        actual,self.directory_id,self.exe_id=_pm_capture(descriptor['pid'],boot_hash,counts)
        need(actual==self.public,'process_scope_identity_mismatch')
    def sample(self,clock,ticks):
        began=clock();pid=self.public['pid'];errors=[]
        if self.terminal:return {'identity':self.public,'roles':self.roles,'status':self.terminal,'cumulative':None,'gauges':None,'interval':None,'errors':[self.terminal],'read_seconds':0.0}
        try:
            with _pm_open(PROC/str(pid),PID_PROC_KEYS,self.counts)as directory:
                first=_pm_stat(directory.read('stat'),pid);_,exe=directory.exe()
                need(directory.identity==self.directory_id and first['starttime_ticks']==self.public['starttime_ticks']and exe==self.exe_id,'process_identity_changed')
                if first['state']in('Z','X','x'):raise ProcessLookupError()
                status=io=None
                try:status=_pm_status(directory.read('status'))
                except (OSError,ValueError,UnicodeError):errors.append('process_status_unavailable')
                try:io=_pm_key_values(directory.read('io'),PID_IO_KEYS)
                except (OSError,ValueError,UnicodeError):errors.append('process_io_unavailable')
                last=_pm_stat(directory.read('stat'),pid);need(first['starttime_ticks']==last['starttime_ticks'],'process_identity_changed_during_read')
                if last['state']in('Z','X','x'):raise ProcessLookupError()
                _,end_exe=directory.exe();need(end_exe==exe,'process_executable_changed_during_read')
        except (FileNotFoundError,ProcessLookupError):self.terminal='process_exited';return self.sample(clock,ticks)
        except PermissionError:self.previous=None;return {'identity':self.public,'roles':self.roles,'status':'unavailable','cumulative':None,'gauges':None,'interval':None,'errors':['process_permission_denied'],'read_seconds':clock()-began}
        except (OSError,ValueError,UnicodeError):self.terminal='process_identity_or_counter_invalid';return self.sample(clock,ticks)
        ended=clock();cum={k:last[k]for k in('utime_ticks','stime_ticks','cutime_ticks','cstime_ticks')};cum['io']=io;interval=None
        if self.previous is not None:
            old_at,old_cpu,old_io=self.previous;dt=ended-old_at
            if dt>0:
                cpu,error=_pm_deltas(old_cpu,{k:cum[k]for k in('utime_ticks','stime_ticks','cutime_ticks','cstime_ticks')});iod,ioerror=_pm_deltas(old_io,io)
                interval={'seconds':dt,'own_cpu_seconds':None if cpu is None else(cpu['utime_ticks']+cpu['stime_ticks'])/ticks,
                    'own_cpu_cores':None if cpu is None else(cpu['utime_ticks']+cpu['stime_ticks'])/ticks/dt,
                    'waited_children_cpu_seconds_accounted':None if cpu is None else(cpu['cutime_ticks']+cpu['cstime_ticks'])/ticks,
                    'io_delta':iod,'io_per_second':None if iod is None else{k:v/dt for k,v in iod.items()},'cpu_error':error,'io_error':ioerror}
                if error:errors.append('process_cpu_'+error)
                if ioerror and ioerror!='first_or_missing_sample':errors.append('process_io_'+ioerror)
            else:errors.append('process_clock_not_advanced')
        self.previous=(ended,{k:cum[k]for k in('utime_ticks','stime_ticks','cutime_ticks','cstime_ticks')},io)
        return {'identity':self.public,'roles':self.roles,'status':'ok'if not errors else'partial','cumulative':cum,'gauges':{**(status or{}),'stat_threads':last['threads'],'state':last['state']},'interval':interval,'errors':errors,'read_seconds':ended-began,'read_span_monotonic':[began,ended]}
    def verify_alive(self):
        pid=self.public['pid']
        with _pm_open(PROC/str(pid),PID_PROC_KEYS,self.counts)as directory:
            stat=_pm_stat(directory.read('stat'),pid);_,exe=directory.exe()
            need(directory.identity==self.directory_id and stat['starttime_ticks']==self.public['starttime_ticks']and exe==self.exe_id and stat['state']not in('Z','X','x'),'postgres_init_identity_changed')


def _pm_inspect(name,cfg,counts):
    import subprocess
    need(cfg.get('postgres_image')==PID_IMAGE,'process_monitor_requires_reviewed_postgres_image')
    counts['podman_inspect_calls']+=1
    result=subprocess.run(['/usr/bin/podman','container','inspect','--format',PID_INSPECT_TEMPLATE,name],capture_output=True,timeout=3)
    need(result.returncode==0 and len(result.stdout)<=16384,'process_podman_inspection_unavailable');row=json.loads(result.stdout)
    expected=frozenset(('id','name','image_id','run_id','running','paused','restarting','pid','restart_count','memory','nano_cpus','cpu_quota','cpu_period','network_mode'))
    need(type(row)is dict and set(row)==expected,'process_podman_inspection_shape_invalid')
    need(type(row['id'])is str and re.fullmatch('[a-f0-9]{64}',row['id'])and row['name']==name and row['run_id']==cfg['run_id'],'process_container_identity_invalid')
    image=row['image_id'];need(type(image)is str and image.removeprefix('sha256:')==PID_IMAGE_ID,'process_container_image_ID_mismatch')
    need(row['running']is True and row['paused']is False and row['restarting']is False and type(row['restart_count'])is int and row['restart_count']==0,'process_container_not_fresh_running')
    for key in('pid','memory','nano_cpus','cpu_quota','cpu_period'):_pm_int(row[key])
    need(row['pid']>0 and row['network_mode']=='host'and row['memory']==cfg['database_memory_mib']*1024*1024,'process_container_limits_mismatch')
    nanos=round(cfg['database_cpu_limit']*1000000000);need(row['nano_cpus']==nanos and row['cpu_period']>0 and row['cpu_quota']*1000000000==nanos*row['cpu_period'],'process_container_CPU_limit_mismatch')
    return row


def _pm_io_devices(raw):
    out={}
    for line in raw.splitlines():
        parts=line.split();need(parts and re.fullmatch(b'[0-9]+:[0-9]+',parts[0]),'process_cgroup_io_invalid');device=parts[0].decode('ascii');need(device not in out,'process_cgroup_duplicate_device');values={}
        for part in parts[1:]:
            pair=part.split(b'=');need(len(pair)==2,'process_cgroup_io_invalid');key=pair[0].decode('ascii')
            if key in('rbytes','wbytes','rios','wios','dbytes','dios'):need(key not in values,'process_cgroup_io_duplicate');values[key]=_pm_int(int(pair[1]))
        need(set(values)=={'rbytes','wbytes','rios','wios','dbytes','dios'},'process_cgroup_io_fields_missing');out[device]=values
    need(len(out)<=4,'process_cgroup_device_budget_exceeded');return out


class _ObservedCgroup:
    def __init__(self,inspection,init,cfg,counts):
        self.init,self.cfg,self.counts=init,cfg,counts;self.previous=None;self.terminal=None
        init.verify_alive()
        with _pm_open(PROC/str(init.public['pid']),PID_PROC_KEYS,counts)as directory:raw=directory.read('cgroup')
        lines=raw.decode('ascii').splitlines();rows=[x[3:]for x in lines if x.startswith('0::')];need(len(rows)==1,'process_cgroup_v2_required');relative=rows[0]
        need(relative.startswith('/')and'..'not in relative.split('/')and'\\'not in relative,'process_cgroup_path_invalid')
        parts=relative.strip('/').split('/');ident=inspection['id'];need(any(x in(ident,'libpod-'+ident,'libpod-'+ident+'.scope')for x in parts),'process_cgroup_container_mismatch')
        self.path=Path('/sys/fs/cgroup').joinpath(*parts);need(self.path.resolve().is_relative_to(Path('/sys/fs/cgroup').resolve()),'process_cgroup_path_escape')
        with _pm_open(self.path,PID_CGROUP_FILES,counts)as directory:
            self.directory_id=directory.identity;self._limits(directory);self.devices=set(_pm_io_devices(directory.read('io.stat')))
        init.verify_alive();self.public={'path':str(self.path),'directory_device':self.directory_id[0],'directory_inode':self.directory_id[1],'io_devices':sorted(self.devices),'container':inspection}
    def _limits(self,directory):
        cpu=directory.read('cpu.max',128).split();need(len(cpu)==2 and cpu[0]!=b'max','process_cgroup_CPU_unbounded');quota,period=map(int,cpu);need(quota>0 and period>0,'process_cgroup_CPU_invalid')
        need(quota*1000000000==round(self.cfg['database_cpu_limit']*1000000000)*period,'process_cgroup_CPU_limit_changed')
        memory=int(directory.read('memory.max',128).strip());need(memory==self.cfg['database_memory_mib']*1024*1024,'process_cgroup_memory_limit_changed');return {'cpu_quota_usec':quota,'cpu_period_usec':period,'memory_max_bytes':memory}
    def sample(self,clock):
        began=clock();errors=[]
        if self.terminal:return {'status':self.terminal,'cumulative':None,'gauges':None,'interval':None,'errors':[self.terminal],'read_seconds':0.0}
        try:
            self.init.verify_alive()
            with _pm_open(self.path,PID_CGROUP_FILES,self.counts)as directory:
                need(directory.identity==self.directory_id,'process_cgroup_identity_changed');limits=self._limits(directory)
                cpu=_pm_key_values(directory.read('cpu.stat'),PID_CPU_KEYS);memory=_pm_int(int(directory.read('memory.current',128).strip()))
                events=_pm_key_values(directory.read('memory.events'),('low','high','max','oom','oom_kill'));pids=_pm_int(int(directory.read('pids.current',128).strip()));pidsmax=directory.read('pids.max',128).strip();pidsmax=None if pidsmax==b'max'else _pm_int(int(pidsmax))
                io=_pm_io_devices(directory.read('io.stat'))
                if set(io)!=self.devices:
                    errors.append('process_cgroup_io_device_set_changed')
                    io={device:io[device]for device in self.devices if device in io}
            self.init.verify_alive()
        except (OSError,ValueError,UnicodeError):self.terminal='postgres_cgroup_identity_or_counters_unavailable';return self.sample(clock)
        ended=clock();cum={'cpu':cpu,'memory_events':events,'io':io};interval=None
        if self.previous is not None:
            old_at,old=self.previous;dt=ended-old_at
            if dt>0:
                cpud,cpuerror=_pm_deltas(old['cpu'],cpu);eventd,eventerror=_pm_deltas(old['memory_events'],events);iod={};ioerrors={}
                for device in sorted(self.devices):
                    value,error=_pm_deltas(old['io'].get(device),io.get(device));iod[device]=value
                    if error:ioerrors[device]=error
                interval={'seconds':dt,'cpu_usage_cores':None if cpud is None else cpud['usage_usec']/1000000/dt,'cpu_delta':cpud,
                    'throttled_seconds_delta':None if cpud is None else cpud['throttled_usec']/1000000,'throttled_wall_percent':None,
                    'memory_events_delta':eventd,'io_delta_by_device':iod,'io_bytes_per_second_by_device':{k:None if v is None else{'read':v['rbytes']/dt,'write':v['wbytes']/dt}for k,v in iod.items()},
                    'cpu_error':cpuerror,'memory_events_error':eventerror,'io_errors':ioerrors}
                if cpuerror:errors.append('process_cgroup_cpu_'+cpuerror)
                if eventerror:errors.append('process_cgroup_memory_events_'+eventerror)
                if ioerrors:errors.append('process_cgroup_io_interval_gap')
            else:errors.append('process_cgroup_clock_not_advanced')
        self.previous=(ended,cum)
        return {'status':'ok'if not errors else'partial','cumulative':cum,'gauges':{**limits,'memory_current_bytes':memory,'pids_current':pids,'pids_max':pidsmax},'interval':interval,'errors':errors,'read_seconds':ended-began,'read_span_monotonic':[began,ended]}


def _pm_block_interval(old,new,seconds):
    a,b=(old or{}).get('block'),new.get('block')
    if a is None or b is None or seconds<=0:return {'status':'first_or_missing_sample','rates':None}
    fields=('reads','writes','read_ms','write_ms','io_busy_ms','weighted_io_ms');delta,error=_pm_deltas({k:a[k]for k in fields},{k:b[k]for k in fields})
    if error:return {'status':error,'rates':None}
    completed=delta['reads']+delta['writes']
    return {'status':'ok','interval_seconds':seconds,'counter_delta':delta,'inflight_at_sample':b['inflight'],
        'rates':{'io_busy_pct':100*delta['io_busy_ms']/(1000*seconds),'weighted_queue_depth':delta['weighted_io_ms']/(1000*seconds),
            'completed_read_write_mean_ms':None if completed==0 else(delta['read_ms']+delta['write_ms'])/completed},
        'scope':'One initialized filesystem block device; kernelstat estimate, notSQL/requestP95 or guaranteed saturation.'}


class _ProcessObservation:
    def __init__(self,root,cfg,scope_path=None):
        began=time.monotonic();self.counts=_pm_counts();self.samples=self.samples_with_gaps=0
        path=Path(scope_path)if scope_path is not None else root/'process_scope.json'
        need(path.resolve()==(root/'process_scope.json').resolve()and path.is_file()and not path.is_symlink()and path.stat().st_size<=16384,'process_scope_path_invalid')
        raw=path.read_bytes();need(len(raw)<=16384,'process_scope_budget_exceeded');value=_pm_scope(cfg,json.loads(raw));self.scope_sha256=_pm_digest(raw)
        boot=_pm_boot_hash();self.ticks=os.sysconf('SC_CLK_TCK');need(type(self.ticks)is int and self.ticks>0,'process_clock_ticks_invalid')
        descriptors=[dict(row,roles=list(row['roles']))for row in value['processes']]
        own=_pm_capture(os.getpid(),boot,self.counts)[0]
        match=next((row for row in descriptors if row['pid']==own['pid']),None)
        if match is None:descriptors.append({**own,'roles':['monitor']})
        else:need({k:match[k]for k in PID_ID_KEYS}==own,'process_monitor_identity_mismatch');match['roles'].append('monitor')
        inspection=_pm_inspect(value['postgres_container_name'],cfg,self.counts);pg=_pm_capture(inspection['pid'],boot,self.counts)[0]
        need(not any(row['pid']==pg['pid']for row in descriptors),'process_container_init_duplicate_pid');descriptors.append({**pg,'roles':['postgres_init']})
        need(len(descriptors)<=4,'process_observer_budget_exceeded')
        self.processes=[_ObservedProcess(row,boot,self.counts)for row in descriptors];init=self.processes[-1];self.cgroup=_ObservedCgroup(inspection,init,cfg,self.counts)
        self.header={'schema':1,'id':'pid-v1','scope_raw_sha256':self.scope_sha256,'scope_file':'process_scope.json','processes':descriptors,
            'clock_ticks_per_second':self.ticks,'host_cpu_count':os.cpu_count(),'cgroup':self.cgroup.public,'initialization_ms':(time.monotonic()-began)*1000,
            'files':{'proc':['stat','status','io','cgroup(initialization-only)','exe(initial-hash,subsequent-file-identity-only)'],'cgroup':sorted(PID_CGROUP_FILES)},
            'scope_notes':['SamePID roles are aliases, never double-summed','CPU own excludes waitedchild cumulative ticks; child accounting can lag untilreap',
                'RSS maydoublecount sharedpages; HWM isprocesslifetime notstagepeak','ProcIO includeswaitedchildren; chars/syscalls are notnetwork/bodybytes andnotexactphysicaldisktransfer',
                'Do notsubtractcancelled_write_bytes orsumparent+childIO asdisjoint work',
                'Container CPU/memory includesallPGprocesses; postgres_init RSS/CPU isonlyinitPID','Throttled ownbandwidth cumulative seconds canexceedwall; ancestor throttling unmeasured; no wallpercent emitted','Rates fromfixedreadspans, no globalatomic snapshot']}
    def sample(self,previous_host,current_host,host_seconds,*,sample_at=None):
        rows=[p.sample(time.monotonic,self.ticks)for p in self.processes];cg=self.cgroup.sample(time.monotonic);self.samples+=1
        gap=any(row['errors']for row in rows)or bool(cg['errors']);self.samples_with_gaps+=int(gap)
        return {'kind':'FIXED_PROCESS_RESOURCE_SAMPLE_V1','outer_sample_monotonic':sample_at,'processes':rows,'postgres_cgroup':cg,'host_block_interval':_pm_block_interval(previous_host,current_host,host_seconds),'has_gaps':bool(gap)}
    def receipt(self):
        return {'schema':1,'id':'pid-v1','scope_raw_sha256':self.scope_sha256,'samples':self.samples,'samples_with_gaps':self.samples_with_gaps,
            'fixed_read_counts':dict(self.counts),'podman_inspection_once':self.counts['podman_inspect_calls']==1,'no_process_scan_or_rebinding':True,'no_config_or_limit_changes':True}


def monitor(directory, duration_seconds=None, interval_seconds=5, *, scope_path=None):
    root, cfg, private = load(directory)
    production_host_guard(cfg)
    need(sys.platform.startswith('linux'), 'linux_monitor_host_required')
    duration = cfg['duration_seconds'] if duration_seconds is None else duration_seconds
    need(type(duration) is int and 1 <= duration <= min(18000, cfg['duration_seconds']),
         'monitor_duration_budget_invalid')
    need(type(interval_seconds) is int and 5 <= interval_seconds <= 60,
         'monitor_interval_budget_invalid')
    process_mode = cfg.get('process_observation')
    need(process_mode in (None, 'pid-v1'), 'process_observation_mode_invalid')
    need(process_mode is not None or scope_path is None, 'process_scope_requires_opt_in')
    process_observer = _ProcessObservation(root, cfg, scope_path) if process_mode == 'pid-v1' else None
    block, nic = _devices(root)
    tag = secrets.token_hex(8)
    output, receipt_path = root / ('monitor_' + tag + '.jsonl'), root / ('monitor_' + tag + '_receipt.json')
    counts = {'connection_attempts': 0, 'connections_verified': 0, 'sql_calls_attempted': 0,
              'samples': 0, 'postgres_samples': 0, 'samples_with_errors': 0}
    started, started_utc = time.monotonic(), _utc()
    deadline = started + duration
    connection = previous = None
    previous_at = None
    stop_reason, error_codes = 'duration_complete', set()
    digest = hashlib.sha256()
    with output.open('xb') as stream:
        output.chmod(0o600)

        def emit(value):
            raw = json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode() + b'\n'
            stream.write(raw); stream.flush(); digest.update(raw)

        emit({'kind': 'ISOLATED_LAB_MONITOR_HEADER', 'run_id': cfg['run_id'],
              'started_utc': started_utc, 'interval_seconds': interval_seconds,
              'filesystem_device': str(block.parent.name), 'network_interface': nic,
              'query_text_collected': False, 'player_rows_collected': False,
              **({'process_observation_v1': process_observer.header} if process_observer is not None else {})})
        try:
            while time.monotonic() < deadline:
                stopped = root / 'stopped_receipt.json'
                if stopped.exists():
                    try:
                        value = read_json(stopped)
                    except (OSError, ValueError):
                        raise ScopeError('invalid_lab_stop_receipt') from None
                    if (not isinstance(value, dict) or value.get('kind') != 'ISOLATED_LOADTEST_LAB_STOPPED'
                            or value.get('run_id') != cfg['run_id']):
                        raise ScopeError('invalid_lab_stop_receipt')
                    stop_reason = 'lab_stopped'
                    break
                sample_at, sampled_utc = time.monotonic(), _utc()
                host, errors = _host(root, block, nic)
                process_sample = (process_observer.sample(previous, host, sample_at - previous_at if previous_at is not None else 0, sample_at=sample_at)
                                  if process_observer is not None else None)
                postgres = None
                scope_failed = False
                try:
                    if connection is None:
                        connection = _connect(cfg, private, counts)
                    postgres = _postgres(connection)
                    counts['postgres_samples'] += 1
                except ScopeError:
                    errors.append('database_scope_or_read_only_guard_failed')
                    scope_failed = True
                except Exception:
                    errors.append('database_aggregate_unavailable')
                    if connection is not None:
                        try:
                            connection.close()
                        except Exception:
                            pass
                        connection = None
                counts['samples'] += 1
                counts['samples_with_errors'] += int(bool(errors))
                error_codes.update(errors)
                rates = _rates(previous, host, sample_at - previous_at if previous_at is not None else 0)
                emit({'kind': 'ISOLATED_LAB_AGGREGATE_SAMPLE', 'index': counts['samples'],
                      'sampled_utc': sampled_utc, 'elapsed_seconds': sample_at - started,
                      'sample_duration_seconds': time.monotonic() - sample_at,
                      'host': host, 'rates': rates, 'postgres': postgres, 'errors': errors,
                      **({'process_observation_v1': process_sample} if process_observer is not None else {})})
                previous, previous_at = host, sample_at
                if scope_failed:
                    stop_reason = 'database_scope_rejected'
                    break
                remaining = min(deadline - time.monotonic(), sample_at + interval_seconds - time.monotonic())
                if remaining > 0:
                    time.sleep(remaining)
        except KeyboardInterrupt:
            stop_reason = 'interrupted'
        except ScopeError:
            stop_reason = 'invalid_lab_stop_receipt'
            error_codes.add('invalid_lab_stop_receipt')
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    error_codes.add('database_connection_close_failed')
            stream.flush(); os.fsync(stream.fileno())
    receipt = {'kind': 'ISOLATED_LAB_READ_ONLY_MONITOR_RECEIPT', 'artifact_root': str(root),
        'run_id': cfg['run_id'], 'started_utc': started_utc, 'finished_utc': _utc(),
        'duration_requested_seconds': duration, 'duration_actual_seconds': time.monotonic() - started,
        'interval_seconds': interval_seconds, 'stop_reason': stop_reason, 'counts': counts,
        'error_codes': sorted(error_codes), 'output': str(output), 'output_sha256': digest.hexdigest(),
        'read_only': True, 'capacity_certified': False,
        **({'process_observation_v1': process_observer.receipt()} if process_observer is not None else {}),
        'limits': ['system_and_database_aggregates_only_not_unique_bottleneck_diagnosis',
                   'network_interface_includes_private_traffic_not_cloud_public_billing',
                   'block_counters_cover_lab_filesystem_device_not_all_host_disks',
                   'first_sample_has_no_counter_rates', 'database_statistics_may_lag_and_include_monitor_reads',
                   'io_times_require_server_track_io_timing_no_configuration_changed',
                   'operation_timeouts_can_extend_requested_stop_time',
                   'readonly_reconnect_per_interval_only_no_business_request_or_write_replay']}
    write_new(receipt_path, receipt)
    if stop_reason == 'interrupted':
        status = 'MONITOR_INTERRUPTED'
    elif stop_reason in {'database_scope_rejected', 'invalid_lab_stop_receipt'}:
        status = 'MONITOR_REJECTED'
    else:
        status = 'MONITOR_COMPLETE' if not error_codes else 'MONITOR_COMPLETE_WITH_GAPS'
    return {'status': status,
            'receipt': str(receipt_path), 'samples': counts['samples'], 'stop_reason': stop_reason}
