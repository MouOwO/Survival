"""Real PostgreSQL and Lua checks; caller supplies a disposable cloned database."""
from concurrent.futures import ThreadPoolExecutor
import copy
import hashlib
import json
from pathlib import Path
import sys
import uuid


def run(connect, release, registry):
    import psycopg
    from psycopg.types.json import Jsonb
    from psycopg.conninfo import make_conninfo
    sys.path.insert(0, str(release / "backend"))
    from fishing_api.postgres import PostgresRpcClient
    from archive_backend.service import ArchiveService
    from archive_backend.bundle import Bundle
    from archive_backend.redemption_codes import normalize
    import shutil
    pointer = json.loads((release / "addon/server/bundles/current.json").read_bytes())
    bundle = Bundle(release / "addon/server/bundles" / pointer["hash"])
    defaults = {r["field_id"]: r["default_value"] for r in bundle.configs["player_gameplay_stats"]["rows"]}
    with connect() as conn:
        database = conn.info.dbname
        assert database.startswith("goufayu_redeem_clone_"), "disposable_clone_required"
    dsn = make_conninfo(host="127.0.0.1", port=5432, dbname=database, user="goufayu_app",
                       password=Path("/etc/goufayu/app-password").read_text().strip())
    client = PostgresRpcClient(dsn)
    assert client.ready(), "actual_app_rpc_not_ready"
    accounts = {}

    class App:
        rpc_client = client
        def _database_account_id(self, public):
            return accounts[public]
        def _ensure_gameplay_stats(self, account):
            return self.rpc_client.rpc("ensure_player_gameplay_stats", {"p_account_id": account, "p_gameplay_stats": defaults})
        def _public_response(self, value, account, public):
            if isinstance(value, dict):
                return {k: public if k == "account_id" and v == account else self._public_response(v, account, public)
                        for k, v in value.items()}
            if isinstance(value, list):
                return [self._public_response(v, account, public) for v in value]
            return value

    service = ArchiveService(App(), bundle, shutil.which("lua5.1") or shutil.which("lua"))
    session = "redemption_clone_" + uuid.uuid4().hex
    checks = []

    def account():
        public = str(90000000000000000 + len(accounts))
        internal = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        accounts[public] = internal
        with connect() as conn:
            conn.execute("SELECT public.ensure_player_gameplay_stats(%s,%s)", (internal, Jsonb(defaults)))
            conn.execute("SELECT public.match_profile_login(%s,%s,'standard',%s)", (internal, session, Jsonb(defaults)))
        return public

    def define(rewards, *, maximum=0, expired=False):
        raw = "QA-" + uuid.uuid4().hex.upper()
        digest = hashlib.sha256(normalize(raw).encode()).hexdigest()
        identifier = "qa_" + uuid.uuid4().hex
        with connect() as conn:
            conn.execute("INSERT INTO public.redemption_codes(code_id,code_hash,label,rewards,max_redemptions,starts_at,expires_at) "
                "VALUES(%s,%s,'QA',%s,%s,clock_timestamp()-interval '2 days',"
                "CASE WHEN %s THEN clock_timestamp()-interval '1 day' ELSE NULL END)",
                (identifier, digest, Jsonb(rewards), maximum, expired))
        return raw, identifier

    def redeem(public, raw, token=None):
        token = token or "qa_request_" + uuid.uuid4().hex
        return service.command({"account_id": public, "match_session_id": session,
            "config_hash": bundle.hash, "command": {"kind": "redemption_redeem", "id": "redeem:" + token,
                "request_id": token, "code": raw}})

    def profile(public):
        return client.rpc("get_fishing_profile", {"p_account_id": accounts[public]})

    all_spec = registry["codes"][0]["rewards"]
    single = next(p for p in all_spec["products"] if p["sku"] == "video_p004")
    single_spec = {"products": [single], "markers": [], "wallet": {}, "entitlements": {}}
    public = account()
    raw, identifier = define(all_spec)
    old = profile(public)
    result = redeem(public, raw, "qa_all_request_01")
    assert result["ok"] and "command" not in result
    saved = profile(public)
    assert saved["save"]["content_inventory"]["commerce_p004"] == 1
    assert saved["save"]["archive"]["commerce"]["balances"]["u_coin"] == 100
    for key, value in old["save"]["gameplay_stats"].items():
        if "vip" in key:
            assert saved["save"]["gameplay_stats"][key] == value
    assert redeem(public, raw, "qa_all_request_01")["ok"]
    assert profile(public) == saved
    assert redeem(public, raw)["error"] == "redeem_already_used"
    checks.append("all_prizes_atomic_and_once_without_vip")

    public = account(); raw, identifier = define(single_spec)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: redeem(public, raw), range(2)))
    assert any(r["ok"] for r in results)
    assert profile(public)["save"]["gameplay_stats"]["initial_wood"] == defaults["initial_wood"] + 200
    checks.append("concurrent_same_account_single_grant")

    limited, identifier = define(single_spec, maximum=1)
    first, second = account(), account()
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda p: redeem(p, limited), (first, second)))
    assert sum(r["ok"] is True for r in results) == 1
    assert sum(r.get("error") == "redeem_code_exhausted" for r in results) == 1
    checks.append("concurrent_global_quota")

    public = account(); raw, identifier = define(single_spec, expired=True)
    assert redeem(public, raw)["error"] == "redeem_code_expired"
    for _ in range(9):
        assert redeem(public, "UNKNOWN-CODE-0000")["error"] == "redeem_code_invalid"
    assert redeem(public, "UNKNOWN-CODE-0000")["error"] == "redeem_rate_limited"
    checks.append("expiry_bad_codes_and_database_rate_limit")

    public = account(); raw, identifier = define(single_spec)
    class LostReply:
        def __init__(self): self.once = True
        def rpc(self, name, args):
            value = client.rpc(name, args)
            if name == "redemption_commit" and self.once:
                self.once = False
                raise TimeoutError("simulated_lost_reply")
            return value
    service.app.rpc_client = LostReply()
    try:
        redeem(public, raw, "qa_lost_reply_01")
    except TimeoutError:
        pass
    else:
        raise AssertionError("lost_reply_not_simulated")
    service.app.rpc_client = client
    saved = profile(public)
    assert redeem(public, raw, "qa_lost_reply_01")["ok"] and profile(public) == saved
    checks.append("lost_commit_reply_recovery")

    public = account()
    monthly = {"products": [], "markers": [], "wallet": {}, "entitlements": {"archive_pass": 30}}
    first, _ = define(monthly); second, _ = define(monthly); third, _ = define(monthly)
    assert redeem(public, first)["ok"]
    with connect() as conn:
        expires = conn.execute("SELECT expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='archive_pass'", (accounts[public],)).fetchone()[0]
    assert redeem(public, second)["ok"]
    with connect() as conn:
        after = conn.execute("SELECT expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='archive_pass'", (accounts[public],)).fetchone()[0]
        assert (after - expires).total_seconds() == 30 * 86400
        conn.execute("UPDATE public.archive_entitlements SET expires_at=NULL WHERE account_id=%s AND entitlement_id='archive_pass'", (accounts[public],))
    assert redeem(public, third)["ok"]
    with connect() as conn:
        assert conn.execute("SELECT expires_at FROM public.archive_entitlements WHERE account_id=%s AND entitlement_id='archive_pass'", (accounts[public],)).fetchone()[0] is None
    checks.append("monthly_renewal_and_permanent_pass_preservation")

    # Existing public routines and payment rows were never patched by this feature.
    return {"ok": True, "checks": checks, "actual_app_transport_ready": True,
            "real_lua_reducer": True, "clone_only": True, "real_player_redemption": False}
