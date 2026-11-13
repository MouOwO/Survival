"""Frozen transport-only four-arm experiment; no SQL is executed by this file."""
from __future__ import annotations
import ast
import hashlib

PARENT_SHA256 = "15efa09cc9297ff065d56067570ba001ae3c4700db62df6e4cd159e5f1e0a966"
ARMS = ("baseline", "reset-v1", "guard-v1", "principal-v1")
GUC_NAMES = ("statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout", "search_path", "application_name")
def sha(source):
    return hashlib.sha256(source.encode("utf-8")).hexdigest()
def _replace(source, old, new):
    if source.count(old) != 1:raise ValueError("principal_source_anchor_invalid")
    return source.replace(old, new, 1)
def _method(source, name):
    node=next(n for n in ast.walk(ast.parse(source)) if isinstance(n,ast.ClassDef) and n.name=="PostgresRpcClient")
    method=next(n for n in node.body if isinstance(n,ast.FunctionDef) and n.name==name)
    return ast.get_source_segment(source,method)
def _constants(source):
    return {n.targets[0].id:ast.literal_eval(n.value) for n in ast.parse(source).body
            if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name)
            and n.targets[0].id in ("_RUNTIME_CHECK","_FUNCTION_CHECK")}
BASELINE_CHECK = r"""
    def _verify_reset_baseline(self, connection: Any, cursor: Any) -> None:
        # Configuration provenance only. Authorization is still checked every RPC.
        with self._reset_baseline_lock:
            if self._reset_baseline.get(id(connection)) is connection:return
            if self._reset_baseline_closed:raise DatabaseError("database_unavailable")
        self._ensure_deadline()
        cursor.execute(_RESET_BASELINE_CHECK, (list(_RESET_GUC_NAMES),))
        rows = cursor.fetchall()
        expected = dict(zip(_RESET_GUC_NAMES, self._reset_options))
        units = dict(zip(_RESET_GUC_NAMES, ("ms", "ms", "ms", None, None)))
        if (len(rows) != len(expected) or any(len(row) != 8 for row in rows)
                or {row[0] for row in rows} != set(expected)
                or any(row[0] not in expected or row[1] != expected[row[0]]
                       or row[2] != expected[row[0]] or row[3] != "client"
                       or row[4] != units[row[0]] or row[5] != RUNTIME_ROLE
                       or row[6] != RUNTIME_ROLE or not isinstance(row[7], str)
                       or row[7].lower() == "postgres" or row[7].lower().startswith("template") for row in rows)):
            raise DatabaseError("database_configuration_baseline_invalid")
        self._ensure_deadline()
        with self._reset_baseline_lock:
            if self._reset_baseline_closed:raise DatabaseError("database_unavailable")
            self._reset_baseline[id(connection)] = connection
"""
MERGED_CHECK = r"""
    def _check_runtime(self, cursor: Any) -> None:
        # Both catalog checks share one statement; no result survives this RPC.
        # Existing role stage covers the complete combined guard, not role-only.
        with measure("db_role_guard"):
            cursor.execute(_PRINCIPAL_CHECK, (list(ALLOWED_FUNCTIONS),))
            row = cursor.fetchone()
        if (not row or len(row) != 11 or row[0] != RUNTIME_ROLE or row[1] != RUNTIME_ROLE
                or not isinstance(row[2], str) or row[2].lower() == "postgres"
                or row[2].lower().startswith("template") or any(row[3:10])):
            raise DatabaseError("database_runtime_role_invalid")
        self._ensure_deadline()
        functions = row[10]
        if (not isinstance(functions, list) or len(functions) != len(ALLOWED_FUNCTIONS)
                or any(not isinstance(item, list) or len(item) != 2 for item in functions)
                or {item[0] for item in functions} != set(ALLOWED_FUNCTIONS)
                or any(item[1] is not True for item in functions)):
            raise DatabaseError("database_rpc_permissions_invalid")
"""
def merged_sql(source):
    constants=_constants(source)
    runtime=constants["_RUNTIME_CHECK"].strip()
    runtime=_replace(runtime,"ARRAY(SELECT to_regprocedure(s)::oid\n                                              FROM unnest(%s::text[]) s)","ARRAY(SELECT oid FROM principal_allowed)")
    runtime=_replace(runtime,"FROM pg_roles r WHERE r.rolname = current_user","FROM principal_actor r WHERE r.rolname = current_user")
    function=constants["_FUNCTION_CHECK"].strip()
    function=_replace(function,"SELECT s,","SELECT a.s,")
    function=_replace(function,"(SELECT oid FROM pg_roles WHERE rolname = current_user)","(SELECT oid FROM principal_actor)")
    function=_replace(function,"FROM unnest(%s::text[]) s LEFT JOIN pg_proc p ON p.oid = to_regprocedure(s)","FROM principal_allowed a LEFT JOIN pg_proc p ON p.oid = a.oid")
    return ("WITH principal_allowed(s, oid) AS MATERIALIZED (\n SELECT s, to_regprocedure(s)::oid FROM unnest(%s::text[]) s\n),\n"
            "principal_actor AS MATERIALIZED (\n SELECT oid,rolname,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls\n"
            " FROM pg_roles WHERE rolname = current_user\n),\nruntime_guard AS MATERIALIZED (\n"+runtime+"\n),\n"
            "function_guard(s, allowed) AS MATERIALIZED (\n"+function+"\n)\n"
            "SELECT runtime_guard.*, (SELECT jsonb_agg(jsonb_build_array(s, allowed) ORDER BY s)\n FROM function_guard) FROM runtime_guard")
