"""Read-only migration probe. Credentials come from server environment, never logs."""
import json
import os
import sys
import urllib.request
import urllib.error

url = os.environ["SUPABASE_URL"].rstrip("/")
key = os.environ.get("SUPABASE_SECRET_KEY") or os.environ["SUPABASE_SERVICE_ROLE_KEY"]
result = {}
opener = urllib.request.build_opener(urllib.request.ProxyHandler({})) if "--direct" in sys.argv else urllib.request.build_opener()
checks = {table: "*" for table in ["player_archive_state", "archive_config_sets", "archive_operations", "archive_online_outbox"]}
checks["player_gameplay_stats"] = "wall_wave_boss_stun_seconds,hero_attack_pct_per_minute,tower_attack_pct_per_minute,hero_attributes_pct_per_minute"
for table, columns in checks.items():
    request = urllib.request.Request(url + "/rest/v1/" + table + "?select=" + columns + "&limit=0",
        headers={"apikey":key,"Authorization":"Bearer " + key})
    try:
        with opener.open(request,timeout=15) as response:
            result[table] = {"status":response.status}
    except urllib.error.HTTPError as error:
        try: code=json.loads(error.read()).get("code")
        except (ValueError,AttributeError): code="unparseable"
        result[table]={"status":error.code,"code":code}
    except urllib.error.URLError as error:
        result[table]={"error":type(error.reason).__name__,"detail":str(error.reason).replace(key,"[redacted]")}
print(json.dumps(result,ensure_ascii=False,indent=2))
