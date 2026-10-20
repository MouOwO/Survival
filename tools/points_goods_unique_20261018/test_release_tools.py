"""Offline startup-poll regression; never executes the remote operator phases."""
from pathlib import Path
import ast
import io
import json
from types import SimpleNamespace
import unittest

ROOT=Path(__file__).resolve().parent
SOURCE=(ROOT/'remote_operator.py').read_text('utf-8-sig')
HEALTH=next(node for node in ast.parse(SOURCE).body if isinstance(node,ast.FunctionDef) and node.name=='health')


class Clock:
    def __init__(self):self.now=0;self.sleeps=[]
    def monotonic(self):return self.now
    def sleep(self,seconds):self.sleeps.append(seconds);self.now+=seconds


class Response(io.StringIO):
    status=200
    def __init__(self):super().__init__('{"ok":true}')


class StartupPollTests(unittest.TestCase):
    def run_health(self, failures):
        clock=Clock();calls=[]
        def urlopen(url,timeout):
            calls.append((url,timeout))
            self.assertGreater(timeout,0);self.assertLessEqual(timeout,1)
            self.assertIn(url,('http://127.0.0.1:8765/health','http://127.0.0.1:8766/health'))
            if failures(url,len(calls),clock.now):raise OSError('not_listening_yet')
            return Response()
        namespace={'time':clock,'json':json,'urllib':SimpleNamespace(request=SimpleNamespace(urlopen=urlopen))}
        code=ast.Module(body=[HEALTH],type_ignores=[])
        exec(compile(code,'remote_operator_health_only','exec'),namespace)
        return namespace['health'],clock,calls

    def test_ready_services_finish_immediately(self):
        run,clock,calls=self.run_health(lambda *_:False);run()
        self.assertEqual(len(calls),2);self.assertEqual(clock.now,0)

    def test_slow_archive_retries_without_changing_services(self):
        run,clock,calls=self.run_health(lambda url,_,now:url.endswith(':8765/health') and now<1.5);run()
        self.assertEqual(clock.now,1.5);self.assertEqual(clock.sleeps,[.5,.5,.5]);self.assertEqual(len(calls),8)

    def test_persistent_failure_stops_after_ten_seconds(self):
        run,clock,calls=self.run_health(lambda *_:True)
        with self.assertRaisesRegex(RuntimeError,'service_unhealthy_after_startup_poll'):run()
        self.assertEqual(clock.now,10);self.assertEqual(len(calls),40)


if __name__=='__main__':unittest.main()
