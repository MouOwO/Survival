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
from locust import HttpUser, task, events
from locust.exception import StopUser

CFG, CONTROLLER = load_client(os.environ['LOADTEST_CLIENT'])


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
                    environment.process_exit_code = 2
                    environment.runner.quit()
                    return
        gevent.spawn(monitor)


class SyntheticPlayer(HttpUser):
    host = 'http://127.0.0.1:29567'

    def wait_time(self):
        return max(.05, min(self.next_activity, self.player.next_checkpoint) - time.monotonic())

    def exchange(self, method, path, body, authorization, name):
        # Locust follows redirects by default; explicitly disable that path.
        with self.client.request(method, path, json=body, headers={'Authorization': authorization},
                                 name=name, timeout=35, allow_redirects=False, catch_response=True) as response:
            try:
                if response.status_code != 200:
                    raise ValueError('http_' + str(response.status_code))
                value = checked(response.json())
            except Exception as error:
                code = str(error)
                safe = code if code.replace('_', '').replace(':', '').isalnum() and len(code) < 100 else 'invalid_response'
                response.failure(safe)
                raise StopUser() from None
            return value

    def on_start(self):
        target_url(self.environment.host or self.host)
        self.player = Player(self.exchange, CFG, CONTROLLER)
        try:
            self.player.start()
            self.next_activity = time.monotonic()
        except StopUser:
            raise
        except Exception:
            self.environment.events.request.fire(request_type='ASSERT', name='workflow_start',
                response_time=0, response_length=0, exception=ValueError('workflow_start_not_confirmed'), context={})
            raise StopUser() from None

    @task
    def activity(self):
        try:
            player = self.player
            if player.clock() >= player.next_checkpoint:
                player.checkpoint()
            if time.monotonic() < self.next_activity:
                return
            self.next_activity = time.monotonic() + random.uniform(15, 30)
            draw = random.random()
            if not player.claimed:
                player.claim(replay=True)
            elif draw < .55:
                player.read_profile()
            elif draw < .85:
                player.snapshot()
            else:
                player.draw(replay=random.random() < .05)
        except StopUser:
            raise
        except Exception:
            self.environment.events.request.fire(request_type='ASSERT', name='workflow_state',
                response_time=0, response_length=0, exception=ValueError('workflow_invariant_failed'), context={})
            raise StopUser() from None

    def on_stop(self):
        if hasattr(self, 'player'):
            try:
                self.player.stop()
            except Exception:
                self.environment.events.request.fire(request_type='ASSERT', name='final_checkpoint_or_release',
                    response_time=0, response_length=0, exception=ValueError('finalization_not_confirmed'), context={})


@events.quitting.add_listener
def exit_on_failure(environment, **kwargs):
    if environment.stats.total.num_failures:
        environment.process_exit_code = 2
    from locust.runners import WorkerRunner
    if isinstance(environment.runner, WorkerRunner):
        return  # Master owns aggregate evidence; workers never overwrite it.
    try:
        folder = Path(os.environ.get('LOADTEST_REPORT_DIRECTORY',
                                     str(Path(os.environ['LOADTEST_CLIENT']).resolve().parent))).resolve()
        project = Path(__file__).resolve().parents[2]
        if not folder.is_dir() or folder.is_relative_to(project):
            raise ValueError('external_report_directory_required')
        total = environment.stats.total
        path = folder / ('locust_final_' + secrets.token_hex(8) + '_receipt.json')
        write_new(path, {'kind': 'REAL_BUSINESS_LOCUST_FINAL_RECEIPT', 'artifact_root': str(folder),
            'run_id': CFG['run_id'], 'manifest_sha256': sha(canonical(CFG)),
            'requests': total.num_requests, 'failures': total.num_failures,
            'includes_user_finalization': True, 'capacity_certified': False,
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
