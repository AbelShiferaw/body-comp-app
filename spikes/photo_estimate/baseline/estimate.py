"""On-device-style baseline: front + side photo -> circumferences -> body fat %.

Uses MediaPipe (person segmentation + pose landmarks), which also ships for
iOS/Android, so this pipeline can run fully on the phone with no upload.

    python -I baseline/estimate.py --front f.jpg --side s.jpg \
        --height-cm 178 --sex male [--debug out.png]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict, dataclass

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from formulas import navy_bf_pct, rfm_bf_pct  # noqa: E402
from geometry import circumference_cm, vertical_extent  # noqa: E402

MODELS_DIR = os.environ.get("PHOTO_SPIKE_MODELS", os.path.join(os.path.dirname(__file__), "..", "models"))

# Default levels as a fraction of stature (adult anthropometric averages).
DEFAULT_LEVELS = {"neck": 0.855, "waist": 0.600, "hip": 0.505}


@dataclass
class Result:
    height_cm: float
    neck_cm: float
    waist_cm: float
    hip_cm: float
    navy_bf_pct: float
    rfm_bf_pct: float
    levels: dict


def person_mask(image_path: str) -> tuple[np.ndarray, np.ndarray]:
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision

    img = mp.Image.create_from_file(image_path)
    seg = vision.ImageSegmenter.create_from_options(vision.ImageSegmenterOptions(
        base_options=BaseOptions(model_asset_path=os.path.join(MODELS_DIR, "selfie_multiclass_256x256.tflite")),
        output_category_mask=True))
    cat = seg.segment(img).category_mask.numpy_view()
    mask = cat.squeeze() != 0  # 0 = background; hair/skin/clothes/other all count
    ext = vertical_extent(mask)
    if ext.height_px < 0.5 * mask.shape[0]:
        raise ValueError(f"{image_path}: person not found or not full body in frame")
    return mask, img.numpy_view()


def landmark_levels(image_path: str, mask: np.ndarray) -> dict:
    """Neck / navel / hip levels from pose landmarks on the front photo."""
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision

    img = mp.Image.create_from_file(image_path)
    det = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=os.path.join(MODELS_DIR, "pose_landmarker_heavy.task"))))
    res = det.detect(img)
    if not res.pose_landmarks:
        return dict(DEFAULT_LEVELS)
    lm = res.pose_landmarks[0]
    h = mask.shape[0]
    ext = vertical_extent(mask)

    def level(y_norm: float) -> float:
        return (ext.bottom - y_norm * h) / (ext.height_px - 1)

    shoulder = level((lm[11].y + lm[12].y) / 2)
    hip = level((lm[23].y + lm[24].y) / 2)
    mouth = level((lm[9].y + lm[10].y) / 2)
    levels = {
        "neck": shoulder + 0.45 * (mouth - shoulder),
        "waist": hip + 0.27 * (shoulder - hip),  # navel, per Navy protocol
        "hip": hip - 0.02,
    }
    if not 0.3 < levels["hip"] < levels["waist"] < levels["neck"] < 0.95:
        return dict(DEFAULT_LEVELS)  # landmarks implausible: use population averages
    return levels


def estimate_from_masks(front: np.ndarray, side: np.ndarray, height_cm: float, sex: str,
                        levels: dict | None = None) -> Result:
    lv = levels or DEFAULT_LEVELS
    neck = circumference_cm(front, side, lv["neck"], height_cm, band=0.02, mode="min")
    waist = circumference_cm(front, side, lv["waist"], height_cm)
    hip = circumference_cm(front, side, lv["hip"], height_cm, band=0.03, mode="max")
    return Result(height_cm, neck, waist, hip,
                  navy_bf_pct(sex, height_cm, waist, neck, hip),
                  rfm_bf_pct(sex, height_cm, waist), lv)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--front", required=True)
    p.add_argument("--side", required=True)
    p.add_argument("--height-cm", type=float, required=True)
    p.add_argument("--sex", choices=["male", "female"], required=True)
    p.add_argument("--debug", help="write mask overlay PNG here")
    a = p.parse_args()
    fmask, fimg = person_mask(a.front)
    smask, _ = person_mask(a.side)
    levels = landmark_levels(a.front, fmask)
    r = estimate_from_masks(fmask, smask, a.height_cm, a.sex, levels)
    if a.debug:
        import cv2
        over = cv2.cvtColor(np.ascontiguousarray(fimg[..., :3]), cv2.COLOR_RGB2BGR)
        over[fmask] = (0.5 * over[fmask] + [0, 90, 0]).astype(np.uint8)
        ext = vertical_extent(fmask)
        for name, lvl in levels.items():
            y = int(round(ext.bottom - lvl * (ext.height_px - 1)))
            cv2.line(over, (0, y), (over.shape[1], y), (0, 0, 255), 2)
            cv2.putText(over, name, (10, y - 6), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
        cv2.imwrite(a.debug, over)
    print(json.dumps(asdict(r), indent=2))


if __name__ == "__main__":
    main()
