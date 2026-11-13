"""Constant-space, bounded HTTP admission; no payload logging or retries.

Per accepted connection: O(1) metadata, at most one semaphore wait <=2s.
Only the listener acceptor waits; active socket metadata is bounded by slots.
Overload response/drain shares <=50ms and <=32KiB, with <=4KiB scratch.
Kernel backlog is a bounded socket count, not an end-to-end latency promise.
"""
from __future__ import annotations
import socket
import threading
import time

class BoundedAdmissionMixin:
    def _configure_admission(self, *, layer, max_concurrency, request_backlog,
                             admission_wait_seconds=0.0):
        if (layer not in ('frontend', 'backend')
                or type(max_concurrency) is not int or not 1 <= max_concurrency <= 128
                or type(request_backlog) is not int or not max_concurrency <= request_backlog <= 256
                or type(admission_wait_seconds) not in (int, float)
                or not 0 <= admission_wait_seconds <= 2):
            raise ValueError('http_admission_configuration_invalid')
        self.request_queue_size = request_backlog
        self._admission_layer = layer
        self._admission_max = max_concurrency
        self._admission_wait = float(admission_wait_seconds)
        self._admission_slots = threading.BoundedSemaphore(max_concurrency)
        self._admission_lock = threading.Lock()
        self._admission_requests = {}
        self._admission_closed = False
        self._admission_admitting_request = None
        self._admission_counters = dict(active=0, admitting=0, peak_active=0,
            accepted=0, rejected=0, cancelled=0, completed=0, dispatch_failed=0,
            responses_sent=0, response_send_failed=0, waited_accepts=0,
            peak_accept_wait_ms=0.0)

    def _sync_admission_counts_locked(self):
        # The socket index and completed counters are authoritative. Computing
        # len(dict) is O(1), and permits exact rollback of a pre-dispatch fault.
        counters = self._admission_counters
        counters['active'] = len(self._admission_requests)
        counters['admitting'] = int(self._admission_admitting_request is not None)
        counters['accepted'] = (counters['active'] + counters['completed']
                                + counters['dispatch_failed'])

    def admission_stats(self):
        with self._admission_lock:
            return dict(layer=self._admission_layer, max_concurrency=self._admission_max,
                backlog=self.request_queue_size, accept_wait_seconds=self._admission_wait,
                **self._admission_counters)

    def request_started_at(self, request):
        with self._admission_lock:
            entry = self._admission_requests.get(id(request))
            if entry is None or entry[0] is not request:
                raise RuntimeError('http_admission_lease_missing')
            return entry[1]

    def _finish_admission(self, request, *, dispatch_failed=False):
        with self._admission_lock:
            entry = self._admission_requests.pop(id(request), None)
            if entry is None:
                return
            field = 'dispatch_failed' if dispatch_failed else 'completed'
            self._admission_counters[field] += 1
            self._sync_admission_counts_locked()
        self._admission_slots.release()

    def _reject_admission(self, request, *, cancelled=False):
        with self._admission_lock:
            self._admission_counters['rejected'] += 1
            self._admission_counters['cancelled'] += int(cancelled)
        code = self._admission_layer.encode('ascii') + b'_busy'
        body = b'{"ok":false,"error":"' + code + b'"}'
        until = time.monotonic() + 0.05
        sent = False
        try:
            request.settimeout(max(0.000001, until - time.monotonic()))
            request.sendall(b'HTTP/1.0 503 Service Unavailable\r\n'
                b'Connection: close\r\nCache-Control: no-store\r\n'
                b'Content-Type: application/json\r\nContent-Length: '
                + str(len(body)).encode('ascii') + b'\r\n\r\n' + body)
            sent = True
            with self._admission_lock:
                self._admission_counters['responses_sent'] += 1
            # Send EOF before bounded discard of unread request bytes, avoiding
            # the usual immediate RST of a close with a POST body outstanding.
            request.shutdown(socket.SHUT_WR)
            remaining_bytes = 32768
            while remaining_bytes:
                remaining_time = until - time.monotonic()
                if remaining_time <= 0:
                    break
                request.settimeout(remaining_time)
                chunk = request.recv(min(4096, remaining_bytes))
                if not chunk:
                    break
                remaining_bytes -= len(chunk)
        except OSError:
            with self._admission_lock:
                # Only a failed send is a response failure. A read/discard
                # timeout after a complete send is expected, not a lost reply.
                if not sent:
                    self._admission_counters['response_send_failed'] += 1
        finally:
            self.shutdown_request(request)

    def process_request(self, request, client_address):
        started = time.monotonic()
        acquired = published = admitting_pending = False
        waited = False
        try:
            with self._admission_lock:
                self._admission_admitting_request = request
                admitting_pending = True
                self._sync_admission_counts_locked()
                closed = self._admission_closed
            if not closed:
                acquired = self._admission_slots.acquire(blocking=False)
                if not acquired and self._admission_wait:
                    waited = True
                    acquired = self._admission_slots.acquire(timeout=self._admission_wait)
            elapsed_ms = (time.monotonic() - started) * 1000
            with self._admission_lock:
                self._admission_admitting_request = None
                admitting_pending = False
                counters = self._admission_counters
                counters['waited_accepts'] += int(waited)
                counters['peak_accept_wait_ms'] = max(counters['peak_accept_wait_ms'], elapsed_ms)
                closed = self._admission_closed
                if acquired and not closed:
                    self._admission_requests[id(request)] = (request, started)
                    published = True
                self._sync_admission_counts_locked()
                counters['peak_active'] = max(counters['peak_active'], counters['active'])
        except BaseException:
            # No dispatch has occurred. Roll back even a fault immediately
            # after insertion/publication; never decrement admitting twice.
            with self._admission_lock:
                if admitting_pending or self._admission_admitting_request is request:
                    self._admission_admitting_request = None
                if published or id(request) in self._admission_requests:
                    self._admission_requests.pop(id(request), None)
                self._sync_admission_counts_locked()
            if acquired:
                self._admission_slots.release()
            self.shutdown_request(request)
            raise
        if not acquired or closed:
            if acquired:
                self._admission_slots.release()
            self._reject_admission(request, cancelled=closed)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            # Thread.start's ordinary synchronous failure created no worker.
            # BaseException is left leased conservatively: asynchronous signal
            # delivery cannot prove a worker did not already start.
            self._finish_admission(request, dispatch_failed=True)
            self._reject_admission(request)

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._finish_admission(request)

    def shutdown(self):
        with self._admission_lock:
            self._admission_closed = True
        return super().shutdown()

    def server_close(self):
        with self._admission_lock:
            self._admission_closed = True
        return super().server_close()
