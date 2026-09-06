"""Prepare reviewable backend changes inside the addon; deploy script copies them afterward."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=Path(r"D:\survival_database\backend\fishing_api\server.py")
text=source.read_text(encoding="utf-8-sig")
if 'SURVIVAL_ARCHIVE_HTTP' not in text:
    text=text.replace('import json\n','import json\nimport os\n')
    text=text.replace('response = application.profile(payload)',
        'response = application.archive.profile(payload) if getattr(application, "archive", None) else application.profile(payload)')
    text=text.replace('elif self.path == "/v1/rewards/grant":', '''elif self.path == "/v1/archive/config":
                    if not getattr(application, "archive", None): raise ApiError("archive_disabled", 503)
                    response = {"ok": True, "protocol": 1, "config_hash": application.archive.bundle.hash}
                elif self.path == "/v1/archive/command":
                    if not getattr(application, "archive", None): raise ApiError("archive_disabled", 503)
                    from archive_backend.service import ArchiveError
                    try:
                        response = application.archive.command(payload)
                    except ArchiveError as error:
                        raise ApiError(str(error), 400) from error
                elif self.path == "/v1/rewards/grant":''')
    text=text.replace('_log_checkpoint_summary(payload, response)', '''_log_checkpoint_summary(payload, response)
                    if getattr(application, "archive", None):
                        account = application._database_account_id(payload["account_id"])
                        application.archive.drain_online(account)
                        response["profile"] = application.archive.profile({"account_id": payload["account_id"]})''')
    text=text.replace('application.sync_definitions()\n    return application',r'''application.sync_definitions()
    if os.environ.get("SURVIVAL_ARCHIVE_HTTP") == "1":
        from archive_backend.service import install
        application.archive = install(application, os.environ["SURVIVAL_ADDON_ROOT"],
            os.environ.get("ARCHIVE_LUA_PATH", r"C:\Program Files\lua\bin\lua5.1.exe"))
    return application''')
target=root/'server/staged/fishing_api/server.py'
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(text,encoding='utf-8')
stats=source.with_name('gameplay_stats.py').read_text(encoding='utf-8-sig')
if 'import math' not in stats:stats=stats.replace('import csv\n','import csv\nimport math\nimport re\n')
stats=stats.replace('return int(value) if value.is_integer() else value','if not math.isfinite(value): raise GameplayStatsError("nonfinite gameplay stat")\n    return int(value) if value.is_integer() else value') if 'nonfinite gameplay stat' not in stats else stats
stats=stats.replace('            if field_id in result:', '            if not re.fullmatch(r"[a-z][a-z0-9_]*", field_id): raise GameplayStatsError("invalid field_id")\n            if field_id in result:') if 'invalid field_id' not in stats else stats
stats=stats.replace('    if len(result) != 38:\n        raise GameplayStatsError(f"expected 38 gameplay stats plus player_id, got {len(result)}")','    if not result:\n        raise GameplayStatsError("gameplay stats CSV is empty")')
target.with_name('gameplay_stats.py').write_text(stats,encoding='utf-8')
tests=source.parents[1]/'tests/test_fishing_api.py'
test_text=tests.read_text(encoding='utf-8-sig').replace('data/csv/玩家档案系统/fishing_reward_definitions.csv','data/csv/挑战与奖励系统/fishing_reward_definitions.csv')
test_text=test_text.replace('test_gameplay_stats_csv_has_38_typed_defaults_plus_player_id','test_gameplay_stats_csv_supports_extended_archive_fields')
test_text=test_text.replace('self.assertEqual(len(stats), 38)','self.assertGreaterEqual(len(stats), 93)\n        self.assertIn("hero_attribute_bonus_pct", stats)')
test_text=test_text.replace('self.assertEqual(stats["tower_attack_interval"], 1.7)','self.assertEqual(stats["tower_attack_interval"], 0)')
test_target=root/'server/staged/tests/test_fishing_api.py';test_target.parent.mkdir(parents=True,exist_ok=True)
test_target.write_text(test_text,encoding='utf-8')
print('ARCHIVE_HTTP_STAGED',target)
