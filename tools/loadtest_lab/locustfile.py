"""Locust entry: LOADTEST_CLIENT points at its private client.json.

Run with a fixed loopback SSH forward. No production URLs, redirects or
automatic transaction retries. Every process reads its immutable setup once;
each virtual user obtains a unique lease from the common indexed allocator.
"""
import os
from pathlib import Path
import random
import secrets
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from loadtest_lab.guard import load_client, target_url, canonical, sha, write_new, register_storage, generator_url
from loadtest_lab.workload import Player, checked, AdmissionBusy, BusyRetryBudget, BusyRetryDeadline, BusyRecoveryTimings, BusyRecoveryRoutes
from loadtest_lab.guard import client_recovery_policy, observation_mode, validate_exit_probe
from loadtest_lab.workload_profiles import COUNTERS as WORKLOAD_COUNTERS, WORKFLOWS, profile_for
from loadtest_lab.wire_client import WireClient, WIRE_MODE, aggregate_reports, http_error_label, failure_label, profile_cache_header
from locust import HttpUser, TaskSet, task, events
from locust.user.task import LOCUST_STATE_STOPPING
from gevent.event import Event
from gevent.lock import BoundedSemaphore
from locust.exception import StopUser
from loadtest_lab.progress import validate_profile as validate_actor_progress, ProgressIndex, ProgressObservation

CFG, CONTROLLER = load_client(os.environ['LOADTEST_CLIENT'])
CLIENT_PROFILE = profile_for(CFG)
EXIT_PROBE = validate_exit_probe(CFG)
EXIT_MODE = 'direct' if EXIT_PROBE is None else EXIT_PROBE['mode']
EXIT_SEMAPHORE = BoundedSemaphore(int(EXIT_MODE[5:-3])) if EXIT_MODE.startswith('queue') else None
EXIT_METRICS = dict(active=0,peak=0,queued=0,completed=0,delay_ms=0)
RUN_EXIT_PROBE_TRIGGERED = False
DEPARTURE_WAVE = None
PROGRESS_PROFILE = validate_actor_progress(CFG)
PROGRESS_INDEX = PROGRESS_OBSERVER = None
PROGRESS_FROZEN = False
WORKLOAD_COUNTS = dict.fromkeys(WORKLOAD_COUNTERS, 0)
WIRE = WireClient(CFG.get('wire_mode', WIRE_MODE), measure_routes=True)
if os.environ.get('LOADTEST_DECODE_SOCKET'):
    from decode_service import install as _install_decode_processes
    _install_decode_processes(WIRE,os.environ['LOADTEST_DECODE_SOCKET'])
WIRE_WORKERS = {}
WIRE_WORKERS_SEEN = set()
WIRE_FINAL = False
WIRE_REPORT_ERROR = None
CLIENT_RECOVERY = client_recovery_policy(CFG)
OBSERVE_OVERLOAD = observation_mode(CFG)
OBSERVATION_COUNTS = dict.fromkeys(('quarantined_actors', 'isolated_errors',
    'cleanup_timeouts', 'failure_rate_windows'), 0)
RECOVERY_TIMINGS = BusyRecoveryTimings() if CLIENT_RECOVERY is not None else None
RECOVERY_COUNTS = dict.fromkeys(('logical_requests', 'logical_completed', 'logical_failed',
    'http_attempts', 'requests_with_busy', 'busy_responses', 'retry_attempts',
    'recovered_requests', 'exhausted_requests', 'backend_busy', 'frontend_busy'), 0)
CONTROL_RECOVERY_COUNTS = (dict.fromkeys(RECOVERY_COUNTS, 0)
    if CLIENT_RECOVERY and CLIENT_RECOVERY.get('retry_setup_control') == 1 else None)
RECOVERY_ROUTES = BusyRecoveryRoutes() if CONTROL_RECOVERY_COUNTS is not None else None
RUN_FAILED = False
RUN_FIRST_FAILURE = None
RUN_QUIT_REQUESTED = False
RUN_NOTIFICATION_FAILED = False
RUN_ENVIRONMENT = None
RUN_MASTER_RAMP = None
RUN_ABORT_ACK = None
RUN_PENDING_WORKERS = set()
RUN_STOPPING = False
RUN_STOPPING_AT = None
RUN_STOPPED = False
RUN_WORKER_SHUTDOWN_STARTED = False
RUN_MASTER_QUIT_OWNER = None
RUN_MASTER_QUIT_DONE = None
RUN_FAILURE_NOTIFIED = False
RUN_COUNTERS = dict.fromkeys(('start_attempts', 'start_blocked_after_failure',
                             'cleanup_attempts', 'cleanup_completed', 'cleanup_failed', 'cleanup_interrupted'), 0)


class CleanupTimeout(Exception):
    """Fixed local teardown budget expiry, never a business retry signal."""


def cleanup_budget(environment):
    return min(70.0, max(.05, float(getattr(environment, 'stop_timeout', 0) or 35)))


def run_state():
    value = {'failed': RUN_FAILED, 'first_failure': RUN_FIRST_FAILURE,
            'quit_requested': RUN_QUIT_REQUESTED, 'notification_failed': RUN_NOTIFICATION_FAILED,
            'stopping': RUN_STOPPING, 'stopped': RUN_STOPPED,
            'counters': dict(RUN_COUNTERS)}
    if CLIENT_PROFILE.mode in ('client-v2', 'client-v3'):
        value.update(client_workload=CLIENT_PROFILE.mode, workload_counters=dict(WORKLOAD_COUNTS))
    if EXIT_PROBE is not None:
        value['exit_probe'] = dict(EXIT_PROBE,triggered=RUN_EXIT_PROBE_TRIGGERED,metrics=dict(EXIT_METRICS))
        wave=globals().get('DEPARTURE_WAVE')
        if wave is not None:
            value['exit_probe']['departure_wave']=wave.report()
            if wave.cancelled or wave.early_finished:
                value['failed']=True;value['first_failure']=value['first_failure']or'departure_wave_incomplete'
    return value


def validate_workload_counters(value):
    if (type(value) is not dict or set(value) != set(WORKLOAD_COUNTERS)
            or any(type(count) is not int or not 0 <= count <= 10**12 for count in value.values())
            or value['checkpoint_attempts'] != value['checkpoint_completed'] + value['checkpoint_failed']
            or value['grant_followup_attempts'] != value['grant_followup_completed'] + value['grant_followup_failed']
            or value['finalization_attempts'] != value['finalization_completed'] + value['finalization_failed']):
        raise ValueError('loadtest_workload_counters_invalid')


