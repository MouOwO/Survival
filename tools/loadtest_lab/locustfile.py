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
from loadtest_lab.wire_client import WireClient, WIRE_MODE, aggregate_reports, http_error_label, failure_label
from locust import HttpUser, task, events
from locust.exception import StopUser

CFG, CONTROLLER = load_client(os.environ['LOADTEST_CLIENT'])
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
RUN_COUNTERS = dict.fromkeys(('start_attempts', 'start_blocked_after_failure',
                             'cleanup_attempts', 'cleanup_completed', 'cleanup_failed', 'cleanup_interrupted'), 0)


def run_state():
    return {'failed': RUN_FAILED, 'first_failure': RUN_FIRST_FAILURE,
            'quit_requested': RUN_QUIT_REQUESTED, 'notification_failed': RUN_NOTIFICATION_FAILED,
            'counters': dict(RUN_COUNTERS)}


def fail_run(environment, reason, *, notify_master=True):
    """Set the barrier before yielding; only one asynchronous stage stop."""
    global RUN_FAILED, RUN_FIRST_FAILURE, RUN_QUIT_REQUESTED, RUN_NOTIFICATION_FAILED
    safe = failure_label(reason, 'workflow_not_confirmed')
    if not RUN_FAILED:
        RUN_FAILED, RUN_FIRST_FAILURE = True, safe
    if environment is None:
        return
    environment.process_exit_code = 2
    if RUN_QUIT_REQUESTED or environment.runner is None:
        return
    RUN_QUIT_REQUESTED = True
    from locust.runners import WorkerRunner, MasterRunner
    runner = environment.runner
    try:
        if isinstance(runner, WorkerRunner) and notify_master:
            runner.send_message('survival_run_failed', {'error': RUN_FIRST_FAILURE})
        elif isinstance(runner, MasterRunner):
            runner.send_message('survival_run_abort', {'error': RUN_FIRST_FAILURE})
    except Exception:
        RUN_NOTIFICATION_FAILED = True
    import gevent
    def stop_stage():
        global RUN_NOTIFICATION_FAILED
        if isinstance(runner, WorkerRunner):
            # Master acknowledgement proves the whole run was told to stop.
            runner.stop()
            if RUN_ABORT_ACK is None or not RUN_ABORT_ACK.wait(timeout=10):
                RUN_NOTIFICATION_FAILED = True
            runner.quit()
        else:
            if isinstance(runner, MasterRunner):
                try:
                    if RUN_MASTER_RAMP is not None and not RUN_MASTER_RAMP.ready():
                        RUN_MASTER_RAMP.kill(block=True)
                    RUN_PENDING_WORKERS.update(client.id for client in runner.clients.all
                        if not (WIRE_WORKERS.get(client.id, {}).get('final')
                                and WIRE_WORKERS.get(client.id, {}).get('run_state') is not None))
                    # Worker abort owns cleanup. Standard stop removes workers
                    # from Locust's index before quit can reach them.
                    runner.stop(send_stop_to_client=False)
                    deadline = time.monotonic() + (environment.stop_timeout or 0) + 15
                    while RUN_PENDING_WORKERS and time.monotonic() < deadline:
                        gevent.sleep(.05)
                    if RUN_PENDING_WORKERS:
                        RUN_NOTIFICATION_FAILED = True
                finally:
                    runner.quit()
            else:
                runner.quit()
    gevent.spawn(stop_stage)


def validate_run_state(state):
    if (type(state) is not dict or type(state.get('failed')) is not bool
            or type(state.get('quit_requested')) is not bool
            or type(state.get('notification_failed')) is not bool
            or type(state.get('counters')) is not dict
            or set(state['counters']) != set(RUN_COUNTERS)
            or any(type(value) is not int or value < 0 for value in state['counters'].values())
            or state.get('first_failure') is not None
            and failure_label(state['first_failure'], 'invalid_worker_failure') != state['first_failure']):
        raise ValueError('loadtest_worker_run_state_invalid')


