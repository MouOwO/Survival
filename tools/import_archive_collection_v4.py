"""Import 43 original imagegen masters for all 60 fishing/work archive entries."""
import csv,hashlib,json,re,shutil,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
receipts=json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
expected={f"star_blessing_{i:03}" for i in range(1,27)}|{f"work_symbol_{i:02}" for i in range(1,18)}
assert len(receipts)==43 and {r["id"] for r in receipts}==expected
masters=ROOT/"panorama/src/images/custom_game/archive_collection_v4"
textures=ROOT/"panorama/src/images/custom_game/archive_gpu_regular"
masters.mkdir(parents=True,exist_ok=True)
template=(textures/"head_v2_friend_01.vtex").read_text(encoding="utf8")
assets={}
for row in receipts:
 identity=row["id"]
 match=re.search(r" as (C:\\[^\r\n]+?\.png) by default",row["output_hint"])
 assert match,"Missing image path: "+identity
 src=Path(match.group(1));assert src.is_file() and "generated_images" in src.parts
 blob=src.read_bytes();assert blob[:8]==b"\x89PNG\r\n\x1a\n"
 width,height=struct.unpack(">II",blob[16:24]);assert min(width,height)>=512
 shutil.copyfile(src,masters/(identity+".png"))
 texture=template.replace("custom_game/archive_heads_v2/friend_01.png","custom_game/archive_collection_v4/"+identity+".png")
 (textures/("collection_v4_"+identity+".vtex")).write_text(texture,encoding="utf8")
 assets[identity]={"id":identity,"name":row["name"],"icon_path":"custom_game/archive_collection_v4/"+identity+".png",
  "runtime_uri":"s2r://panorama/images/custom_game/archive_gpu_regular/collection_v4_"+identity+".vtex",
  "source_width":width,"source_height":height,"sha256":hashlib.sha256(blob).hexdigest(),
  "prompt":row["prompt"],"generator":"built-in image_gen","original_file":str(src)}
def asset_for(identity):
 if identity.startswith("work_"):
  return assets.get("work_symbol_"+str((int(identity[5:])-1)%17+1).zfill(2))
 return assets.get(identity)
p=next((ROOT/"data/csv").rglob("archive_item_icons.csv"))
with p.open(encoding="utf-8-sig",newline="") as stream:
 reader=csv.DictReader(stream);fields=reader.fieldnames;rows=list(reader)
updated=0
for row in rows:
 if row.get("category_id") not in ("work","fishing"):continue
 asset=asset_for(row["item_id"]);assert asset,row
 row.update(icon_id="archive_"+row["item_id"]+"_v4",icon_path=asset["icon_path"],display_width="88",display_height="88",art_status="generated_collection_v4")
 updated+=1
assert updated==60
with p.open("w",encoding="utf8",newline="") as stream:
 writer=csv.DictWriter(stream,fields,lineterminator="\n");writer.writeheader();writer.writerows(rows)
p=ROOT/"panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js"
s=p.read_text(encoding="utf8");start=s.index("entries=")+len("entries=")
entries,consumed=json.JSONDecoder().raw_decode(s[start:]);updated=0
for row in entries:
 if row.get("category_id") not in ("work","fishing"):continue
 asset=asset_for(row["item_id"]);assert asset,row
 row.update({k:asset[k] for k in ("icon_path","runtime_uri","source_width","source_height","sha256")})
 row.update(small_runtime_uri=asset["runtime_uri"],display_width=88,display_height=88,art_status="generated_collection_v4")
 for key in ("portrait","tint_icon","tone_color"):row.pop(key,None)
 updated+=1
assert updated==60
p.write_text(s[:start]+json.dumps(entries,ensure_ascii=False,separators=(",",":"))+s[start+consumed:],encoding="utf8")
manifest={"assets":assets,"items":{r["item_id"]:asset_for(r["item_id"])["id"] for r in rows if r.get("category_id") in ("work","fishing")}}
(ROOT/"data/ui/archive_collection_v4.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
print("ARCHIVE_COLLECTION_V4_IMPORTED: 43 untouched masters, 43 BGRA textures, 60 item mappings")