def cleanup_balanced(state):
    counters = state['counters']
    return counters['cleanup_attempts'] == sum(counters[name] for name in
        ('cleanup_completed', 'cleanup_failed', 'cleanup_interrupted'))


def worker_settled(state):
    return (type(state) is dict and state.get('stopped') is True
            and type(state.get('counters')) is dict and cleanup_balanced(state))


def wire_balanced(report):
    counters = report['counters']
    return counters['requests'] == counters['responses']


def notify_failure(runner):
    global RUN_FAILURE_NOTIFIED, RUN_NOTIFICATION_FAILED
    if RUN_FAILURE_NOTIFIED:
        return
    RUN_FAILURE_NOTIFIED = True
    try:
        runner.send_message('survival_run_failed', {'error': RUN_FIRST_FAILURE})
    except Exception:
        RUN_NOTIFICATION_FAILED = True


def stop_worker(environment):
    """One owner drains users; cleanup failures never start a second quit."""
    global RUN_WORKER_SHUTDOWN_STARTED, RUN_STOPPING, RUN_NOTIFICATION_FAILED
    if RUN_WORKER_SHUTDOWN_STARTED:
        return
    RUN_WORKER_SHUTDOWN_STARTED = True
    RUN_STOPPING = True
    runner = environment.runner
    try:
        runner.stop()
        if RUN_ABORT_ACK is None or not RUN_ABORT_ACK.wait(timeout=10):
            RUN_NOTIFICATION_FAILED = True
            environment.process_exit_code = 2
        runner.quit()
    except Exception:
        RUN_NOTIFICATION_FAILED = True
        environment.process_exit_code = 2
        runner.greenlet.kill(block=True)


def fail_run(environment, reason, *, notify_master=True):
    """Set the barrier before yielding; only one asynchronous stage stop."""
    global RUN_FAILED, RUN_FIRST_FAILURE, RUN_QUIT_REQUESTED, RUN_NOTIFICATION_FAILED
    safe = failure_label(reason, 'workflow_not_confirmed')
    if not RUN_FAILED:
        RUN_FAILED, RUN_FIRST_FAILURE = True, safe
    if environment is None:
        return
    environment.process_exit_code = 2
    if environment.runner is None:
        return
    from locust.runners import WorkerRunner, MasterRunner
    runner = environment.runner
    if isinstance(runner, WorkerRunner) and notify_master:
        notify_failure(runner)
    # test_stopping fires before Locust begins on_stop. Calling quit again
    # while that owner waits for users can kill the owner and save partial
    # statistics while checkpoint/release requests are still in flight.
    if RUN_STOPPING or RUN_QUIT_REQUESTED:
        return
    RUN_QUIT_REQUESTED = True
    import gevent
    def stop_stage():
        if isinstance(runner, WorkerRunner):
            stop_worker(environment)
        else:
            runner.quit()
    gevent.spawn(stop_stage)


def validate_run_state(state):
    if (type(state) is not dict or type(state.get('failed')) is not bool
            or type(state.get('quit_requested')) is not bool
            or type(state.get('notification_failed')) is not bool
            or type(state.get('stopping')) is not bool
            or type(state.get('stopped')) is not bool
            or type(state.get('counters')) is not dict
            or set(state['counters']) != set(RUN_COUNTERS)
            or any(type(value) is not int or value < 0 for value in state['counters'].values())
            or state.get('first_failure') is not None
            and failure_label(state['first_failure'], 'invalid_worker_failure') != state['first_failure']):
        raise ValueError('loadtest_worker_run_state_invalid')
    if CLIENT_PROFILE.mode in ('client-v2', 'client-v3'):
        if state.get('client_workload') != CLIENT_PROFILE.mode:
            raise ValueError('loadtest_worker_workload_mismatch')
        validate_workload_counters(state.get('workload_counters'))
    if EXIT_PROBE is not None:
        policy=state.get('exit_probe',{})
        if (policy.get('common_seconds')!=EXIT_PROBE['common_seconds'] or policy.get('mode')!=EXIT_MODE
                or type(policy.get('triggered'))is not bool or set(policy.get('metrics',{}))!=set(EXIT_METRICS)
                or any(type(v)is not int or v<0 for v in policy['metrics'].values())):
            raise ValueError('loadtest_exit_probe_report_invalid')



def final_run_state(environment):
    from locust.runners import MasterRunner
    if not isinstance(environment.runner, MasterRunner):
        state = run_state()
        return state | {'scope': 'this_process',
                        'collection_complete': WIRE_FINAL and worker_settled(state)}
    states = [value.get('run_state') for value in WIRE_WORKERS.values()]
    complete = (bool(WIRE_WORKERS_SEEN) and set(WIRE_WORKERS) == WIRE_WORKERS_SEEN
                and all(value['final'] and worker_settled(value.get('run_state')) for value in WIRE_WORKERS.values())
                and not WIRE_REPORT_ERROR)
    counters = dict.fromkeys(RUN_COUNTERS, 0)
    workload = dict.fromkeys(WORKLOAD_COUNTERS, 0)
    for state in states:
        if state is not None:
            for name in counters:
                counters[name] += state['counters'][name]
            if CLIENT_PROFILE.mode in ('client-v2', 'client-v3'):
                for name in workload:
                    workload[name] += state['workload_counters'][name]
    value = run_state() | {'scope': 'latest_cumulative_worker_snapshots',
                          'counters': counters, 'collection_complete': complete}
    if CLIENT_PROFILE.mode in ('client-v2', 'client-v3'):
        value['workload_counters'] = workload
    return value


def remember_worker(client_id, report, *, final=False, state=None):
    # Replace cumulative snapshots; never sum retransmitted worker reports.
    global WIRE_REPORT_ERROR
    try:
        aggregate_reports([report], WIRE.mode)
        if state is not None:
            validate_run_state(state)
        previous = WIRE_WORKERS.get(client_id)
        if previous and previous['final'] and not final:
            return
        if not isinstance(client_id, str) or len(client_id) > 256 or len(WIRE_WORKERS) >= 512 and client_id not in WIRE_WORKERS:
            raise ValueError('loadtest_worker_wire_identity_invalid')
        WIRE_WORKERS[client_id] = {'report': report, 'final': final, 'run_state': state}
        if final and worker_settled(state):
            RUN_PENDING_WORKERS.discard(client_id)
    except Exception:
        WIRE_REPORT_ERROR = 'loadtest_worker_wire_report_invalid'