def patch_postgres(source: str, arm: str = "principal-v1") -> str:
    if arm not in ARMS or sha(source) != PARENT_SHA256:raise ValueError("principal_parent_source_invalid")
    if arm == "baseline":return source
    result=source
    if arm in ("guard-v1","principal-v1"):
        result=_replace(result,"\ndef _json_dumps","\n_PRINCIPAL_CHECK = "+repr(merged_sql(source))+"\n\ndef _json_dumps")
        result=_replace(result,_method(source,"_check_runtime"),MERGED_CHECK.strip())
    if arm in ("reset-v1","principal-v1"):
        baseline_sql="SELECT name, setting, reset_val, source, unit, current_user::text, session_user::text, current_database()::text FROM pg_catalog.pg_settings WHERE name = ANY(%s::text[]) ORDER BY name"
        result=_replace(result,"\ndef _json_dumps","\n_RESET_GUC_NAMES = "+repr(GUC_NAMES)+"\n_RESET_BASELINE_CHECK = "+repr(baseline_sql)+"\n\ndef _json_dumps")
        result=_replace(result,"        self._pool = BoundedConnectionPool(","        self._reset_baseline = {}\n        self._reset_baseline_lock = threading.RLock()\n        self._reset_baseline_closed = False\n        self._pool = BoundedConnectionPool(")
        result=_replace(result,"    def _reset_connection(self, connection: Any) -> None:","    "+BASELINE_CHECK.strip()+"\n\n    def _reset_connection(self, connection: Any) -> None:")
        old="        connection.autocommit = True\n        try:\n            with connection.cursor() as cursor:"
        new="        with self._reset_baseline_lock:\n            if self._reset_baseline.get(id(connection)) is not connection:\n                raise DatabaseError(\"database_configuration_baseline_invalid\")\n        connection.autocommit = True\n        try:\n            with connection.cursor() as cursor:"
        result=_replace(result,old,new)
        old="                cursor.execute(\n                    \"SELECT pg_catalog.set_config('statement_timeout', %s, false), \"\n                    \"pg_catalog.set_config('lock_timeout', %s, false), \"\n                    \"pg_catalog.set_config('idle_in_transaction_session_timeout', %s, false), \"\n                    \"pg_catalog.set_config('search_path', %s, false), \"\n                    \"pg_catalog.set_config('application_name', %s, false)\",\n                    self._reset_options)"
        result=_replace(result,old,"                # Client-pinned reset_val provenance was verified on this physical lease.")
        result=_replace(result,"    def close(self) -> None:\n        self._pool.close()","    def close(self) -> None:\n        with self._reset_baseline_lock:\n            self._reset_baseline_closed = True\n            self._reset_baseline.clear()\n        self._pool.close()")
        result=_replace(result,"            with connection.cursor() as cursor:\n                with measure(\"db_guard\"):","            with connection.cursor() as cursor:\n                self._verify_reset_baseline(connection, cursor)\n                with measure(\"db_guard\"):")
        result=_replace(result,"                    self._pool.release(connection, reusable=reusable)","                    if not reusable:\n                        with self._reset_baseline_lock:\n                            self._reset_baseline.pop(id(connection), None)\n                    self._pool.release(connection, reusable=reusable)")
    compile(result,"<principal-"+arm+">","exec")
    _validate_delta(source,result,arm)
    return result

def _validate_delta(parent,result,arm):
    old=ast.parse(parent);new=ast.parse(result)
    allowed_methods={"_check_runtime"} if arm=="guard-v1" else {"__init__","_reset_connection","close","_transaction","_verify_reset_baseline"}
    if arm=="principal-v1":allowed_methods.add("_check_runtime")
    added={"_PRINCIPAL_CHECK"} if arm=="guard-v1" else {"_RESET_GUC_NAMES","_RESET_BASELINE_CHECK"}
    if arm=="principal-v1":added.add("_PRINCIPAL_CHECK")
    def scrub(tree):
        for c in tree.body:
            if isinstance(c,ast.ClassDef) and c.name=="PostgresRpcClient":
                c.body=[m for m in c.body if not(isinstance(m,ast.FunctionDef) and m.name in allowed_methods)]
        tree.body=[n for n in tree.body if not(isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id in added)]
        return ast.dump(tree,include_attributes=False)
    if scrub(old)!=scrub(new):raise ValueError("principal_ast_delta_invalid")