def final_run_state(environment):
    from locust.runners import MasterRunner
    if not isinstance(environment.runner, MasterRunner):
        return run_state() | {'scope': 'this_process', 'collection_complete': True}
    states = [value.get('run_state') for value in WIRE_WORKERS.values()]
    complete = (bool(WIRE_WORKERS_SEEN) and set(WIRE_WORKERS) == WIRE_WORKERS_SEEN
                and all(value['final'] and value.get('run_state') is not None for value in WIRE_WORKERS.values())
                and not WIRE_REPORT_ERROR)
    counters = dict.fromkeys(RUN_COUNTERS, 0)
    for state in states:
        if state is not None:
            for name in counters:
                counters[name] += state['counters'][name]
    return run_state() | {'scope': 'latest_cumulative_worker_snapshots',
                         'counters': counters, 'collection_complete': complete}


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
        if final and state is not None:
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
        environment.runner.register_message('survival_run_abort', abort)


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
    global WIRE_FINAL
    from locust.runners import WorkerRunner
    WIRE_FINAL = True
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
        return WIRE.report() | {'scope': 'this_process', 'collection_complete': True}
    complete = (bool(WIRE_WORKERS_SEEN) and set(WIRE_WORKERS) == WIRE_WORKERS_SEEN
                and all(value['final'] for value in WIRE_WORKERS.values()) and not WIRE_REPORT_ERROR)
    report = aggregate_reports((value['report'] for value in WIRE_WORKERS.values()), WIRE.mode)
    return report | {'scope': 'latest_cumulative_worker_snapshots',
        'collection_complete': complete, 'workers_seen': len(WIRE_WORKERS_SEEN),
        'workers_reported': len(WIRE_WORKERS),
        'workers_final': sum(value['final'] for value in WIRE_WORKERS.values()),
        'collection_error': WIRE_REPORT_ERROR}


@events.test_start.add_listener
def validate_host(environment, **kwargs):
    target_url(environment.host)
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


class SyntheticPlayer(HttpUser):
    host = 'http://127.0.0.1:29567'

    def wait_time(self):
        return max(.05, min(self.next_activity, self.player.next_checkpoint) - time.monotonic())

    def exchange(self, method, path, body, authorization, name):
        if RUN_FAILED:
            existing = getattr(self, 'player', None)
            cleanup = (getattr(self, '_finalizing', False) and existing is not None
                       and existing.identity is not None and method == 'POST'
                       and path in ('/v1/online-time/checkpoint', '/_loadtest/release'))
            if not cleanup:
                raise StopUser()
        # Locust follows redirects by default; explicitly disable that path.
        with self.client.request(method, path, json=body, headers=WIRE.headers(method, path, authorization),
                                 name=name, timeout=35, allow_redirects=False, catch_response=True) as response:
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
            return value

    def on_start(self):
        RUN_COUNTERS['start_attempts'] += 1
        if RUN_FAILED:
            RUN_COUNTERS['start_blocked_after_failure'] += 1
            raise StopUser()
        try:
            target_url(self.environment.host or self.host)
            self._finalizing = False
            self.player = Player(self.exchange, CFG, CONTROLLER)
            self.player.start()
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
            if time.monotonic() < self.next_activity:
                return
            self.next_activity = time.monotonic() + random.uniform(15, 30)
            draw = random.random()
            if not player.claimed:
                player.claim(replay=random.random() < .01)
            elif draw < .45:
                player.read_profile()
            elif draw < .65:
                player.snapshot()
            elif draw < .75:
                player.catalog()
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
            RUN_COUNTERS['cleanup_attempts'] += 1
            try:
                self.player.stop()
                RUN_COUNTERS['cleanup_completed'] += 1
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
        if not wire['collection_complete'] or not run['collection_complete']:
            environment.process_exit_code = 2
        path = folder / ('locust_final_' + secrets.token_hex(8) + '_receipt.json')
        write_new(path, {'kind': 'REAL_BUSINESS_LOCUST_FINAL_RECEIPT', 'artifact_root': str(folder),
            'run_id': CFG['run_id'], 'manifest_sha256': sha(canonical(CFG)),
            'requests': total.num_requests, 'failures': total.num_failures,
            'includes_user_finalization': True, 'capacity_certified': False,
            'business_wire': wire,
            'run_state': run,
            'http_timing_scope': 'locust_http_time_excludes_client_wire_decode',
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
