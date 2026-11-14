"""Checks the silhouette -> circumference math against a real 3D body mesh.

Renders front and side silhouettes of the CC0 MakeHuman body from the 3D spike,
then compares the ellipse estimate with the true mesh cross-section perimeter.
Run: BODY_GLB=path/to/body.glb python -I -m pytest tests -q   (from this folder)
"""
import os
import sys

import numpy as np
import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "baseline"))
from formulas import navy_bf_pct, rfm_bf_pct  # noqa: E402
from geometry import circumference_cm, ellipse_perimeter  # noqa: E402

GLB = os.environ.get("BODY_GLB")
HEIGHT_CM = 180.0
PX = 1600  # rendered image height


def test_ellipse_perimeter_circle():
    assert ellipse_perimeter(10, 10) == pytest.approx(np.pi * 10)


def test_navy_known_value():
    # 180 cm man, waist 80, neck 38: inch-form Navy gives 11.95 %, metric form 12.05 %
    assert navy_bf_pct("male", 180, 80, 38) == pytest.approx(12.0, abs=0.2)
    assert rfm_bf_pct("male", 180, 80) == pytest.approx(19.0)


def _load():
    trimesh = pytest.importorskip("trimesh")
    if not GLB or not os.path.exists(GLB):
        pytest.skip("set BODY_GLB to the 3D spike's body.glb")
    mesh = trimesh.load(GLB).to_geometry()
    lo, hi = mesh.bounds
    scale = HEIGHT_CM / (hi[1] - lo[1])
    mesh.apply_translation(-lo)
    mesh.apply_scale(scale)
    return mesh


def _silhouette(mesh, axis_h):
    import cv2
    v = mesh.vertices
    px_per_cm = PX / HEIGHT_CM
    xs = v[:, axis_h] - v[:, axis_h].min()
    width = int(np.ceil(xs.max() * px_per_cm)) + 20
    img = np.zeros((PX + 20, width), np.uint8)
    pts = np.stack([xs * px_per_cm + 10, (HEIGHT_CM - v[:, 1]) * px_per_cm + 10], axis=1)
    tris = np.round(pts[mesh.faces]).astype(np.int32)
    for t in tris:  # fillPoly on many polygons uses even-odd fill, so draw one by one
        cv2.fillConvexPoly(img, t, 1)
    return img.astype(bool)


def _true_perimeter(mesh, level):
    sec = mesh.section(plane_origin=[0, level * HEIGHT_CM, 0], plane_normal=[0, 1, 0])
    cx = (mesh.bounds[0][0] + mesh.bounds[1][0]) / 2
    best = None
    for path in sec.discrete:
        xs = path[:, 0]
        if xs.min() <= cx <= xs.max():
            per = float(np.sum(np.linalg.norm(np.diff(path, axis=0), axis=1)))
            best = per if best is None else max(best, per)
    return best


@pytest.mark.parametrize("name,level", [("neck", 0.855), ("waist", 0.60), ("hip", 0.505)])
def test_circumference_matches_mesh(name, level):
    mesh = _load()
    front, side = _silhouette(mesh, 0), _silhouette(mesh, 2)
    est = circumference_cm(front, side, level, HEIGHT_CM)
    true = _true_perimeter(mesh, level)
    print(f"{name}: estimate {est:.1f} cm, mesh {true:.1f} cm, error {100 * (est - true) / true:+.1f}%")
    # The ellipse reads 3-7 % low: real torso slices are boxier than an ellipse.
    # That bias is constant per person, so per-user DEXA calibration absorbs it.
    assert -0.08 < (est - true) / true < 0.0