@events.init.add_listener
def register_wire_messages(environment, **kwargs):
    global RUN_ENVIRONMENT, RUN_ABORT_ACK
    RUN_ENVIRONMENT = environment
    from locust.runners import MasterRunner, WorkerRunner
    if isinstance(environment.runner, MasterRunner):
        original_start = environment.runner.start
        def start_without_recovery(*args, **kwargs):
            # Retain the headless master's one ramp greenlet by identity.
            global RUN_MASTER_RAMP
            if RUN_FAILED:
                return
            import gevent
            RUN_MASTER_RAMP = gevent.getcurrent()
            try:
                return original_start(*args, **kwargs)
            finally:
                RUN_MASTER_RAMP = None
        environment.runner.start = start_without_recovery
        original_quit = environment.runner.quit
        def quit_after_worker_cleanup():
            # One O(W) identity snapshot at shutdown, then O(1) updates as each
            # worker reports a settled final state. No player/container scans.
            global RUN_MASTER_QUIT_OWNER, RUN_MASTER_QUIT_DONE, RUN_STOPPING, RUN_NOTIFICATION_FAILED
            import gevent
            from gevent.event import Event
            current = gevent.getcurrent()
            if RUN_MASTER_QUIT_OWNER is not None:
                if RUN_MASTER_QUIT_OWNER is not current:
                    RUN_MASTER_QUIT_DONE.wait(timeout=cleanup_budget(environment) + 15)
                return
            RUN_MASTER_QUIT_OWNER, RUN_MASTER_QUIT_DONE = current, Event()
            RUN_STOPPING = True
            runner = environment.runner
            try:
                if (RUN_MASTER_RAMP is not None and RUN_MASTER_RAMP is not current
                        and not RUN_MASTER_RAMP.ready()):
                    RUN_MASTER_RAMP.kill(block=True)
                WIRE_WORKERS_SEEN.update(client.id for client in runner.clients.all)
                RUN_PENDING_WORKERS.update(client_id for client_id in WIRE_WORKERS_SEEN
                    if not (WIRE_WORKERS.get(client_id, {}).get('final')
                            and worker_settled(WIRE_WORKERS.get(client_id, {}).get('run_state'))))
                message = 'survival_run_abort' if RUN_FAILED else 'survival_run_finish'
                for client_id in tuple(RUN_PENDING_WORKERS):
                    runner.send_message(message, {'error': RUN_FIRST_FAILURE}, client_id=client_id)
                # Custom worker messages own cleanup and process exit. Locust's
                # standard quit only waits 0.5s; standard stop removes identities
                # from the index before quit can reach those same processes.
                runner.stop(send_stop_to_client=False)
                deadline = time.monotonic() + cleanup_budget(environment) + 15
                while RUN_PENDING_WORKERS and time.monotonic() < deadline:
                    gevent.sleep(.05)
                if RUN_PENDING_WORKERS:
                    RUN_NOTIFICATION_FAILED = True
                    fail_run(environment, 'worker_finalization_not_collected')
            finally:
                try:
                    original_quit()
                finally:
                    RUN_MASTER_QUIT_DONE.set()
        environment.runner.quit = quit_after_worker_cleanup
        def receive(environment, msg, **kwargs):
            WIRE_WORKERS_SEEN.add(msg.node_id)
            payload = msg.data if isinstance(msg.data, dict) else {}
            remember_worker(msg.node_id, payload.get('wire'), final=True, state=payload.get('run_state'))
        def failed(environment, msg, **kwargs):
            value = msg.data.get('error') if type(msg.data) is dict else None
            fail_run(environment, value or 'worker_not_confirmed')
        environment.runner.register_message('survival_wire_final', receive)
        environment.runner.register_message('survival_run_failed', failed)
    elif isinstance(environment.runner, WorkerRunner):
        from gevent.event import Event
        RUN_ABORT_ACK = Event()
        def abort(environment, msg, **kwargs):
            RUN_ABORT_ACK.set()
            value = msg.data.get('error') if type(msg.data) is dict else None
            fail_run(environment, value or 'master_stopped_run', notify_master=False)
        def finish(environment, msg, **kwargs):
            global RUN_STOPPING
            RUN_ABORT_ACK.set()
            RUN_STOPPING = True
            import gevent
            gevent.spawn(stop_worker, environment)
        environment.runner.register_message('survival_run_abort', abort)
        environment.runner.register_message('survival_run_finish', finish)


@events.report_to_master.add_listener
def report_wire(client_id, data, **kwargs):
    data['survival_wire'] = {'report': WIRE.report(), 'final': WIRE_FINAL, 'run_state': run_state()}


@events.worker_report.add_listener
def collect_wire(client_id, data, **kwargs):
    WIRE_WORKERS_SEEN.add(client_id)
    value = data.get('survival_wire')
    if isinstance(value, dict):
        state = value.get('run_state')
        remember_worker(client_id, value.get('report'), final=value.get('final') is True, state=state)
        if type(state) is dict and state.get('failed') is True:
            fail_run(RUN_ENVIRONMENT, state.get('first_failure') or 'worker_not_confirmed')


@events.test_stop.add_listener
def finish_worker_wire(environment, **kwargs):
    global WIRE_FINAL, RUN_STOPPED
    from locust.runners import WorkerRunner
    RUN_STOPPED = WIRE_FINAL = True
    if isinstance(environment.runner, WorkerRunner):
        # Send HTTP stats after cleanup; quit may arrive after stop_timeout.
        try:
            environment.runner._send_stats()
        except Exception:
            fail_run(environment, 'worker_final_statistics_not_sent')
        environment.runner.send_message('survival_wire_final', {'wire': WIRE.report(), 'run_state': run_state()})


