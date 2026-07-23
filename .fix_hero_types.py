from pathlib import Path
import csv

path = Path(r"D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\data\csv\英雄系统\hero_definitions.csv")
lines = path.read_text(encoding="utf-8-sig").splitlines()
headers = next(csv.reader([lines[0]]))
strings = {
    "hero_id", "unit_name", "display_name", "public_skill_pool_id",
    "exclusive_skill_group_id", "notes", "projectile_model",
}
enums = {"primary_attribute"}
booleans = {"vip_required", "enabled"}
types = [
    "string" if key in strings else
    "enum" if key in enums else
    "boolean" if key in booleans else
    "number"
    for key in headers
]
assert len(headers) == len(types) == 41
lines[2] = "#types:" + ",".join(types)
path.write_bytes(("\n".join(lines) + "\n").encode("utf-8"))

rows = list(csv.reader(path.read_text(encoding="utf-8").splitlines()))
parsed_types = rows[2]
parsed_types[0] = parsed_types[0][7:]
assert len(rows[0]) == len(parsed_types) == len(rows[3]) == 41
print("HERO_TYPES_FIXED", len(parsed_types))