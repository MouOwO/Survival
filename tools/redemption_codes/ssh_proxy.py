"""Optional transport through the existing local HTTP proxy; SSH verifies its host key."""
import os
import socket
import sys
import threading

if sys.argv[1:] != ['47.110.238.248', '22']:
    raise SystemExit(2)
connection = socket.create_connection(('127.0.0.1', 7890), timeout=15)
connection.sendall(b'CONNECT 47.110.238.248:22 HTTP/1.1\r\nHost: 47.110.238.248:22\r\n\r\n')
header = b''
while not header.endswith(b'\r\n\r\n') and len(header) < 8192:
    part = connection.recv(1)
    if not part:
        raise SystemExit(3)
    header += part
if b' 200 ' not in header.split(b'\r\n', 1)[0]:
    raise SystemExit(4)
connection.settimeout(None)

def forward():
    try:
        while True:
            raw = os.read(sys.stdin.fileno(), 65536)
            if not raw:
                break
            connection.sendall(raw)
        connection.shutdown(socket.SHUT_WR)
    except OSError:
        pass

threading.Thread(target=forward, daemon=True).start()
try:
    while True:
        raw = connection.recv(65536)
        if not raw:
            break
        sys.stdout.buffer.write(raw)
        sys.stdout.buffer.flush()
finally:
    connection.close()
