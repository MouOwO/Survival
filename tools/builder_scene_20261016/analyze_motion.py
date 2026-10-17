"""Measure the bright magenta Io core in unchanged native screenshot frames."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'output/video_shop_20261015/deps'))
import cv2
import numpy as np


def analyze(tag):
    directory = ROOT / 'output/builder_scene_20261016' / tag
    capture = json.loads((directory / 'capture.json').read_text('utf-8-sig'))
    values = []
    for frame in capture['frames']:
        raw = cv2.imread(str(directory / frame['file']))
        image = raw[17:132, 17:140].astype(np.int16)
        b, g, r = image[:, :, 0], image[:, :, 1], image[:, :, 2]
        ys, xs = np.where((r > 25) & (b > 25) & (r > g * 1.5) & (b > g * 1.3))
        if len(ys) < 8:
            raise ValueError(f'Core is obscured in {tag}/{frame["file"]}')
        values.append({'frame': frame['frame'], 'milliseconds': frame['milliseconds'],
                       'pixels': len(ys), 'center_y': float(ys.mean() + 17), 'center_x': float(xs.mean() + 17),
                       'top': int(ys.min() + 17), 'bottom': int(ys.max() + 17)})
    centers = np.array([row['center_y'] for row in values])
    # Diagnostic only: the core itself changes shape as its lights animate.
    return {'tag': tag, 'frames': len(values), 'duration_ms': values[-1]['milliseconds'],
            'centroid_y_peak_to_peak_pixels': float(np.ptp(centers)),
            'centroid_y_standard_deviation_pixels': float(np.std(centers)),
            'average_frame_delta_pixels': float(np.mean(np.abs(np.diff(centers)))),
            'min_frame': int(np.argmin(centers)), 'max_frame': int(np.argmax(centers)),
            'samples': values,
            'caveat': 'Bright-core centroid also moves with native shape/light animation; this is a screen-space observation, not the skeletal root position.'}


if __name__ == '__main__':
    reports = [analyze(tag) for tag in (sys.argv[1:] or ['final_alpha'])]
    target = ROOT / 'output/builder_scene_20261016/motion_analysis.json'
    target.write_text(json.dumps(reports, indent=2) + '\n', encoding='utf-8')
    print(json.dumps([{key: val for key, val in report.items() if key != 'samples'} for report in reports]))
