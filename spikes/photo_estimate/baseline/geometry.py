"""Silhouette geometry: turn front + side person masks into body circumferences.

Pure numpy so the same math can be ported to Dart and run on the phone.
Masks are 2D bool arrays (True = person). Levels are given as a fraction of
standing height measured from the floor (0.0 = heels, 1.0 = top of head).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Extent:
    top: int  # first row containing the person
    bottom: int  # last row containing the person

    @property
    def height_px(self) -> int:
        return self.bottom - self.top + 1


def vertical_extent(mask: np.ndarray) -> Extent:
    rows = np.flatnonzero(mask.any(axis=1))
    if rows.size == 0:
        raise ValueError("mask is empty: no person found")
    return Extent(int(rows[0]), int(rows[-1]))


def row_for_level(ext: Extent, level: float) -> int:
    """Image row at `level` (fraction of height above the floor)."""
    return int(round(ext.bottom - level * (ext.height_px - 1)))


def torso_width_px(mask: np.ndarray, row: int, center_x: float | None = None) -> int:
    """Width of the contiguous run of person pixels that contains the body center.

    Taking the run around the center ignores arms held away from the torso.
    """
    line = mask[row]
    cols = np.flatnonzero(line)
    if cols.size == 0:
        return 0
    cx = int(round(center_x if center_x is not None else cols.mean()))
    if not line[cx]:  # center pixel can fall in a gap (e.g. between legs)
        cx = int(cols[np.argmin(np.abs(cols - cx))])
    left = cx
    while left > 0 and line[left - 1]:
        left -= 1
    right = cx
    while right < line.size - 1 and line[right + 1]:
        right += 1
    return right - left + 1


def ellipse_perimeter(width: float, depth: float) -> float:
    """Ramanujan's second approximation for an ellipse with full axes width x depth."""
    a, b = width / 2.0, depth / 2.0
    if a + b == 0:
        return 0.0
    h = ((a - b) ** 2) / ((a + b) ** 2)
    return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h)))


def circumference_cm(front: np.ndarray, side: np.ndarray, level: float, height_cm: float,
                     band: float = 0.0, mode: str = "at") -> float:
    """Circumference at `level`, from front width and side depth.

    band > 0 scans +/- band (fraction of height) around the level and takes the
    min (mode="min", e.g. natural waist / neck) or max (mode="max", e.g. hips).
    """
    fe, se = vertical_extent(front), vertical_extent(side)
    f_scale = height_cm / fe.height_px
    s_scale = height_cm / se.height_px
    levels = [level] if band <= 0 else list(np.linspace(level - band, level + band, 15))
    values = []
    for lv in levels:
        w = torso_width_px(front, row_for_level(fe, lv)) * f_scale
        d = torso_width_px(side, row_for_level(se, lv)) * s_scale
        values.append(ellipse_perimeter(w, d))
    if mode == "min":
        return float(min(values))
    if mode == "max":
        return float(max(values))
    return float(values[len(values) // 2])
