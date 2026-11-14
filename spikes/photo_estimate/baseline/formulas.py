"""Published anthropometric body-fat equations (all inputs in cm)."""
from __future__ import annotations

import math


def navy_bf_pct(sex: str, height_cm: float, waist_cm: float, neck_cm: float,
                hip_cm: float | None = None) -> float:
    """US Navy circumference method (Hodgdon & Beckett 1984), metric form."""
    if sex == "male":
        return 495.0 / (1.0324 - 0.19077 * math.log10(waist_cm - neck_cm)
                        + 0.15456 * math.log10(height_cm)) - 450.0
    if hip_cm is None:
        raise ValueError("female Navy formula needs hip circumference")
    return 495.0 / (1.29579 - 0.35004 * math.log10(waist_cm + hip_cm - neck_cm)
                    + 0.22100 * math.log10(height_cm)) - 450.0


def rfm_bf_pct(sex: str, height_cm: float, waist_cm: float) -> float:
    """Relative Fat Mass (Woolcott & Bergman 2018), validated against DXA."""
    return 64.0 - 20.0 * (height_cm / waist_cm) + (12.0 if sex == "female" else 0.0)