def final_wire_report(environment):
    from locust.runners import MasterRunner
    if not isinstance(environment.runner, MasterRunner):
        report = WIRE.report()
        return report | {'scope': 'this_process',
                         'collection_complete': WIRE_FINAL and worker_settled(run_state()) and wire_balanced(report)}
    complete = (bool(WIRE_WORKERS_SEEN) and set(WIRE_WORKERS) == WIRE_WORKERS_SEEN
                and all(value['final'] and worker_settled(value.get('run_state'))
                        and wire_balanced(value['report']) for value in WIRE_WORKERS.values())
                and not WIRE_REPORT_ERROR)
    report = aggregate_reports((value['report'] for value in WIRE_WORKERS.values()), WIRE.mode)
    return report | {'scope': 'latest_cumulative_worker_snapshots',
        'collection_complete': complete, 'workers_seen': len(WIRE_WORKERS_SEEN),
        'workers_reported': len(WIRE_WORKERS),
        'workers_final': sum(value['final'] for value in WIRE_WORKERS.values()),
        'collection_error': WIRE_REPORT_ERROR}


@events.test_start.add_listener
def validate_host(environment, **kwargs):
    global PROGRESS_INDEX, PROGRESS_OBSERVER
    target_url(environment.host)
    if PROGRESS_PROFILE is not None:
        from locust.runners import LocalRunner
        if not isinstance(environment.runner, LocalRunner) or PROGRESS_INDEX is not None:
            raise ValueError('loadtest_progress_requires_fresh_local_worker')
        folder = Path(os.environ['LOADTEST_REPORT_DIRECTORY']).resolve()
        if not folder.is_dir() or folder.is_relative_to(Path(__file__).resolve().parents[2]):
            raise ValueError('external_report_directory_required')
        PROGRESS_INDEX = ProgressIndex(CFG['active'], CFG['accounts'])
        PROGRESS_OBSERVER = ProgressObservation(PROGRESS_INDEX, folder, run_id=CFG['run_id'],
            manifest_sha256=sha(canonical(CFG)), controller=CONTROLLER)
        if not PROGRESS_OBSERVER.sample():
            raise ValueError('loadtest_progress_observation_failed')
        import gevent
        def sample_progress():
            global RUN_EXIT_PROBE_TRIGGERED, DEPARTURE_WAVE
            while not RUN_STOPPING:
                gevent.sleep(5)
                if not RUN_STOPPING and not PROGRESS_OBSERVER.sample():
                    fail_run(environment, 'actor_progress_not_confirmed')
                    return
                if EXIT_PROBE is not None and not RUN_STOPPING and not RUN_EXIT_PROBE_TRIGGERED:
                    snap=PROGRESS_OBSERVER.last_snapshot
                    if snap is not None and snap['all_active'] and snap['best_seconds']>=EXIT_PROBE['common_seconds']+15:
                        RUN_EXIT_PROBE_TRIGGERED=True
                        if EXIT_MODE=='gradual120-v1':
                            try:
                                DEPARTURE_WAVE=DepartureWave(environment,EXIT_PROBE['wave_seconds'])
                                DEPARTURE_WAVE.start()
                            except Exception:fail_run(environment,'departure_wave_start_failed');return
                        else:
                            gevent.spawn(environment.runner.quit)
                            return
        gevent.spawn(sample_progress)
    if environment.parsed_options.num_users and environment.parsed_options.num_users > CFG['active']:
        raise ValueError('virtual_users_exceed_manifest_budget')
    from locust.runners import WorkerRunner
    if not isinstance(environment.runner, WorkerRunner):
        import gevent
        def monitor():
            previous_requests = previous_failures = bad = 0
            while environment.runner.state not in ('stopped', 'stopping', 'cleanup'):
                gevent.sleep(5)
                total = environment.stats.total
                requests, failures = total.num_requests - previous_requests, total.num_failures - previous_failures
                previous_requests, previous_failures = total.num_requests, total.num_failures
                bad = bad + 1 if requests >= 100 and failures / requests > .05 else 0
                if bad >= 2:
                    if OBSERVE_OVERLOAD:
                        OBSERVATION_COUNTS['failure_rate_windows'] += 1
                        bad = 0
                        continue
                    fail_run(environment, 'failure_rate_budget_exceeded')
                    return
        gevent.spawn(monitor)


@events.test_stopping.add_listener
def mark_stopping(environment, **kwargs):
    global RUN_STOPPING, RUN_STOPPING_AT, PROGRESS_FROZEN
    RUN_STOPPING = True
    wave=globals().get('DEPARTURE_WAVE')
    if wave is not None:wave.stop_dispatch()
    if CLIENT_PROFILE.mode in ('client-v2', 'client-v3') and RUN_STOPPING_AT is None:
        RUN_STOPPING_AT = time.monotonic()
    if PROGRESS_INDEX is not None and not PROGRESS_FROZEN:
        try:
            PROGRESS_INDEX.freeze(RUN_STOPPING_AT)
            PROGRESS_FROZEN = True
        except Exception:
            fail_run(environment, 'actor_progress_not_confirmed')


