# 3D body spike

Flutter + flutter_scene prototype: a 3D body reshaped from DEXA-style regional
numbers (lean and fat per arm, leg, trunk, plus android/gynoid fat), animated
between two scans, in three visual styles, with tap-to-select body parts.
Data is fake (`lib/body/dexa_scan.dart`) until the BodySpec spike provides real scans.

## Run

```sh
flutter run --enable-flutter-gpu      # Flutter GPU is also enabled in Info.plist / AndroidManifest
flutter test                          # shaper tests (visceral fat never changes shape, etc.)
```

## How it works

- `data/body.glb` (1.5 MB) is built by `tool/build_body.py` from the MakeHuman base mesh
  (CC0): base body, 10 sparse morph targets (male, female, fat up/down, muscle up/down per sex)
  and per-vertex soft region masks (arms, legs, trunk, head, android band, gynoid band)
  derived from MakeHuman's CC0 skin weights. Rebuild: `tool/fetch_makehuman.sh .makehuman`
  then `python3 tool/build_body.py .makehuman data/body.glb` (needs numpy).
- `BodyShaper` (pure Dart) turns a scan into vertex positions: each region's fat/lean ratio
  against a reference body sets how much of the masked fat/muscle target to apply.
  Visceral fat is shown as a number only. Tuning constants live in `ShapeReference`.
- `BodyScene` renders one flutter_scene node per region, each a morphed mesh with one
  target (scan A -> scan B), so the GPU only blends two shapes (flutter_scene blends at most
  8 targets per draw). Tap picking is a CPU ray test in Dart, so it does not depend on the
  renderer.

## Licenses

MakeHuman base mesh, targets and weights: CC0 1.0 (released Sept 2020,
https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.ASSETS.md).
flutter_scene: MIT.
