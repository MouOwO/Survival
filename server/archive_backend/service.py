from __future__ import annotations
import hashlib
import hmac
import json
import math
import re
import subprocess
import threading
import time
from pathlib import Path
from .bundle import Bundle
from .config_compatibility import accepts, upgrades

class ArchiveError(ValueError):
    pass

FIELDS = {
    "commerce_catalog": set(),
    "commerce_purchase": {"sku", "request_id"},
    "clear": {"difficulty_id","count","day_key","cooperative_win"}, "boss_kill": set(),
    "standard_clear": {"difficulty_id","count","day_key","cooperative_win"},
    "rich_clear": {"difficulty_id","count","day_key","cooperative_win"},
    "cold_clear": {"difficulty_id","count","day_key","cooperative_win"},
    "scourge_clear": {"difficulty_id","count","day_key","cooperative_win"},
    "mode_clear": {"difficulty_id","count","day_key","cooperative_win"},
    "endless": {"wave","difficulty"}, "endless_reconcile": set(), "starjoy_reconcile": set(), "welfare_reconcile": set(),
    "challenge": {"challenge_id","kill_sequence","difficulty_id","day_key"},
    "social_draw": {"pool_id"}, "promotion": {"fragment_id","day_key"},
    "daily_init": {"today"}, "daily_claim": {"today","target_day"},
    "benefit_claim": {"track", "tier_id"},
    "vip_claim": {"reward_id"}, "vip_purchase": {"reward_id"},
    "title_equip": {"title_id"},
    "work_upgrade": {"item_id","expected_level"},
    "building_upgrade": {"item_id","expected_level"},
    # No simulated currency/faith grants in the HTTP integration.
    "lottery_draw": {"pool_id","count","request_id"},
    "lottery_exchange": {"pool_id","item_id","request_id"},
    "lottery_read": {"pool_id","revision","read_action","request_id"},
}

def object_maps(value):
    # Lua's empty table encoder produces []; saved archive empty fields are all maps.
    if value == []: return {}
    if isinstance(value,dict): return {k:object_maps(v) for k,v in value.items()}
    if isinstance(value,list): return [object_maps(v) for v in value]
    return value

