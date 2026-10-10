"""Keep the small 3D shortcuts framed separately from the bottom HUD."""
import copy
import math
import re
from pathlib import Path

CAMERA_NAME = "shortcut_soft"
MODEL_MARGINS = {
    "models/heroes/wisp/wisp.vmdl": 1.45,
    "models/heroes/axe/axe.vmdl": 1.35,
    "models/heroes/doom/doom.vmdl": 1.65,
    "models/heroes/nevermore/nevermore.vmdl": 1.40,
    "models/heroes/drow/drow_base.vmdl": 1.35,
    "models/heroes/monkey_king/monkey_king.vmdl": 1.40,
    "models/heroes/juggernaut/juggernaut.vmdl": 1.35,
}


def add_shortcut_cameras(portraits):
    for model, margin in MODEL_MARGINS.items():
        cameras = portraits[model]["cameras"]
        default_name = next(name for name in cameras if name.lower() == "default")
        camera = copy.deepcopy(cameras[default_name])
        # Widen the frustum, preserving the native face direction and animation.
        fov = float(camera["PortraitFOV"])
        camera["PortraitFOV"] = f"{math.degrees(2 * math.atan(math.tan(math.radians(fov / 2)) * margin)):.4f}"
        cameras[CAMERA_NAME] = camera
    return portraits


def write_shortcut_cameras(path):
    from build_wave_monster_cosmetics import parse_kv
    source = path.read_text(encoding="utf-8-sig")
    before = parse_kv(source)["Portraits"]
    after = add_shortcut_cameras(copy.deepcopy(before))
    # Insert only the new camera, retaining all other text and profiles exactly.
    for model in MODEL_MARGINS:
        model_start = source.index('"' + model + '"')
        cameras_start = source.index('"cameras"', model_start)
        opening = source.index("{", cameras_start)
        depth, closing = 1, opening + 1
        while depth:
            depth += (source[closing] == "{") - (source[closing] == "}")
            closing += 1
        block = source[opening:closing]
        block = re.sub(r'\n\s*"shortcut_soft"\s*\{[^{}]*\}', "", block)
        camera = after[model]["cameras"][CAMERA_NAME]
        new_camera = '\n            "' + CAMERA_NAME + '"\n            {\n'
        new_camera += "".join(f'                "{key}" "{value}"\n' for key, value in camera.items())
        new_camera += "            }\n        }"
        block = block[:block.rfind("}")].rstrip() + new_camera
        source = source[:opening] + block + source[closing:]
    actual = parse_kv(source)["Portraits"]
    if actual != after:
        raise ValueError("Unexpected portrait data change")
    path.write_text(source, encoding="utf-8")
    print("SHORTCUT_CAMERAS_PASS", len(MODEL_MARGINS), "default cameras unchanged")


if __name__ == "__main__":
    write_shortcut_cameras(Path(__file__).resolve().parents[1] / "scripts/npc/portraits_custom.txt")
