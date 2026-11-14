#!/usr/bin/env python3
"""Turn a BodySpec spike dump into data/local/scans.json for the 3D app.

Keeps only body-composition numbers, scan date and height. Drops names,
email, phone, ids, locations and tokens. The output is gitignored: it is
still personal health data.

Usage: python3 tool/import_bodyspec.py <bodyspec_dump.json> [male|female]
"""
import json
import sys
from pathlib import Path

dump = json.load(open(sys.argv[1]))
sex = sys.argv[2] if len(sys.argv) > 2 else "male"
out = []
for s in dump["scans"]:
    c = s["composition"]
    regions = {k: {"lean_kg": v["lean_mass_kg"], "fat_kg": v["fat_mass_kg"]}
               for k, v in c["regions"].items()}
    limbs = ("left_arm", "right_arm", "left_leg", "right_leg", "trunk")
    # BodySpec has no head region: head = total minus arms, legs and trunk.
    regions["head"] = {
        "lean_kg": round(c["total"]["lean_mass_kg"] - sum(regions[k]["lean_kg"] for k in limbs), 2),
        "fat_kg": round(c["total"]["fat_mass_kg"] - sum(regions[k]["fat_kg"] for k in limbs), 2),
    }
    out.append({
        "date": s["detail"]["start_time"][:10],
        "source": "BodySpec",
        "sex": sex,
        "height_cm": s["scan-info"]["patient_intake"]["height_cm"],
        "bone_kg": c["total"]["bone_mass_kg"],
        "visceral_fat_g": round(s["visceral-fat"]["vat_mass_kg"] * 1000),
        "regions": regions,
    })
out.sort(key=lambda x: x["date"])
dest = Path(__file__).resolve().parent.parent / "data" / "local" / "scans.json"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps({"scans": out}, indent=1))
print(f"wrote {len(out)} scans to {dest}")