class ArchiveService:
    slots=threading.BoundedSemaphore(4)
    def __init__(self, application, bundle: Bundle, lua: str):
        self.app,self.bundle,self.lua=application,bundle,lua
        self._lottery_catalog = None
        self._lottery_catalog_lock = threading.Lock()

    def lottery_catalog(self, payload):
        # Static public content has no account/profile dependency. Authentication
        # remains the HTTP handler's normal Bearer-token boundary.
        from .lottery_catalog import build_catalog
        with self._lottery_catalog_lock:
            if self._lottery_catalog is None:
                self._lottery_catalog = build_catalog(self)
            document = self._lottery_catalog
        unchanged = payload.get("md5") == document["catalog_md5"]
        response = {"ok": True, "unchanged": unchanged,
                    "catalog_md5": document["catalog_md5"], "config_hash": document["config_hash"]}
        if not unchanged:
            response["catalog_json"] = document["catalog_json"]
        return response

    def sync(self):
        config = {"configs": self.bundle.configs}
        compatibility = getattr(self.bundle, "compatible_config_hashes", {})
        if compatibility:
            config["compatible_config_hashes"] = {digest: {
                "commands": sorted(rule["commands"]),
                "upgrade_commands": sorted(rule["upgrade_commands"]),
            } for digest, rule in compatibility.items()}
        return self.app.rpc_client.rpc("archive_sync_config",{
            "p_hash":self.bundle.hash,"p_config":config})

    def validate(self, command):
        if not isinstance(command,dict): raise ArchiveError("archive_command_invalid")
        kind=command.get("kind")
        if not isinstance(kind, str) or kind not in FIELDS or set(command)-FIELDS[kind]-{"id","kind"}: raise ArchiveError("archive_command_fields_invalid")
        if not isinstance(command.get("id"),str) or not re.fullmatch(r"[A-Za-z0-9_:.-]{8,200}",command["id"]): raise ArchiveError("archive_id_invalid")
        c=dict(command)
        if kind == 'commerce_purchase':
            if c.get('sku') not in self.bundle.tables['commerce_catalog']:
                raise ArchiveError('product_unavailable')
            if not isinstance(c.get('request_id'), str) or not re.fullmatch(r'[A-Za-z0-9_.-]{8,96}', c['request_id']):
                raise ArchiveError('commerce_request_id_invalid')
            # Same account + purchase token is the same transaction across reconnects.
            c['id'] = 'commerce:' + c['request_id']
        def integer(key,lo,hi):
            v=c.get(key)
            if isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or int(v)!=v or not lo<=v<=hi: raise ArchiveError("archive_number_invalid:"+key)
            c[key]=int(v)
        if kind in {"clear", "standard_clear", "rich_clear", "cold_clear", "scourge_clear", "mode_clear"}:
            # Lua validates each authenticated mode against its configured
            # range. The protocol must not truncate supported N21-N50 wins.
            if type(c.get("count")) is not int or c["count"]!=1 or not re.fullmatch(r"n(?:[1-9]|[1-4][0-9]|50)",str(c.get("difficulty_id"))): raise ArchiveError("archive_clear_invalid")
            if "cooperative_win" in c: integer("cooperative_win",0,1)
        if kind=="endless":
            integer("wave",1,1000);integer("difficulty",1,20)
        if kind=="challenge":
            definition=self.bundle.tables["archive_challenge_definitions"].get(c.get("challenge_id"))
            if not definition or not definition.get("enabled"): raise ArchiveError("archive_challenge_invalid")
            raw=c.get("difficulty_id")
            if isinstance(raw,str): raw=raw.lower().removeprefix("n")
            if not re.fullmatch(r"(?:[1-9]|[1-4][0-9]|50)",str(raw)): raise ArchiveError("archive_difficulty_invalid")
            try: difficulty=int(raw)
            except (ValueError,TypeError): raise ArchiveError("archive_difficulty_invalid")
            # Challenge definitions also drive the game's unlock buttons.
            if not definition["min_difficulty"]<=difficulty<=50: raise ArchiveError("archive_challenge_locked")
            c["difficulty_id"]="n"+str(difficulty);integer("kill_sequence",1,100000)
        if kind in {"vip_claim", "vip_purchase"}:
            item=self.bundle.tables["archive_vip_rewards"].get(c.get("reward_id"))
            group="privileges" if kind=="vip_claim" else "packages"
            if not item or not item.get("enabled") or item["group_id"]!=group: raise ArchiveError("vip_reward_invalid")
        if kind=="title_equip":
            title_id=c.get("title_id")
            item=self.bundle.tables.get("archive_titles",{}).get(title_id) if isinstance(title_id,str) else None
            if not isinstance(title_id,str) or (title_id!="" and (not item or not item.get("enabled"))):
                raise ArchiveError("archive_title_invalid")
        if kind=="daily_claim": integer("target_day",0,1000000)
        if kind=="benefit_claim":
            tier_id=c.get("tier_id")
            tier = (self.bundle.tables.get("archive_benefit_rewards", {}).get(tier_id)
                    if isinstance(tier_id,str) and isinstance(c.get("track"),str) else None)
            if not tier or tier.get("enabled") is not True or tier.get("track") != c.get("track"):
                raise ArchiveError("archive_benefit_invalid")
        if kind.startswith("lottery_"):
            if c.get("pool_id") not in self.bundle.tables["lottery_pool_definitions"]: raise ArchiveError("lottery_pool_invalid")
            if not isinstance(c.get("request_id"),str) or not re.fullmatch(r"[A-Za-z0-9_:.-]{1,96}",c["request_id"]): raise ArchiveError("lottery_request_id_invalid")
            if kind=="lottery_draw" and (type(c.get("count")) is not int or c["count"] not in (1,10)): raise ArchiveError("lottery_count_invalid")
            if kind=="lottery_exchange" and c.get("item_id") not in self.bundle.tables["lottery_item_definitions"]: raise ArchiveError("lottery_item_invalid")
            if kind=="lottery_read" and (c.get("read_action") not in ("visit","details","notice") or not isinstance(c.get("revision"),str)): raise ArchiveError("lottery_read_invalid")
        if kind=="faith_cheat": integer("amount",1,1000000000)
        if kind=="social_draw" and c.get("pool_id") not in self.bundle.tables["archive_social_rules"]: raise ArchiveError("archive_pool_invalid")
        if kind=="promotion" and c.get("fragment_id") not in self.bundle.tables["archive_fragment_definitions"]: raise ArchiveError("archive_fragment_invalid")
        if kind=="building_upgrade":
            item=self.bundle.tables["archive_building_items"].get(c.get("item_id"))
            if not item or not item.get("enabled"): raise ArchiveError("archive_building_invalid")
            integer("expected_level",0,item["max_level"]-1)
        if kind=="work_upgrade":
            item=self.bundle.tables["archive_work_items"].get(c.get("item_id"))
            if not item: raise ArchiveError("archive_work_invalid")
            integer("expected_level",0,item["max_level"]-1)
        # A retry across midnight keeps the first database-recorded date, never client date.
        c.pop("today",None);c.pop("day_key",None)
        match=c["id"].split(":",1)[0]
        if kind=="clear": c["id"]=match+":clear"
        if kind=="endless": c["id"]=match+":endless:"+str(c["wave"])
        if kind in {"endless_reconcile", "starjoy_reconcile", "welfare_reconcile"}: c["id"]=match+":"+kind
        if kind=="challenge": c["id"]=match+":challenge_kind:"+c["challenge_id"]
        return c

    @staticmethod
    def shared_challenge_roll(bundle):
        rule = bundle.tables.get("archive_cooperative_reward_rules", {}).get("default", {})
        return (rule.get("version") == 1 and rule.get("enabled") is True
                and rule.get("shared_challenge_roll") is True)

    def settle(self,profile,command,has_pass,shared_challenge_roll=None):
        shared = (self.shared_challenge_roll(self.bundle)
                  if shared_challenge_roll is None else shared_challenge_roll)
        if command["kind"] == "challenge" and shared:
            # Every recipient uses the same base roll. Their own prepared
            # entitlement still decides how many entries they may receive.
            scope = command["id"].split(":", 1)[0] + ":challenge_kind:" + command["challenge_id"]
        else:
            scope = profile["account_id"] + ":" + command["id"]
        seed=int.from_bytes(hmac.new(self.app.account_id_pepper.encode(),
            scope.encode(),hashlib.sha256).digest()[:4],"big")%2147483646+1
        payload={"configs":self.bundle.configs,"profile":profile,"command":command,"has_pass":has_pass,"seed":seed,"server_time":int(time.time())}
        if not self.slots.acquire(timeout=2): raise TimeoutError("archive_workers_busy")
        try:
            completed=subprocess.run([self.lua,"worker.lua"],cwd=self.bundle.directory,
                input=json.dumps(payload,ensure_ascii=False,allow_nan=False).encode(),stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,timeout=10,check=True,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
        finally: self.slots.release()
        result=object_maps(json.loads(completed.stdout))
        if not isinstance(result,dict): raise ArchiveError("archive_worker_invalid")
        return result

    def command(self,payload):
        account=payload.get("account_id")
        if not isinstance(account,str) or not re.fullmatch(r"[0-9]{1,20}",account): raise ArchiveError("account_id_invalid")
        requested_hash = payload.get("config_hash")
        raw_command = payload.get("command")
        kind = raw_command.get("kind") if isinstance(raw_command, dict) else None
        # Account tutorial metadata has its own protocol and SQL persistence.
        # It neither settles rewards nor depends on a reward configuration hash.
        from .onboarding import KINDS as onboarding_kinds, command as onboarding_command
        if isinstance(kind, str) and kind in onboarding_kinds:
            try:
                return onboarding_command(self.app, payload)
            except ValueError as error:
                raise ArchiveError(str(error)) from error
        if not accepts(self.bundle, requested_hash, kind): return {"ok":False,"terminal":True,"error":"archive_config_mismatch","config_hash":self.bundle.hash}
        command=self.validate(payload.get("command"))
        from .match_modes import scope_clear
        command=scope_clear(self,payload,command)
        if command['kind'] == 'commerce_catalog':
            profile = self.profile({'account_id': account})
            return self.settle(profile, command, False)
        database_id=self.app._database_account_id(account)
        self.app._ensure_gameplay_stats(database_id)
        from .clear_receipts import lookup
        receipt = lookup(self, payload, command)
        if receipt is not None:
            result = self.finish_prepared(database_id, receipt.operation_id, receipt.prepared,
                                          clear_mode=receipt.mode_id)
            return self.app._public_response(result, database_id, account)
        if command['kind'] == 'starjoy_reconcile':
            # Cash grants can cross several tiers during one match. Derive a
            # stable receipt from saved progress, never a client-supplied score.
            # profile() also resolves earlier pending operations before reading.
            trusted = self.profile({'account_id': account})
            stats = trusted.get('save', {}).get('gameplay_stats', {})
            score = max(0, *(int(stats.get(key) or 0) for key in
                            ('starjoy_points_earned', 'starjoy_points')))
            command['id'] += ':earned:' + str(score)
        fingerprint=hashlib.sha256(json.dumps(command,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
        prepared=self.app.rpc_client.rpc("archive_prepare",{"p_account":database_id,"p_id":command["id"],
            "p_hash":requested_hash,"p_fingerprint":fingerprint,"p_command":command})
        result=self.finish_prepared(database_id,command["id"],prepared)
        return self.app._public_response(result,database_id,account)

    def endless_batch(self, payload):
        """Bounded transport batch; durable per-wave receipts remain unchanged."""
        if not accepts(self.bundle, payload.get("config_hash"), "endless"):
            # A game ahead of deployment keeps its earned score queued; an
            # incompatible server is not an acknowledgement for any wave.
            return {"ok": False, "error": "archive_config_mismatch", "results": [], "config_hash": self.bundle.hash}
        commands = payload.get("commands")
        if not isinstance(commands, list) or not 1 <= len(commands) <= 32:
            raise ArchiveError("archive_batch_size_invalid")
        # Validate the whole envelope before the first mutation. Only trusted
        # existing endless intents are accepted, never client scores/deltas.
        validated = [self.validate(command) for command in commands]
        if any(command["kind"] != "endless" for command in validated):
            raise ArchiveError("archive_batch_kind_invalid")
        if len({command["id"] for command in validated}) != len(validated):
            raise ArchiveError("archive_batch_duplicate_id")
        if len({command["id"].split(":", 1)[0] for command in validated}) != 1:
            raise ArchiveError("archive_batch_session_invalid")
        results, profile = [], None
        for original, command in zip(commands, validated):
            request = dict(payload)
            request.pop("commands", None)
            request["command"] = command
            result = self.command(request)
            if result.get("profile"):
                profile = result["profile"]
            results.append({"id": original["id"], "ok": result.get("ok") is True,
                "terminal": result.get("terminal") is True, "error": result.get("error")})
            if not result.get("ok") and not result.get("terminal"):
                return {"ok": False, "error": result.get("error"), "results": results, "profile": profile}
        return {"ok": True, "results": results, "profile": profile}

    def finish_prepared(self,account,operation_id,prepared,clear_mode=None):
        for _ in range(4):
            if not prepared.get("ok") or prepared.get("done"): return prepared
            profile,command=prepared["profile"],dict(prepared["command"])
            # This timestamp belongs to the durable database receipt, not the
            # HTTP caller or the worker's retry time. It keeps late checkpoints
            # and claims in the period where their operation was first accepted.
            event_at=prepared.get("event_at")
            if isinstance(event_at,(int,float)) and not isinstance(event_at,bool) and math.isfinite(event_at):
                command["event_at"]=int(event_at)
            if (clear_mode is None and getattr(self.app, "_archive_modes_active", False)
                    and (command["kind"] in {"clear", "mode_clear"} or command["kind"].endswith("_clear"))):
                from .clear_receipts import resolve_pending_mode
                clear_mode = resolve_pending_mode(self, account, command)
            if clear_mode is not None:
                from .clear_receipts import bound_command
                command = bound_command(command, clear_mode)
            reducer=self
            version=prepared.get("config_hash",self.bundle.hash)
            from .unique_points import legacy_lottery_error
            # Starjoy is cumulative progression. Reject new and unfinished old
            # exchanges through the existing terminal receipt commit; completed
            # receipts already returned above remain immutable.
            legacy_error=('starjoy_exchange_disabled' if command.get('kind')=='lottery_exchange'
                          else legacy_lottery_error(self.bundle.hash,version,command.get('kind')))
            shared_roll = self.shared_challenge_roll(self.bundle)
            # Preserve the recorded hash and fingerprint for old-match replays.
            # Only explicitly approved archive updates use the current reducer.
            # Old lottery mutations require a refreshed unique-ownership
            # catalog; completed receipts were returned above unchanged.
            if version!=self.bundle.hash and not legacy_error:
                if not re.fullmatch(r"[0-9a-f]{64}",version): raise ArchiveError("archive_config_invalid")
                upgraded = upgrades(self.bundle, version, command.get("kind"))
                # Outstanding reward intents must observe account quotas too.
                # Completed receipts returned above remain immutable, and a
                # challenge keeps its originally recorded shared-roll policy.
                if "archive_daily_limits" in self.bundle.tables and command["kind"] in {
                    "clear", "standard_clear", "rich_clear", "cold_clear", "scourge_clear",
                    "mode_clear", "boss_kill", "endless", "challenge", "online_checkpoint",
                }:
                    upgraded = True
                if command["kind"] == "challenge" or not upgraded:
                    recorded_bundle = Bundle(self.bundle.directory.parent/version)
                # Even an explicitly upgraded reducer must retain the seed
                # policy recorded when this operation was first accepted.
                if command["kind"] == "challenge":
                    shared_roll = self.shared_challenge_roll(recorded_bundle)
                if not upgraded:
                    reducer=ArchiveService(self.app,recorded_bundle,self.lua)
            product = self.bundle.tables.get('commerce_catalog', {}).get(command.get('sku'), {})
            recorded_price = product.get('price')
            if (not legacy_error and command['kind'] == 'commerce_purchase'
                    and version != self.bundle.hash and product.get('currency') == 'shop_points'):
                price_bundle = reducer.bundle if reducer is not self else Bundle(self.bundle.directory.parent/version)
                recorded_price = price_bundle.tables.get('commerce_catalog', {}).get(command.get('sku'), {}).get('price')
            if legacy_error:
                result={'ok':False,'error':legacy_error}
            elif command['kind'] == 'commerce_purchase' and product.get('currency') == 'shop_gold':
                # A currency pause applies to uncommitted older-client intents too.
                # Completed receipts already returned above and remain immutable.
                result = {'ok': False, 'error': 'shop_gold_not_open'}
            elif (command['kind'] == 'commerce_purchase' and version != self.bundle.hash
                  and product.get('currency') == 'shop_points'
                  and product.get('price') != recorded_price):
                # An old confirmation cannot authorize a newly increased price.
                # Close the old intent without charging; a refreshed catalog and
                # a fresh player confirmation are required for the current price.
                result = {'ok': False, 'error': 'commerce_price_changed'}
            elif (command['kind'] == 'commerce_purchase' and reducer is not self
                  and (unique_block := self.commerce_unique_block(profile, product))):
                # An unfinished historical intent cannot bypass today's shared
                # permanent ownership rule. Its recorded price/effects remain
                # intact, and completed receipts returned before this branch.
                result = {'ok': False, 'error': unique_block}
            elif version == self.bundle.hash or command["kind"] != "challenge":
                result=reducer.settle(profile,command,prepared["has_pass"])
            else:
                result=reducer.settle(profile,command,prepared["has_pass"],shared_roll)
            old=profile["save"]["gameplay_stats"]
            deltas={key:value-old.get(key,0) for key,value in result.get("gameplay_stats",{}).items() if value!=old.get(key,0)}
            archive=result.get("archive",{})
            archive.pop("processed",None) # DB receipts, not ever-growing Lua IDs, own remote deduplication.
            if isinstance(archive.get("online"),dict): archive["online"]["cursors"]={}
            commit_payload={"p_account":account,"p_id":operation_id,
                "p_revision":profile["revision"],"p_archive":archive,"p_deltas":deltas,
                "p_error":None if result.get("ok") else result.get("error","archive_rejected")}
            rpc="archive_commit"
            if command["kind"].startswith("lottery_") or command['kind'] in {'commerce_purchase','benefit_claim'}:
                rpc="archive_commit_lottery"
                commit_payload.update(p_inventory=result.get("content_inventory",{}),p_response=result.get("response",{}))
            committed=self.app.rpc_client.rpc(rpc,commit_payload)
            if committed.get("error")!="archive_revision_conflict": return committed
            prepared=self.app.rpc_client.rpc("archive_resume",{"p_account":account,"p_id":operation_id})
        return {"ok":False,"error":"archive_busy_retry"}

    def commerce_unique_block(self, profile, product):
        """Current permanent-ownership guard for an older uncommitted reducer."""
        from .unique_points import catalog, integer
        unique, aliases = catalog(self.bundle)
        canonical = lambda identity: aliases.get(identity, identity)
        marker = canonical(product.get('item_id'))
        components = product.get('grants', {}).get('items', {})
        # A historical receipt must not reopen a product paused in the current
        # catalog merely because its item changed from unique to stackable.
        if not product.get('enabled'):
            return 'product_unavailable'
        relevant = marker in unique or any(canonical(identity) in unique for identity in components)
        if not relevant:
            return ''
        inventory = profile.get('save', {}).get('content_inventory', {})

        def owned(identity):
            return any(canonical(key) == identity and integer(value) > 0
                       for key, value in inventory.items())

        if marker in unique:
            if owned(marker):
                return 'already_owned'
            if product.get('ownership_quantity', 1) != 1:
                return 'ownership_limit_reached'
        for identity, quantity in components.items():
            identity = canonical(identity)
            if identity in unique and (owned(identity) or quantity != 1):
                return 'component_already_owned'
        return ''

    def drain_online(self,database_account):
        # Persistent checkpoint outbox survives a Python crash between fishing and archive settlement.
        pending=self.app.rpc_client.rpc("archive_online_pending",{"p_account":database_account,"p_hash":self.bundle.hash})
        for operation in pending:
            prepared=self.app.rpc_client.rpc("archive_resume",{"p_account":database_account,"p_id":operation["id"]})
            result=self.finish_prepared(database_account,operation["id"],prepared)
            if not result.get("ok"): raise TimeoutError("archive_online_pending")

    def profile(self,payload):
        # Called after the existing profile loader initializes a new player.
        value=self.app.profile(payload)
        account=self.app._database_account_id(payload["account_id"])
        self.drain_online(account)
        for pending in self.app.rpc_client.rpc("archive_pending",{"p_account":account}):
            result=self.finish_prepared(account,pending["id"],self.app.rpc_client.rpc("archive_resume",{"p_account":account,"p_id":pending["id"]}))
            if not result.get("ok") and not result.get("terminal"):
                # A contested/incomplete settlement is not a successfully loaded save.
                raise TimeoutError("archive_pending_retry")
        value=self.app.rpc_client.rpc("get_fishing_profile",{"p_account_id":account})
        return self.app._public_response(value,account,payload["account_id"])

    def lottery_snapshot(self,payload):
        requested_hash = payload.get("config_hash")
        if not accepts(self.bundle, requested_hash, "lottery_snapshot"):
            return {"ok":False,"terminal":True,"error":"archive_config_mismatch","config_hash":self.bundle.hash}
        profile=self.profile({"account_id":payload.get("account_id")})
        reducer=self
        if requested_hash != self.bundle.hash:
            # Advertise the same currency/rates that this client's recorded
            # draw reducer uses, until the game joins the new bundle version.
            reducer=ArchiveService(self.app,Bundle(self.bundle.directory.parent/requested_hash),self.lua)
        projected=reducer.settle(profile,{"id":"lottery_snapshot","kind":"lottery_snapshot"},False)
        from .unique_points import limit_snapshot_ownership
        projected=limit_snapshot_ownership(projected,self.bundle)
        projected["config_hash"]=requested_hash
        return projected

def install(application,addon_root,lua):
    # Opt-in host setting: fail before config sync or player RPCs if malformed.
    from .test_access import install as install_test_access
    install_test_access(application)
    from .match_modes import install as install_match_modes
    install_match_modes()
    application._archive_modes_active = True
    root=Path(addon_root)
    current=json.loads((root/"server/bundles/current.json").read_text(encoding="utf-8"))
    service=ArchiveService(application,Bundle(root/"server/bundles"/current["hash"]),lua)
    service.sync()
    from .endless_leaderboard import install as install_endless_leaderboard
    install_endless_leaderboard(service)
    from .vip_progression import install as install_vip_progression
    install_vip_progression(service)
    return service
