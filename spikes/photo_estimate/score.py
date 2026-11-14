"""Score photo body-fat estimates against DEXA ground truth.

    python -I score.py data/dexa.csv data/estimates.csv [--max-days 7]

dexa.csv:       scan_date,body_fat_pct[,lean_mass_kg]
estimates.csv:  photo_date,session,method,repeat,bf_pct

A session is one photo shoot. Estimates are paired with the closest DEXA scan
within --max-days. Per method this reports:
  raw     mean error and MAE vs DEXA (what a new user without DEXA gets)
  repeat  SD across repeats in the same session (noise: needs to be well below
          the ~0.5-1 pt monthly change we want to show)
  calib   leave-one-out MAE after subtracting the user's average gap from the
          other paired sessions (what a user with DEXA calibration gets)
  change  error in the change between two paired sessions vs DEXA's change
"""
from __future__ import annotations

import argparse
import csv
import itertools
import statistics as st
from collections import defaultdict
from datetime import date


def _read(path: str) -> list[dict]:
    with open(path, newline="") as f:
        return [r for r in csv.DictReader(f) if any(v.strip() for v in r.values())]


def _d(s: str) -> date:
    return date.fromisoformat(s.strip())


def pair_sessions(dexa: list[dict], est: list[dict], max_days: int) -> dict:
    """{method: {session: {"dexa": bf, "values": [bf, ...]}}} for paired sessions."""
    scans = [(_d(r["scan_date"]), float(r["body_fat_pct"])) for r in dexa]
    out: dict = defaultdict(dict)
    for r in est:
        pd_ = _d(r["photo_date"])
        gap, bf = min(((abs((pd_ - sd).days), bf) for sd, bf in scans), key=lambda t: t[0])
        if gap > max_days:
            continue
        s = out[r["method"]].setdefault(r["session"], {"dexa": bf, "values": [], "date": pd_})
        s["values"].append(float(r["bf_pct"]))
    return out


def score(paired: dict) -> dict:
    report = {}
    for method, sessions in sorted(paired.items()):
        means = {k: st.mean(v["values"]) for k, v in sessions.items()}
        gaps = {k: means[k] - v["dexa"] for k, v in sessions.items()}
        sds = [st.stdev(v["values"]) for v in sessions.values() if len(v["values"]) > 1]
        m = {
            "sessions": len(sessions),
            "raw_bias": st.mean(gaps.values()),
            "raw_mae": st.mean(abs(g) for g in gaps.values()),
            "repeat_sd": st.mean(sds) if sds else None,
        }
        if len(sessions) >= 2:
            loo = [abs(gaps[k] - st.mean(g for j, g in gaps.items() if j != k)) for k in gaps]
            m["calib_mae"] = st.mean(loo)
            ordered = sorted(sessions, key=lambda k: sessions[k]["date"])
            ch = [abs((means[b] - means[a]) - (sessions[b]["dexa"] - sessions[a]["dexa"]))
                  for a, b in itertools.combinations(ordered, 2)
                  if sessions[a]["dexa"] != sessions[b]["dexa"]]
            m["change_mae"] = st.mean(ch) if ch else None
        report[method] = m
    return report


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("dexa")
    p.add_argument("estimates")
    p.add_argument("--max-days", type=int, default=7)
    a = p.parse_args()
    rep = score(pair_sessions(_read(a.dexa), _read(a.estimates), a.max_days))
    cols = ["sessions", "raw_bias", "raw_mae", "repeat_sd", "calib_mae", "change_mae"]
    print("method".ljust(22) + "".join(c.rjust(12) for c in cols))
    for method, m in rep.items():
        cells = [m.get(c) for c in cols]
        print(method.ljust(22) + "".join(
            ("-" if v is None else f"{v:.2f}" if isinstance(v, float) else str(v)).rjust(12) for v in cells))


if __name__ == "__main__":
    main()