class DepartureWave:
    """One O(N) owned-user snapshot, one coordinator, O(1) per departure.

    Until each scheduled intent, that actor continues normal business. No
    periodic user scan, replacement actor, hidden finalization wait or retry.
    """
    def __init__(self,environment,seconds,*,clock=time.monotonic,sleep=None):
        import gevent
        if type(seconds)not in(int,float)or seconds not in(2,120):raise ValueError('departure_wave_seconds_invalid')
        users=[]
        for item in environment.runner.user_greenlets:
            if not item.dead and item.args and isinstance(item.args[0],SyntheticPlayer):users.append(item.args[0])
        if len(users)!=CFG['active']or len(users)<2:raise ValueError('departure_wave_target_not_ready')
        self.environment,self.seconds,self.clock,self.sleep=environment,float(seconds),clock,sleep or gevent.sleep
        self.users=tuple(users);self.target=len(users);self.started_at=clock();self.task=None
        self.scheduled=self.finished_count=self.early_finished=0;self.cancelled=False
        self.first_offset_ms=self.last_offset_ms=None;self.max_lag_ms=0.0
        self.early_timer_wakes=0;self.max_timer_early_ms=0.0
        for user in self.users:user._exit_wave_owner=self;user._exit_wave_finished=False
    def start(self):
        import gevent
        if self.task is not None:raise ValueError('departure_wave_already_started')
        self.task=gevent.spawn(self.run)
    def run(self):
        try:
            for index,user in enumerate(self.users):
                planned=self.started_at+self.seconds*index/(self.target-1)
                self.sleep(max(0,planned-self.clock()))
                if RUN_STOPPING:self.cancelled=True;return
                if user.greenlet.dead:continue
                # A sleep is only a wakeup hint. The monotonic deadline is
                # authoritative, including after repeated coarse libuv wakes.
                # At most eight corrective yields; no user collection scan.
                for correction in range(8):
                    actual=self.clock()
                    if actual>=planned:break
                    self.early_timer_wakes+=1
                    self.max_timer_early_ms=max(self.max_timer_early_ms,(planned-actual)*1000)
                    self.sleep(max(.010,planned-actual+.002))
                    if RUN_STOPPING:self.cancelled=True;return
                    if user.greenlet.dead:break
                if user.greenlet.dead:continue
                actual=self.clock()
                if actual<planned:raise ValueError('departure_timer_still_early')
                user._exit_wave_intent=planned
                offset=(actual-self.started_at)*1000
                if self.first_offset_ms is None:self.first_offset_ms=offset
                self.last_offset_ms=offset;self.max_lag_ms=max(self.max_lag_ms,max(0,(actual-planned)*1000));self.scheduled+=1
                user.stop(force=False)
        except Exception:
            self.cancelled=True;fail_run(self.environment,'departure_wave_dispatch_failed')
    def finished(self,user):
        if getattr(user,'_exit_wave_owner',None)is not self or getattr(user,'_exit_wave_finished',False):return
        user._exit_wave_finished=True;self.finished_count+=1
        self.early_finished+=int(getattr(user,'_exit_wave_intent',None)is None)
        if self.finished_count==self.target:
            import gevent
            gevent.spawn(self.environment.runner.quit)
    def stop_dispatch(self):
        if self.finished_count!=self.target:self.cancelled=True
        if self.task is not None and not self.task.ready():self.task.kill(block=False)
    def report(self):
        return dict(target=self.target,scheduled=self.scheduled,finished=self.finished_count,
            early_finished=self.early_finished,cancelled=self.cancelled,window_seconds=self.seconds,
            first_actual_intent_offset_ms=self.first_offset_ms,last_actual_intent_offset_ms=self.last_offset_ms,
            max_intent_schedule_lag_ms=self.max_lag_ms,early_timer_wakes=self.early_timer_wakes,
            max_timer_early_ms=self.max_timer_early_ms,remaining_actors_keep_business=True,
            per_actor_cleanup_deadline_seconds=45,whole_wave_is_not_one_simultaneous_intent=True)


class ExitCooperativeTaskSet(TaskSet):
    @task
    def activity(self):
        self.user.activity()

    def _sleep(self, seconds):
        # Reuse one per-user Event; normal quit wakes waits without injecting a kill.
        self.user._normal_stop_event.wait(timeout=seconds)


_HTTPBase=HttpUser
if os.environ.get('LOADTEST_FAST_HTTP')=='1':
    from fast_transport import BudgetFastHttpUser as _HTTPBase

