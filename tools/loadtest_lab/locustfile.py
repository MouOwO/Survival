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
from loadtest_lab.guard import load_client, target_url, canonical, sha, write_new, register_storage
from loadtest_lab.workload import Player, checked
from loadtest_lab.workload_profiles import COUNTERS as WORKLOAD_COUNTERS, WORKFLOWS, profile_for
from loadtest_lab.wire_client import WireClient, WIRE_MODE, aggregate_reports, http_error_label, failure_label
from locust import HttpUser, task, events
from locust.exception import StopUser
from loadtest_lab.progress import validate_profile as validate_actor_progress, ProgressIndex, ProgressObservation

CFG, CONTROLLER = load_client(os.environ['LOADTEST_CLIENT'])
CLIENT_PROFILE = profile_for(CFG)
PROGRESS_PROFILE = validate_actor_progress(CFG)
PROGRESS_INDEX = PROGRESS_OBSERVER = None
PROGRESS_FROZEN = False
WORKLOAD_COUNTS = dict.fromkeys(WORKLOAD_COUNTERS, 0)
WIRE = WireClient(CFG.get('wire_mode', WIRE_MODE))
WIRE_WORKERS = {}
WIRE_WORKERS_SEEN = set()
WIRE_FINAL = False
WIRE_REPORT_ERROR = None
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
            while not RUN_STOPPING:
                gevent.sleep(5)
                if not RUN_STOPPING and not PROGRESS_OBSERVER.sample():
                    fail_run(environment, 'actor_progress_not_confirmed')
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
                    fail_run(environment, 'failure_rate_budget_exceeded')
                    return
        gevent.spawn(monitor)


@events.test_stopping.add_listener
def mark_stopping(environment, **kwargs):
    global RUN_STOPPING, RUN_STOPPING_AT, PROGRESS_FROZEN
    RUN_STOPPING = True
    if CLIENT_PROFILE.mode in ('client-v2', 'client-v3') and RUN_STOPPING_AT is None:
        RUN_STOPPING_AT = time.monotonic()
    if PROGRESS_INDEX is not None and not PROGRESS_FROZEN:
        try:
            PROGRESS_INDEX.freeze(RUN_STOPPING_AT)
            PROGRESS_FROZEN = True
        except Exception:
            fail_run(environment, 'actor_progress_not_confirmed')


class SyntheticPlayer(HttpUser):
    host = 'http://127.0.0.1:29567'

    def wait_time(self):
        next_due = min(self.next_activity, self.player.next_checkpoint)
        if CLIENT_PROFILE.mode == 'client-v3':
            from loadtest_lab.workload import compact_rooms
            next_due=min(next_due,compact_rooms().next_poll(self.player))
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

    def exchange(self, method, path, body, authorization, name):
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
        # One attempt, no redirect or retry; preserve incomplete HTTP accounting.
        headers = WIRE.headers(method, path, authorization)
        entered = False
        try:
            with self.client.request(method, path, json=body, headers=headers,
                                     name=name, timeout=35, allow_redirects=False, catch_response=True) as response:
                entered = True
                try:
                    try:
                        value = WIRE.decode(method, path, response.content, response.status_code, request_body=body)
                    except Exception:
                        if response.status_code != 200:
                            raise ValueError(http_error_label(response.status_code, None)) from None
                        raise
                    if response.status_code != 200:
                        raise ValueError(http_error_label(response.status_code, value))
                    value = checked(value)
                except Exception as error:
                    safe = failure_label(error)
                    response.failure(safe)
                    fail_run(getattr(self, 'environment', None), safe)
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
                WIRE.note_incomplete(error)
            raise

    def on_start(self):
        RUN_COUNTERS['start_attempts'] += 1
        if RUN_FAILED:
            RUN_COUNTERS['start_blocked_after_failure'] += 1
            raise StopUser()
        try:
            target_url(self.environment.host or self.host)
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
            if not RUN_FAILED:
                fail_run(self.environment, 'workflow_start_stopped')
            raise
        except Exception:
            self.environment.events.request.fire(request_type='ASSERT', name='workflow_start',
                response_time=0, response_length=0, exception=ValueError('workflow_start_not_confirmed'), context={})
            fail_run(self.environment, 'workflow_start_not_confirmed')
            raise StopUser() from None

    @task
    def activity(self):
        try:
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
            if not RUN_FAILED:
                fail_run(self.environment, 'workflow_activity_stopped')
            raise
        except Exception:
            self.environment.events.request.fire(request_type='ASSERT', name='workflow_state',
                response_time=0, response_length=0, exception=ValueError('workflow_invariant_failed'), context={})
            fail_run(self.environment, 'workflow_invariant_failed')
            raise StopUser() from None

    def on_stop(self):
        if hasattr(self, 'player') and not getattr(self, '_cleanup_started', False):
            self._cleanup_started = True
            self._finalizing = True
            import gevent
            budget = cleanup_budget(self.environment)
            self._cleanup_deadline = time.monotonic() + budget
            RUN_COUNTERS['cleanup_attempts'] += 1
            try:
                # Locust's async stop of a waiting user joins on_stop before its
                # stop-group timeout. Bound this multi-request cleanup itself.
                with gevent.Timeout(budget, CleanupTimeout()):
                    if CLIENT_PROFILE.mode in ('client-v2', 'client-v3'):
                        self.player.stop(intent_started=RUN_STOPPING_AT)
                    else:
                        self.player.stop()
                RUN_COUNTERS['cleanup_completed'] += 1
            except CleanupTimeout:
                RUN_COUNTERS['cleanup_interrupted'] += 1
                self.environment.events.request.fire(request_type='ASSERT', name='final_checkpoint_or_release',
                    response_time=0, response_length=0, exception=ValueError('finalization_interrupted'), context={})
                fail_run(self.environment, 'finalization_interrupted')
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
            'workflow_timing_scope': 'WORKFLOW checkpoint includes grant followup profile; finalization starts at worker test_stopping intent before cleanup scheduling and includes checkpoint, followup, release. WORKFLOW is not HTTP.'}


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
