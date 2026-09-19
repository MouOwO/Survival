"""Author the building enlargement into ModelDoc, with matching pick/PHYS boxes."""
import re

MODEL_SOURCE_SCALE = 2.0
BASE_WIDTH = 118.0


def resize_modeldoc(text, target=MODEL_SOURCE_SCALE):
    mesh_pattern = r'(_class="RenderMeshFile"[^{}]*?import_scale=)([\d.]+)'
    current = re.search(mesh_pattern, text)
    assert current, 'missing mesh import scale'
    factor = target / (float(current[2]) / .01)
    text, count = re.subn(mesh_pattern, lambda m: m[1]+str(.01*target), text)
    assert count == 1
    def box(match):
        values = [float(v)*factor for v in match[2].split(',')]
        return match[1]+'['+','.join(format(v, '.12g') for v in values)+']'
    text, count = re.subn(r'(hitbox_(?:mins|maxs)=)\[([^\]]+)\]', box, text)
    assert count == 6, 'all three selection sets must be resized'
    text, count = re.subn(r'(_class="PhysicsHullFile"[^{}]*?import_scale=)([\d.]+)',
                         lambda m: m[1]+str(target), text)
    assert count == 1
    return text


if __name__ == '__main__':
    import json
    from pathlib import Path
    stage = Path(__file__).resolve().parents[1]/'output/unique_buildings'
    manifest_path = stage/'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    for entry in manifest:
        path = stage/'source/models/survival_buildings'/(entry['name']+'.vmdl')
        path.write_text(resize_modeldoc(path.read_text(encoding='utf-8')), encoding='utf-8')
        entry['model_source_scale'] = MODEL_SOURCE_SCALE
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('MODELDOC_RESIZE_PASS models=24 scale=2 selection_sets=72 physics=24')