class SyntheticPlayer(_HTTPBase):
    host = 'http://127.0.0.1:29567'
    tasks = [ExitCooperativeTaskSet]

    def __init__(self, environment):
        super().__init__(environment)
        self._normal_stop_event = Event()

    def stop(self, force=False):
        if not force and (RUN_STOPPING or getattr(self,'_exit_wave_intent',None)is not None):
            self._state = LOCUST_STATE_STOPPING
            self._normal_stop_event.set()
            return False
        return super().stop(force=force)


    def wait_time(self):
        if getattr(self, '_isolated_failure', False):
            return 30
        next_due = min(self.next_activity, self.player.next_checkpoint)
        if CLIENT_PROFILE.mode == 'client-v3':
            from loadtest_lab.workload import compact_rooms
            try:
                next_due=min(next_due,compact_rooms().next_poll(self.player))
            except ValueError as error:
                if not self.isolate_dependency(error):
                    fail_run(self.environment, 'workflow_invariant_failed')
                    raise StopUser() from None
                return 30
        return max(.05, next_due - time.monotonic())

    def record_workflow(self, name, elapsed_ms, error, counters):
        # Fixed names/counters only: no account, token, grant or payload data.
        if name not in WORKFLOWS or set(counters) != set(WORKLOAD_COUNTERS):
            raise ValueError('loadtest_workflow_metric_invalid')
        validate_workload_counters(counters)
        for key in WORKLOAD_COUNTERS:
            WORKLOAD_COUNTS[key] += counters[key]
        safe = None if error is None else ValueError(failure_label(error, 'workflow_not_confirmed'))
        self.environment.events.request.fire(request_type='WORKFLOW', name=name,
            response_time=elapsed_ms, response_length=0, exception=safe,
            context={'client_workload': CLIENT_PROFILE.mode})

    def fail_actor(self, reason, *, transport=False):
        """O(1) quarantine; no replay, respawn, identity scan or hidden success.

        Setup O(1), stable quarantined actors wake once per 30s without HTTP.
        Genuine schema/source/integrity errors retain the global stop barrier.
        """
        if OBSERVE_OVERLOAD and transport:
            OBSERVATION_COUNTS['isolated_errors'] += 1
            if not getattr(self, '_isolated_failure', False):
                OBSERVATION_COUNTS['quarantined_actors'] += 1
            self._isolated_failure = True
            self.environment.process_exit_code = 2
        else:
            fail_run(self.environment, reason)

    def isolate_dependency(self, error):
        if (OBSERVE_OVERLOAD and not RUN_FAILED and str(error) in
                ('compact_room_startup_timeout', 'compact_room_catalog_unavailable')):
            self.fail_actor(str(error), transport=True)
            self.environment.events.request.fire(request_type='ASSERT', name='room_dependency_unavailable',
                response_time=0, response_length=0, exception=ValueError(str(error)), context={})
            return True
        return False

    def exchange(self, method, path, body, authorization, name):
        business = WIRE.business(method, path)
        if (CLIENT_RECOVERY is None or not business
                and CLIENT_RECOVERY.get('retry_setup_control') != 1):
            return self._exchange_once(method, path, body, authorization, name)
        import gevent
        counters = RECOVERY_COUNTS if business else CONTROL_RECOVERY_COUNTS
        final_checkpoint = (method == 'POST' and path == '/v1/online-time/checkpoint'
                            and name == '[checkpoint:final] /v1/online-time/checkpoint'
                            and type(body) is dict and body.get('final') is True)
        budget = BusyRetryBudget(CFG, final_checkpoint=final_checkpoint)
        counters['logical_requests'] += 1
        route = RECOVERY_ROUTES.begin(method, path, name) if RECOVERY_ROUTES is not None else None
        had_busy = False
        logical_started, logical_succeeded = time.monotonic(), False
        try:
            with gevent.Timeout(budget.remaining(), BusyRetryDeadline()):
                for _ in range(budget.max_attempts):
                    remaining = budget.begin()
                    counters['http_attempts'] += 1
                    if route is not None: route['http_attempts'] += 1
                    counters['retry_attempts'] += int(budget.attempts > 1)
                    try:
                        value = self._exchange_once(method, path, body, authorization, name,
                                                    busy_recovery=True, timeout=remaining)
                    except AdmissionBusy as error:
                        counters['requests_with_busy'] += int(not had_busy)
                        had_busy = True
                        counters['busy_responses'] += 1
                        counters[error.code] += 1
                        if route is not None: route['busy_responses'] += 1
                        delay = budget.delay(random.random())
                        if delay is None:
                            counters['exhausted_requests'] += 1
                            self.fail_actor('admission_retry_exhausted', transport=True)
                            raise StopUser() from None
                        gevent.sleep(delay)
                        continue
                    logical_succeeded = True
                    counters['logical_completed'] += 1
                    counters['recovered_requests'] += int(had_busy)
                    return value
        except BusyRetryDeadline:
            counters['logical_failed'] += 1
            self.fail_actor('admission_retry_deadline', transport=True)
            raise StopUser() from None
        except BaseException:
            counters['logical_failed'] += 1
            raise
        finally:
            if business:
                RECOVERY_TIMINGS.observe(path, name, (time.monotonic() - logical_started) * 1000,
                                         not logical_succeeded)
            if route is not None:
                RECOVERY_ROUTES.finish(route, logical_succeeded, had_busy)

    def _exchange_once(self, method, path, body, authorization, name,
                       *, busy_recovery=False, timeout=35):
        if (getattr(self, '_finalizing', False)
                and time.monotonic() >= getattr(self, '_cleanup_deadline', float('inf'))):
            raise CleanupTimeout()
        if RUN_FAILED:
            existing = getattr(self, 'player', None)
            cleanup = (getattr(self, '_finalizing', False) and existing is not None
                       and existing.identity is not None and method == 'POST'
                       and (path in ('/v1/online-time/checkpoint', '/_loadtest/release')
                            or CLIENT_PROFILE.mode in ('client-v2', 'client-v3') and path == '/v1/profile'
                            and getattr(existing, 'grant_followup_final', False)))
            if not cleanup:
                raise StopUser()
        # Every attempt keeps its raw HTTP failure and wire accounting.
        headers = WIRE.headers(method, path, authorization)
        profile_context = profile_scope = None
        if CFG.get('profile_read_cache') == 'unchanged-v1' and method == 'POST' and path in ('/v1/profile', '/v1/online-time/checkpoint'):
            profile_scope = (authorization, body.get('account_id'), body.get('match_session_id'))
            saved = getattr(self, '_profile_read_baseline', None)
            baseline = saved[1] if saved is not None and saved[0] == profile_scope else None
            profile_context = {'baseline': baseline if path == '/v1/profile' else None}
            headers['X-Survival-Profile-Cache'] = profile_cache_header(baseline if path == '/v1/profile' else None)
        entered = False
        try:
            with self.client.request(method, path, json=body, headers=headers,
                                     name=name, timeout=timeout, allow_redirects=False, catch_response=True) as response:
                entered = True
                try:
                    try:
                        value = WIRE.decode(method, path, response.content, response.status_code, request_body=body,
                                            profile_context=profile_context if response.status_code == 200 else None)
                        if profile_context is not None and response.status_code == 200:
                            # This cache belongs to this single synthetic actor. The
                            # ordinary profile identity/session checks remain below.
                            snapshot = value if path == '/v1/profile' else value.get('profile')
                            if (type(snapshot) is not dict or snapshot.get('account_id') != body.get('account_id')
                                    or snapshot.get('match_session_id') != body.get('match_session_id')):
                                raise ValueError('loadtest_profile_cache_identity_mismatch')
                            if path == '/v1/profile' or profile_context.get('next_state') is not None:
                                self._profile_read_baseline = (profile_scope, profile_context.get('next_state'))
                    except Exception:
                        if response.status_code != 200:
                            raise ValueError(http_error_label(response.status_code, None)) from None
                        raise
                    if (busy_recovery and response.status_code == 503
                            and type(value) is dict and set(value) == {'ok', 'error'}
                            and value.get('ok') is False
                            and value.get('error') in ('backend_busy', 'frontend_busy')):
                        response.failure(http_error_label(503, value))
                        raise AdmissionBusy(value['error'])
                    if response.status_code != 200:
                        raise ValueError(http_error_label(response.status_code, value))
                    value = checked(value)
                except AdmissionBusy:
                    raise
                except Exception as error:
                    safe = failure_label(error)
                    response.failure(safe)
                    self.fail_actor(safe, transport=response.status_code in (0, 429, 500, 502, 503, 504))
                    raise StopUser() from None
                if (PROGRESS_INDEX is not None and WIRE.business(method, path)
                        and not getattr(self, '_finalizing', False) and not RUN_STOPPING):
                    self._progress_last_success = time.monotonic()
                    slot = getattr(self, '_progress_slot', None)
                    if slot is not None:
                        try:
                            PROGRESS_INDEX.success(slot, self)
                        except Exception:
                            fail_run(self.environment, 'actor_progress_not_confirmed')
                            raise StopUser() from None
                return value
        except BaseException as error:
            if not entered:
                WIRE.note_incomplete(error, method, path)
            raise

    def on_start(self):
        RUN_COUNTERS['start_attempts'] += 1
        if RUN_FAILED:
            RUN_COUNTERS['start_blocked_after_failure'] += 1
            raise StopUser()
        try:
            target_url(self.environment.host or self.host)
            if 'generator_transport'in CFG:
                self.client.base_url=generator_url(CFG,RUN_COUNTERS['start_attempts']-1)
            if CLIENT_PROFILE.mode == 'client-v3':
                from locust.runners import LocalRunner
                if not isinstance(self.environment.runner, LocalRunner):
                    raise ValueError('compact_client_requires_single_local_worker')
            self._finalizing = False
            self._progress_slot = self._progress_last_success = None
            if CLIENT_PROFILE.mode in ('client-v2', 'client-v3'):
                self.player = Player(self.exchange, CFG, CONTROLLER,
                                     workflow_observer=self.record_workflow)
            else:
                self.player = Player(self.exchange, CFG, CONTROLLER)
            self.player.start()
            if PROGRESS_INDEX is not None and not RUN_STOPPING:
                slot = int(self.player.identity['account_id']) - CFG['account_start']
                PROGRESS_INDEX.register(slot, self, self._progress_last_success)
                self._progress_slot = slot
            self.next_activity = time.monotonic()
        except StopUser:
            if OBSERVE_OVERLOAD and getattr(self, '_isolated_failure', False):
                return
            if not RUN_FAILED:
                fail_run(self.environment, 'workflow_start_stopped')
            raise
        except Exception as error:
            if self.isolate_dependency(error):
                return
            self.environment.events.request.fire(request_type='ASSERT', name='workflow_start',
                response_time=0, response_length=0, exception=ValueError('workflow_start_not_confirmed'), context={})
            fail_run(self.environment, 'workflow_start_not_confirmed')
            raise StopUser() from None

    def activity(self):
        # Locust can wake a waiting user before its scheduled kill arrives.
        # Finish existing workflows, but never begin a new one after quit intent.
        if RUN_STOPPING:
            raise StopUser()
        try:
            if OBSERVE_OVERLOAD and getattr(self, '_isolated_failure', False):
                return
            if RUN_FAILED:
                raise StopUser()
            player = self.player
            if player.clock() >= player.next_checkpoint:
                player.checkpoint()
            if CLIENT_PROFILE.mode == 'client-v3':
                from loadtest_lab.workload import compact_rooms
                compact_rooms().tick(player)
            if time.monotonic() < self.next_activity:
                return
            self.next_activity = time.monotonic() + random.uniform(15, 30)
            draw = random.random()
            if not player.claimed:
                player.claim(replay=random.random() < .01)
            elif draw < .45:
                player.read_profile()
            elif draw < .65:
                player.local_view() if CLIENT_PROFILE.mode == 'client-v3' else player.snapshot()
            elif draw < .75:
                player.local_view() if CLIENT_PROFILE.mode == 'client-v3' else player.catalog()
            elif draw < .90:
                player.endless_batch(1)
            else:
                player.draw(replay=random.random() < .05)
        except StopUser:
            if OBSERVE_OVERLOAD and getattr(self, '_isolated_failure', False):
                return
            if not RUN_FAILED:
                fail_run(self.environment, 'workflow_activity_stopped')
            raise
        except Exception as error:
            if self.isolate_dependency(error):
                return
            self.environment.events.request.fire(request_type='ASSERT', name='workflow_state',
                response_time=0, response_length=0, exception=ValueError('workflow_invariant_failed'), context={})
            fail_run(self.environment, 'workflow_invariant_failed')
            raise StopUser() from None

    def _finish_with_exit_policy(self):
        import gevent
        from contextlib import nullcontext
        if EXIT_MODE=='jitter3-v1':
            delay_ms=(int(self.player.identity['account_id'])%61)*50
            EXIT_METRICS['delay_ms']+=delay_ms
            gevent.sleep(delay_ms/1000)
        if EXIT_SEMAPHORE is not None and EXIT_SEMAPHORE.locked():
            EXIT_METRICS['queued']+=1
        with EXIT_SEMAPHORE if EXIT_SEMAPHORE is not None else nullcontext():
            EXIT_METRICS['active']+=1
            EXIT_METRICS['peak']=max(EXIT_METRICS['peak'],EXIT_METRICS['active'])
            try:
                if CLIENT_PROFILE.mode in ('client-v2','client-v3'):
                    intent=getattr(self,'_exit_wave_intent',None)
                    self.player.stop(intent_started=RUN_STOPPING_AT if intent is None else intent)
                else:
                    self.player.stop()
                EXIT_METRICS['completed']+=1
            finally:
                EXIT_METRICS['active']-=1

    def on_stop(self):
        if hasattr(self, 'player') and not getattr(self, '_cleanup_started', False):
            self._cleanup_started = True
            self._finalizing = True
            import gevent
            budget = cleanup_budget(self.environment)
            personal=getattr(self,'_exit_wave_intent',None)
            if personal is not None:budget=max(0.0,min(budget,personal+45-time.monotonic()))
            self._cleanup_deadline = time.monotonic() + budget
            RUN_COUNTERS['cleanup_attempts'] += 1
            try:
                # Locust's async stop of a waiting user joins on_stop before its
                # stop-group timeout. Bound this multi-request cleanup itself.
                if budget<=0:raise CleanupTimeout()
                with gevent.Timeout(budget, CleanupTimeout()):
                    self._finish_with_exit_policy()
                RUN_COUNTERS['cleanup_completed'] += 1
            except CleanupTimeout:
                RUN_COUNTERS['cleanup_interrupted'] += 1
                self.environment.events.request.fire(request_type='ASSERT', name='final_checkpoint_or_release',
                    response_time=0, response_length=0, exception=ValueError('finalization_interrupted'), context={})
                if OBSERVE_OVERLOAD:
                    OBSERVATION_COUNTS['cleanup_timeouts'] += 1
                    self.fail_actor('finalization_interrupted', transport=True)
                else:
                    fail_run(self.environment, 'finalization_interrupted')
            except StopUser:
                RUN_COUNTERS['cleanup_failed'] += 1
                self.environment.events.request.fire(request_type='ASSERT', name='final_checkpoint_or_release',
                    response_time=0, response_length=0, exception=ValueError('finalization_not_confirmed'), context={})
                if not (OBSERVE_OVERLOAD and getattr(self, '_isolated_failure', False)):
                    fail_run(self.environment, 'finalization_not_confirmed')
            except Exception:
                RUN_COUNTERS['cleanup_failed'] += 1
                self.environment.events.request.fire(request_type='ASSERT', name='final_checkpoint_or_release',
                    response_time=0, response_length=0, exception=ValueError('finalization_not_confirmed'), context={})
                fail_run(self.environment, 'finalization_not_confirmed')
            except BaseException:
                RUN_COUNTERS['cleanup_interrupted'] += 1
                fail_run(self.environment, 'finalization_interrupted')
                raise
            finally:
                self._finalizing = False
                wave=globals().get('DEPARTURE_WAVE')
                if wave is not None:wave.finished(self)
                slot = getattr(self, '_progress_slot', None)
                if slot is not None:
                    self._progress_slot = None
                    try:
                        PROGRESS_INDEX.depart(slot, self)
                    except Exception:
                        fail_run(self.environment, 'actor_progress_not_confirmed')


