# Photo body-fat estimate spike

Question: can photos give a body-fat estimate good enough for the app's no-DEXA
entry point, and good enough to track change between DEXA scans once calibrated?

## What is here

| Path | What it does |
|---|---|
| `score.py` | Scores any method's estimates against DEXA: raw bias/MAE, same-session repeatability, DEXA-calibrated MAE (leave-one-out), and change-tracking error. |
| `baseline/` | On-device-style baseline: MediaPipe segmentation + pose on front and side photos, ellipse circumferences at neck/navel/hip, then US Navy and RFM equations. Pure numpy geometry, portable to Dart. |
| `tests/` | Unit tests; the geometry test renders the 3D spike's CC0 body mesh and checks silhouette circumferences against true mesh slices (ellipse reads 3-7 % low, a constant bias). |
| `llm_prompt.md` | Fixed prompt for LLM-vision estimates so repeats are comparable. |
| `data/example_*.csv` | Fake data showing the CSV formats. Real data stays in `data/` locally and is git-ignored. |

## Run

```bash
pip install mediapipe opencv-python-headless numpy pytest trimesh scipy
mkdir -p models && cd models
curl -LO https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task
curl -LO https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite
cd ..
python -I baseline/estimate.py --front photos/front.jpg --side photos/side.jpg --height-cm 178 --sex male --debug out/front_debug.png
BODY_GLB=../body3d/data/body.glb python -I -m pytest tests -q
python -I score.py data/dexa.csv data/estimates.csv
```

## Photo protocol (per session)

- Phone on a stable surface at waist height, about 2.5 m away, portrait, full body head to heels in frame, 1x lens.
- Plain wall, even light, no backlight. Morning, fasted, before training (no pump).
- Fitted shorts only (or shorts + sports bra), barefoot, hair off the neck.
- Pose: stand tall, feet hip width, arms out about 30-45 degrees so they don't touch the torso, relaxed belly (no sucking in).
- Shots: front, right side (arms forward slightly so they don't cover the waist), back.
- Repeat the full set 3 times, stepping out and back in between, to measure noise.
- Note date, time, weight that morning.
- Ideal: a session within 3 days of each DEXA scan, so it can be paired.
