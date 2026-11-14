import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from score import _read, pair_sessions, score  # noqa: E402

DATA = os.path.join(HERE, "..", "data")


def test_example_scores():
    rep = score(pair_sessions(_read(os.path.join(DATA, "example_dexa.csv")),
                              _read(os.path.join(DATA, "example_estimates.csv")), 7))
    nav = rep["navy_silhouette"]
    assert nav["sessions"] == 3
    assert nav["raw_bias"] == pytest.approx(2.4, abs=0.01)  # always ~2.4 high
    assert nav["calib_mae"] < 0.2  # constant gap -> calibration removes it
    assert nav["repeat_sd"] == pytest.approx(0.42, abs=0.01)


def test_unpaired_sessions_dropped():
    paired = pair_sessions([{"scan_date": "2026-01-01", "body_fat_pct": "10"}],
                           [{"photo_date": "2026-03-01", "session": "x", "method": "m",
                             "repeat": "1", "bf_pct": "12"}], 7)
    assert paired == {}