def workload_statistics(environment, run):
    if CLIENT_PROFILE.mode not in ('client-v2', 'client-v3'):
        return {}
    counters = run['workload_counters']
    entries = {entry.name: entry for entry in environment.stats.entries.values()
               if entry.method == 'WORKFLOW'}
    if set(entries) - set(WORKFLOWS):
        raise ValueError('loadtest_workflow_name_invalid')
    rows = []
    for name in WORKFLOWS:
        entry = entries.get(name)
        count = 0 if entry is None else entry.num_requests
        rows.append({'name': name, 'requests': count,
                     'failures': 0 if entry is None else entry.num_failures,
                     'mean_ms': None if not count else entry.total_response_time / count,
                     'max_ms': None if not count else entry.max_response_time,
                     'p95_ms': None if not count else entry.get_response_time_percentile(.95)})
    checkpoint_count = sum(row['requests'] for row in rows if row['name'].startswith('checkpoint_'))
    final_count = next(row['requests'] for row in rows if row['name'] == 'finalization')
    return {**({'compact_client': __import__('loadtest_lab.workload',fromlist=['compact_rooms']).compact_rooms().report()} if CLIENT_PROFILE.mode == 'client-v3' else {}),
            'client_workload': CLIENT_PROFILE.mode, 'workload_counters': counters,
            'workflow_statistics': rows,
            'workflow_statistics_complete': checkpoint_count == counters['checkpoint_attempts']
                and final_count == counters['finalization_attempts'],
            'workflow_timing_scope': ('WORKFLOW finalization starts at EACH scheduled departure intent; actors keep business until own intent, personal45s deadline includes pending work/checkpoint/followup/release; 2s native or120s full cohort window is not simultaneous intent.'if EXIT_MODE=='gradual120-v1'else'WORKFLOW checkpoint includes grant followup profile; finalization starts at worker test_stopping intent before cleanup scheduling and includes checkpoint, followup, release. WORKFLOW is not HTTP.')}


