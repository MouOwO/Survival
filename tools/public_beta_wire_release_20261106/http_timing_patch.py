"""Exact audited WS4 source transformation; no remote operation or deployment."""
import hashlib

SERVER_SHA = '8330125801f19589e3ae37fe4e4876c4cbcc65c0739e51fdf6731cc7f17c17e2'
POSTGRES_SHA = '418dda0886ff06903c24f7785a81228dbdaf1f5b2001df4e51ae7b9adc85df76'


def _source(raw, expected):
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError('http_timing_audited_source_changed')
    return raw.decode('utf-8')


def _replace(text, before, after):
    if text.count(before) != 1:
        raise ValueError('http_timing_unique_anchor_required')
    return text.replace(before, after, 1)


def server(raw):
    text = _source(raw, SERVER_SHA)
    text = _replace(text, 'from .application import ApiError, FishingApplication\n',
                    'from .application import ApiError, FishingApplication\n'
                    'from archive_backend.http_request_timing import request_span, measure, identify, sent\n')
    text = _replace(text,
        '        def do_POST(self) -> None:\n            if not self._authorized():\n                return\n',
        '        @request_span\n        def do_POST(self) -> None:\n'
        '            with measure("authorize"):\n                if not self._authorized():\n                    return\n')
    text = _replace(text, '                payload = self._body()\n',
                    '                with measure("body"):\n                    payload = self._body()\n'
                    '                identify(payload)\n')
    text = _replace(text,
        '                match_context = (match_profiles.context(application, payload)\n'
        '                                 if self.path not in ("/v1/session/login", "/v1/session/authenticate") else None)\n',
        '                with measure("context"):\n'
        '                    match_context = (match_profiles.context(application, payload)\n'
        '                                     if self.path not in ("/v1/session/login", "/v1/session/authenticate") else None)\n')
    text = _replace(text, '                        response = archive.command(payload)\n',
                    '                        with measure("command"):\n                            response = archive.command(payload)\n')
    text = _replace(text, '                response = match_profiles.project(application, payload, response, match_context)\n',
                    '                with measure("project"):\n                    response = match_profiles.project(application, payload, response, match_context)\n')
    text = _replace(text,
        '            body = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()\n',
        '            with measure("serialize"):\n                body = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()\n'
        '            sent(status, len(body))\n')
    text = _replace(text, '                self.wfile.write(body)\n',
                    '                with measure("write"):\n                    self.wfile.write(body)\n')
    compile(text, '<http-timing-server>', 'exec')
    return text.encode('utf-8')


def postgres(raw):
    text = _source(raw, POSTGRES_SHA)
    text = _replace(text, 'from .supabase import SupabaseError\n',
                    'from .supabase import SupabaseError\nfrom archive_backend.http_request_timing import measure, rpc_span\n')
    text = _replace(text, '        cursor.execute(_RUNTIME_CHECK, (list(ALLOWED_FUNCTIONS),))\n        row = cursor.fetchone()\n',
                    '        with measure("db_role_guard"):\n            cursor.execute(_RUNTIME_CHECK, (list(ALLOWED_FUNCTIONS),))\n            row = cursor.fetchone()\n')
    text = _replace(text, '        cursor.execute(_FUNCTION_CHECK, (list(ALLOWED_FUNCTIONS),))\n        functions = cursor.fetchall()\n',
                    '        with measure("db_function_guard"):\n            cursor.execute(_FUNCTION_CHECK, (list(ALLOWED_FUNCTIONS),))\n            functions = cursor.fetchall()\n')
    text = _replace(text, '            connection = self._connect(self._dsn, **self._connect_options)\n',
                    '            with measure("db_connect"):\n                connection = self._connect(self._dsn, **self._connect_options)\n')
    text = _replace(text, '                self._check_runtime(cursor)\n                cursor.execute(query, parameters)\n                row = cursor.fetchone()\n',
                    '                with measure("db_guard"):\n                    self._check_runtime(cursor)\n'
                    '                with measure("db_query"):\n                    cursor.execute(query, parameters)\n                    row = cursor.fetchone()\n')
    text = _replace(text, '            connection.commit()\n',
                    '            with measure("db_commit"):\n                connection.commit()\n')
    text = _replace(text, '                    connection.rollback()\n',
                    '                    with measure("db_rollback"):\n                        connection.rollback()\n')
    text = _replace(text, '                    connection.close()\n',
                    '                    with measure("db_close"):\n                        connection.close()\n')
    text = _replace(text, '        return self._transaction(query, values)\n',
                    '        with rpc_span(function_name):\n            return self._transaction(query, values)\n')
    compile(text, '<http-timing-postgres>', 'exec')
    return text.encode('utf-8')
