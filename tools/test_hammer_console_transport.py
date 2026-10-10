"""Offline end-to-end tests: Python -> real Node worker -> fake local TCP only."""
from contextlib import nullcontext
import json
from pathlib import Path
import socket
import struct
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

import hammer_backend_bridge as bridge
import hammer_console_transport as transport


class FakeConsole:
    def __init__(self):
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.port = self.listener.getsockname()[1]
        self.listener.listen()
        self.listener.settimeout(0.2)
        self.stopping = False
        self.connections = self.fin = self.polls = self.reloads = 0
        self.session = 'fake-map-session-one'
        self.drop = False
        self.peer = None
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    @staticmethod
    def print_frame(text):
        body = bytes(28) + text.encode() + b'\0'
        head = bytearray(12)
        head[:4] = b'PRNT'
        struct.pack_into('>I', head, 4, 0x00d40000)
        struct.pack_into('>I', head, 6, len(body) + 12)
        return head + body

    def run(self):
        while not self.stopping:
            try:
                peer, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            self.connections += 1
            self.peer = peer
            pending = b''
            try:
                while not self.stopping:
                    data = peer.recv(65536)
                    if not data:
                        self.fin += 1
                        break
                    pending += data
                    while len(pending) >= 12:
                        size = struct.unpack_from('>I', pending, 6)[0]
                        if len(pending) < size:
                            break
                        frame, pending = pending[:size], pending[size:]
                        if frame[:4] == b'VFCS':
                            peer.sendall(self.print_frame('VConsole Buffered Messages\n' +
                                'credential-from-older-console-history\n' * 1000 +
                                'End VConsole Buffered Messages\n'))
                        elif frame[:4] == b'CMND':
                            command = frame[12:-1].decode()
                            if command.startswith('echo SURVIVAL_CONSOLE_SESSION_READY_'):
                                peer.sendall(self.print_frame(command[5:] + '\n'))
                            elif command.startswith('script_reload_code '):
                                self.reloads += 1
                                peer.sendall(self.print_frame('SURVIVAL_TOOLS_HAMMER_BRIDGE_INSTALLED_V1\n'))
                            else:
                                assert command.startswith('survival_tools_hammer_bridge_inspect ')
                                nonce = command.split(' ', 1)[1]
                                self.polls += 1
                                if self.drop:
                                    self.drop = False
                                    peer.shutdown(socket.SHUT_WR)
                                    continue
                                state = {'status': 'configured', 'session': self.session,
                                         'players': 1, 'authenticated': 1, 'loaded': 1,
                                         'secret': 'never-forward-extra-fields'}
                                peer.sendall(self.print_frame(bridge.PREFIX + nonce + ':' + json.dumps(state) + '\n'))
            except OSError:
                pass
            finally:
                peer.close()
                self.peer = None

    def close(self):
        self.stopping = True
        if self.peer:
            try:
                self.peer.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.listener.close()
        self.thread.join(2)


class PersistentTransportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.server = FakeConsole()
        self.addCleanup(self.server.close)
        # This shim changes only the test's TCP endpoint, not production config.
        original = transport.ROOT
        script = self.root / 'tools/map_c6/hammer-console-worker.cjs'
        script.parent.mkdir(parents=True)
        script.write_text(
            'const {Inspector,serve}=require(' + json.dumps(str(original / 'tools/map_c6/hammer-console-worker.cjs')) + ');\n' +
            'const {ConsoleSession}=require(' + json.dumps(str(original / 'tools/map_c6/console-session.cjs')) + ');\n' +
            'serve(process.stdin,process.stdout,new Inspector({sessionFactory:()=>new ConsoleSession({' +
            f'port:{self.server.port},retainOutput:false,maxPendingOutputChars:32768,timeoutMs:300' + '})}));\n',
            encoding='utf-8')
        self.root_patch = patch.object(transport, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.inspector = transport.ResidentInspector()
        self.addCleanup(self.inspector.close)

    def test_foreground_keeps_one_connection_reconnects_new_map_and_fin_closes(self):
        first = self.inspector.inspect("print('offline fixture')")
        self.assertEqual(first['status'], 'configured')
        child = self.inspector.process
        for _ in range(30):
            result = self.inspector.inspect("print('offline fixture')")
            self.assertEqual(result, first)
        self.assertEqual(self.server.connections, 1)
        self.assertEqual(self.server.reloads, 1, '31 healthy inspections load Lua only once')
        self.assertNotIn('secret', json.dumps(result))
        self.assertNotIn(self.server.session, json.dumps(result))
        self.inspector.disconnect()
        self.assertEqual(self.server.fin, 1)
        self.server.session = 'fake-map-session-two'
        second = self.inspector.inspect("print('offline fixture')")
        self.assertNotEqual(first['session'], second['session'])
        self.assertEqual(self.server.connections, 2)
        self.assertIs(self.inspector.process, child, 'auth handoff does not restart Node')
        self.inspector.close()
        self.assertIsNone(self.inspector.process)
        self.assertEqual(child.returncode, 0)
        self.assertEqual(self.server.fin, 2)

    def test_owned_child_crash_recovers_and_resets_generation(self):
        self.inspector.inspect("print('offline fixture')")
        child = self.inspector.process
        child.terminate()
        child.wait(timeout=2)
        result = self.inspector.inspect("print('offline fixture')")
        self.assertEqual(result['status'], 'configured')
        self.assertEqual(self.inspector.stats['console_worker_generation'], 2)
        self.assertEqual(self.server.connections, 2)

    def test_closed_game_socket_returns_safe_wait_then_reconnects(self):
        self.inspector.inspect("print('offline fixture')")
        self.server.drop = True
        result = self.inspector.inspect("print('offline fixture')")
        self.assertEqual(result, {'status': 'waiting_for_workshop'})
        time.sleep(1.1)
        self.assertEqual(self.inspector.inspect("print('offline fixture')")['status'], 'configured')
        self.assertEqual(self.server.connections, 2)

    def test_background_bridge_stop_closes_child_before_lock_release(self):
        worker = bridge.Bridge(key=self.root / 'unused-key')
        worker.inspector = self.inspector
        ended, failures = [], []
        stop = self.root / 'bridge.stop'
        state = self.root / 'bridge_status.json'
        lock_exits = []
        inspector = self.inspector

        class Lock:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                lock_exits.append(inspector.process)

        def run():
            try:
                ended.append(bridge.run(worker))
            except Exception as exc:
                failures.append(type(exc).__name__)

        # No auth, credential, tunnel, real bridge state or Dota operation occurs.
        with patch.object(bridge, 'OUTPUT', self.root), patch.object(bridge, 'STATUS', state), \
                patch.object(bridge, 'STOP', stop), patch.object(bridge.auth, 'ignored'), \
                patch.object(bridge.tunnel, 'state_lock', side_effect=lambda file:
                    Lock() if file.name == 'bridge_instance.json' else nullcontext()), \
                patch.object(bridge.tunnel, 'connect', return_value={'ok': True}), \
                patch.object(bridge.auth, 'inject', return_value={'ok': True}) as inject:
            thread = threading.Thread(target=run)
            thread.start()
            deadline = time.monotonic() + 6
            while self.server.polls < 2 and thread.is_alive() and time.monotonic() < deadline:
                time.sleep(0.05)
            stop.write_text('stop\n')
            thread.join(5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(failures, [])
            self.assertEqual(ended[0]['status'], 'stopped')
            self.assertIsNone(self.inspector.process)
            self.assertGreaterEqual(self.server.fin, 2)
            self.assertEqual(lock_exits, [None], 'worker must exit before stop can acquire the instance lock')
            inject.assert_called_once()

    def test_stalled_child_pipe_write_and_response_share_a_bounded_deadline(self):
        script = self.root / 'tools/map_c6/hammer-console-worker.cjs'
        script.write_text('setInterval(()=>{},1000);\n', encoding='utf-8')
        started = time.monotonic()
        with self.assertRaisesRegex(transport.TransportError, '^inspection_worker_unavailable$'):
            self.inspector._rpc('inspect', code='x' * 50000, timeout=0.15)
        self.assertLess(time.monotonic() - started, 3)
        self.assertIsNone(self.inspector.process)
        self.assertEqual(self.server.connections, 0)

    def test_invalid_child_json_never_leaks_output_and_is_disposed(self):
        self.inspector._start()
        self.inspector.responses.put_nowait({'id': 'SECRET HISTORY', 'ok': True})
        with self.assertRaisesRegex(transport.TransportError, '^inspection_worker_unavailable$'):
            self.inspector.inspect("print('offline fixture')")
        self.assertIsNone(self.inspector.process)


if __name__ == '__main__':
    unittest.main()