@events.quitting.add_listener
def exit_on_failure(environment, **kwargs):
    if environment.stats.total.num_failures or RUN_FAILED:
        environment.process_exit_code = 2
    from locust.runners import WorkerRunner
    if isinstance(environment.runner, WorkerRunner):
        environment.runner.send_message('survival_wire_final', {'wire': WIRE.report(), 'run_state': run_state()})
        return  # Master owns aggregate evidence; workers never overwrite it.
    try:
        folder = Path(os.environ.get('LOADTEST_REPORT_DIRECTORY',
                                     str(Path(os.environ['LOADTEST_CLIENT']).resolve().parent))).resolve()
        project = Path(__file__).resolve().parents[2]
        if not folder.is_dir() or folder.is_relative_to(project):
            raise ValueError('external_report_directory_required')
        total = environment.stats.total
        wire = final_wire_report(environment)
        run = final_run_state(environment)
        workload = workload_statistics(environment, run)
        progress = None if PROGRESS_OBSERVER is None else PROGRESS_OBSERVER.finish()
        if PROGRESS_PROFILE is not None and (progress is None or not progress['complete']):
            environment.process_exit_code = 2
        http_requests = sum(entry.num_requests for entry in environment.stats.entries.values()
                            if entry.method in ('GET', 'POST', 'HEAD', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'))
        if http_requests != wire['counters']['requests']:
            wire['collection_complete'] = False
        if not wire['collection_complete'] or not run['collection_complete']:
            environment.process_exit_code = 2
        if workload and not workload['workflow_statistics_complete']:
            environment.process_exit_code = 2
        path = folder / ('locust_final_' + secrets.token_hex(8) + '_receipt.json')
        write_new(path, {'kind': 'REAL_BUSINESS_LOCUST_FINAL_RECEIPT', 'artifact_root': str(folder),
            'run_id': CFG['run_id'], 'manifest_sha256': sha(canonical(CFG)),
            'requests': total.num_requests, 'failures': total.num_failures,
            'includes_user_finalization': True, 'capacity_certified': False,
            'business_wire': wire,
            'client_decode_offload':None if not hasattr(WIRE,'_decode_offload_snapshot')else WIRE._decode_offload_snapshot(),
            **({'overload_observation': {'mode': 'observe-overload-v1',
                'counters': dict(OBSERVATION_COUNTS), 'capacity_certified': False,
                'quarantined_users_are_not_active_business_users': True,
                'automatic_respawn_or_ambiguous_replay': False}} if OBSERVE_OVERLOAD else {}),
            **({'client_recovery': {'policy': CLIENT_RECOVERY, 'counters': dict(RECOVERY_COUNTS),
                'logical_latency': RECOVERY_TIMINGS.report(),
                **({'control_counters': dict(CONTROL_RECOVERY_COUNTS),
                    'route_counts': RECOVERY_ROUTES.report()} if RECOVERY_ROUTES is not None else {}),
                'scope': 'single local runner; explicit pre-dispatch HTTP503 busy only; raw failures retained',
                'automatic_ambiguous_mutation_retries': False}} if CLIENT_RECOVERY is not None else {}),
            'run_state': run,
            'http_timing_scope': 'locust_http_time_excludes_client_wire_decode',
            **workload,
            **({'actor_progress': progress} if PROGRESS_PROFILE is not None else {}),
            **({'http_requests': http_requests,
                'http_failures': sum(entry.num_failures for entry in environment.stats.entries.values()
                    if entry.method in ('GET', 'POST', 'HEAD', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'))}
               if CLIENT_PROFILE.mode in ('client-v2', 'client-v3') else {}),
            'reset_stats_requested': bool(getattr(environment.parsed_options, 'reset_stats', False)),
            'routes': [{'method': entry.method, 'name': entry.name,
                        'requests': entry.num_requests, 'failures': entry.num_failures}
                       for entry in environment.stats.entries.values()]})
        import json
        print(json.dumps({'status': 'FINAL_STATISTICS_SAVED', 'receipt': str(path),
                          'storage_registration': register_storage(path)}), flush=True)
    except Exception:
        environment.process_exit_code = 2
        print('final_statistics_not_saved', flush=True)
