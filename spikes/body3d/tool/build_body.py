#!/usr/bin/env python3
"""Build assets/body/body.glb from the CC0 MakeHuman base mesh.

Output: one glTF binary with
  - POSITION + triangle indices for the MakeHuman base body (plus eyes),
    converted to flutter_scene's left-handed space (z negated, winding swapped),
  - 10 sparse morph targets: male, female, then for each sex
    fat_up, fat_down, muscle_up, muscle_down (MakeHuman macro targets),
  - two custom vertex attributes holding soft region masks (0..1, ubyte):
      _REGIONS_A = (arm_l, arm_r, leg_l, leg_r)
      _REGIONS_B = (trunk, head, android, gynoid)

Regional fat/muscle shapes are made at runtime by multiplying a global target
by a region mask, so the file stays small and every region can be driven
independently from DEXA numbers.

Usage:  python3 tool/build_body.py <makehuman_dir> assets/body/body.glb
<makehuman_dir> holds base.obj, default_weights.mhw and the .target files
(tool/fetch_makehuman.sh downloads them). All are CC0 (MakeHuman, Sept 2020).
"""
import json
import struct
import sys
from pathlib import Path

import numpy as np

KEEP_GROUPS = {"body", "helper-l-eye", "helper-r-eye"}
RACES = ["african", "asian", "caucasian"]

# Proportion shapes (MakeHuman measure targets, CC0), driven by measurements.
PROPORTIONS = ["shoulder-dist", "bust-circ", "waist-circ", "hips-circ", "upperarm-circ",
               "thigh-circ", "calf-circ", "upperarm-length", "lowerarm-length",
               "upperleg-height", "lowerleg-height"]

# Joint rings: vertices weighted to both bones of a joint. The app takes each
# ring's centroid as the joint centre for length measurements.
JOINTS = {
    "shoulder": ("shoulder01", "upperarm01"),
    "elbow": ("upperarm02", "lowerarm01"),
    "wrist": ("lowerarm02", "wrist"),
    "hip": ("pelvis", "upperleg01"),
    "knee": ("upperleg02", "lowerleg01"),
    "ankle": ("lowerleg02", "foot"),
}


def load_obj(path):
    verts, faces = [], []
    group = None
    for line in open(path):
        if line.startswith("v "):
            verts.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("g "):
            group = line.split()[1]
        elif line.startswith("f ") and group in KEEP_GROUPS:
            idx = [int(tok.split("/")[0]) - 1 for tok in line.split()[1:]]
            for i in range(1, len(idx) - 1):
                faces.append((idx[0], idx[i], idx[i + 1]))
    return np.array(verts, np.float32), np.array(faces, np.int64)


def load_target(path, n):
    d = np.zeros((n, 3), np.float32)
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        p = line.split()
        d[int(p[0])] = [float(p[1]), float(p[2]), float(p[3])]
    return d


def region_masks(weights, n, pos):
    """Soft masks from MakeHuman skin weights. Returns (n, 8) float."""
    def bones(pred):
        m = np.zeros(n, np.float32)
        for bone, pairs in weights.items():
            if pred(bone):
                for vi, w in pairs:
                    m[vi] += w
        return m

    arm = lambda s: (lambda b: b.endswith(s) and any(
        b.startswith(k) for k in ("shoulder", "upperarm", "lowerarm", "wrist", "finger", "metacarpal")))
    leg = lambda s: (lambda b: b.endswith(s) and any(
        b.startswith(k) for k in ("upperleg", "lowerleg", "foot", "toe")))
    face_prefixes = ("head", "jaw", "eye", "oculi", "oris", "risorius", "levator",
                     "orbicularis", "special", "tongue", "neck03")
    head = lambda b: b.startswith(face_prefixes)

    arm_l, arm_r = bones(arm(".L")), bones(arm(".R"))
    leg_l, leg_r = bones(leg(".L")), bones(leg(".R"))
    hd = bones(head)
    total = np.maximum(arm_l + arm_r + leg_l + leg_r + hd, 0)
    trunk = np.clip(1.0 - total, 0, 1)
    m = np.stack([arm_l, arm_r, leg_l, leg_r, trunk, hd], 1)
    m = np.clip(m, 0, None)
    s = m.sum(1, keepdims=True)
    s[s == 0] = 1
    m /= s

    # DEXA android (belly) and gynoid (hips) bands, by height on the body.
    y = pos[:, 1]
    trunk_w = m[:, 4]
    hip_y = np.average(y, weights=bones(lambda b: b.startswith("pelvis")) + 1e-9)
    chin_y = np.average(y, weights=bones(lambda b: b.startswith("jaw")) + 1e-9)
    span = chin_y - hip_y
    def band(lo, hi, soft):
        return np.clip((y - lo) / soft, 0, 1) * np.clip((hi - y) / soft, 0, 1)
    android = band(hip_y + 0.05 * span, hip_y + 0.40 * span, 0.08 * span) * trunk_w
    legs = m[:, 2] + m[:, 3]
    gynoid = band(hip_y - 0.55 * span, hip_y + 0.12 * span, 0.10 * span) * np.clip(trunk_w + legs, 0, 1)
    return np.concatenate([m, android[:, None], gynoid[:, None]], 1)


def smooth(values, faces, iters):
    n = values.shape[0]
    for _ in range(iters):
        acc = np.zeros_like(values)
        cnt = np.zeros((n, 1), np.float32)
        for a, b in ((0, 1), (1, 2), (2, 0)):
            np.add.at(acc, faces[:, a], values[faces[:, b]])
            np.add.at(cnt, faces[:, a], 1)
        values = 0.5 * values + 0.5 * acc / np.maximum(cnt, 1)
    return values


class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accessors = [], []

    def _view(self, data):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += data
        self.views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
        return len(self.views) - 1

    def dense(self, arr, ctype, typ, normalized=False, minmax=False):
        v = self._view(arr.tobytes())
        acc = {"bufferView": v, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = arr.min(0).tolist()
            acc["max"] = arr.max(0).tolist()
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def sparse_vec3(self, delta, eps=1e-5):
        idx = np.nonzero(np.abs(delta).max(1) > eps)[0].astype(np.uint32)
        vals = delta[idx].astype(np.float32)
        acc = {"componentType": 5126, "count": int(delta.shape[0]), "type": "VEC3",
               "min": delta.min(0).tolist(), "max": delta.max(0).tolist()}
        if len(idx):
            acc["sparse"] = {
                "count": int(len(idx)),
                "indices": {"bufferView": self._view(idx.tobytes()), "componentType": 5125},
                "values": {"bufferView": self._view(vals.tobytes())},
            }
        self.accessors.append(acc)
        return len(self.accessors) - 1


def main(src, out):
    src = Path(src)
    pos_all, faces_all = load_obj(src / "base.obj")
    n_all = pos_all.shape[0]

    def tgt(name):
        return load_target(src / f"{name}.target", n_all)

    shapes = {}
    for sex in ("male", "female"):
        shapes[sex] = sum(tgt(f"{r}-{sex}-young") for r in RACES) / len(RACES)
        u = f"universal-{sex}-young"
        shapes[f"{sex}_fat_up"] = tgt(f"{u}-averagemuscle-maxweight")
        shapes[f"{sex}_fat_down"] = tgt(f"{u}-averagemuscle-minweight")
        shapes[f"{sex}_muscle_up"] = tgt(f"{u}-maxmuscle-averageweight")
        shapes[f"{sex}_muscle_down"] = tgt(f"{u}-minmuscle-averageweight")

    for prop in PROPORTIONS:
        for d in ("incr", "decr"):
            shapes[f"prop_{prop}_{d}"] = tgt(f"measure-{prop}-{d}")

    weights = json.load(open(src / "default_weights.mhw"))["weights"]
    masks_all = region_masks(weights, n_all, pos_all + shapes["male"])

    # Keep only the vertices the kept faces use.
    used = np.unique(faces_all)
    remap = -np.ones(n_all, np.int64)
    remap[used] = np.arange(len(used))
    faces = remap[faces_all]
    pos = pos_all[used]
    masks = masks_all[used]
    # Soften region edges so a regional shape blends into its neighbour.
    masks = smooth(masks, faces, 4)
    deltas = {k: v[used] for k, v in shapes.items()}

    def bone_w(bone):
        w = np.zeros(n_all, np.float32)
        for vi, x in weights.get(bone, []):
            w[vi] = x
        return w

    joints = {}
    for name, (a, b) in JOINTS.items():
        for side in ("L", "R"):
            ring = np.nonzero((bone_w(f"{a}.{side}") > 0.15) & (bone_w(f"{b}.{side}") > 0.15))[0]
            ring = remap[ring]
            joints[f"{name}_{side.lower()}"] = [int(i) for i in ring if i >= 0]

    # Right-handed (MakeHuman, +Z front) -> flutter_scene left-handed:
    # negate z and swap winding so the body faces the default camera at -Z.
    flip = np.array([1, 1, -1], np.float32)
    pos = pos * flip
    deltas = {k: v * flip for k, v in deltas.items()}
    faces = faces[:, [0, 2, 1]]

    g = Glb()
    a_pos = g.dense(pos.astype(np.float32), 5126, "VEC3", minmax=True)
    a_idx = g.dense(faces.reshape(-1).astype(np.uint32), 5125, "SCALAR")
    q = lambda a: np.clip(np.round(a * 255), 0, 255).astype(np.uint8)
    a_ra = g.dense(q(masks[:, 0:4]), 5121, "VEC4", normalized=True)
    a_rb = g.dense(q(masks[:, 4:8]), 5121, "VEC4", normalized=True)
    order = ["male", "female"] + [f"{s}_{k}" for s in ("male", "female")
                                  for k in ("fat_up", "fat_down", "muscle_up", "muscle_down")]
    order += [f"prop_{p}_{d}" for p in PROPORTIONS for d in ("incr", "decr")]
    targets = [{"POSITION": g.sparse_vec3(deltas[k])} for k in order]

    gltf = {
        "asset": {"version": "2.0", "generator": "body3d build_body.py",
                  "copyright": "Base mesh, targets and weights: MakeHuman, CC0 1.0"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "body"}],
        "meshes": [{"name": "body", "extras": {"targetNames": order},
                    "weights": [0.0] * len(order),
                    "primitives": [{"attributes": {"POSITION": a_pos, "_REGIONS_A": a_ra,
                                                   "_REGIONS_B": a_rb},
                                    "indices": a_idx, "targets": targets}]}],
        "accessors": g.accessors, "bufferViews": g.views,
        "buffers": [{"byteLength": len(g.bin)}],
        "extras": {"regions": ["arm_l", "arm_r", "leg_l", "leg_r", "trunk", "head",
                               "android", "gynoid"], "units": "decimeters",
                   "joints": joints},
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(g.bin) % 4:
        g.bin.append(0)
    total = 12 + 8 + len(js) + 8 + len(g.bin)
    with open(out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(g.bin), 0x004E4942) + bytes(g.bin))

    # Sanity report.
    hard = masks[:, :6].argmax(1)
    names = gltf["extras"]["regions"]
    print(f"vertices {len(pos)}, triangles {len(faces)}, file {total/1e6:.2f} MB")
    for r in range(6):
        sel = hard == r
        print(f"  {names[r]:6s} {sel.sum():6d} verts, mean x {pos[sel,0].mean():+.2f}")
    print(f"  android verts>0.5: {(masks[:,6]>0.5).sum()}, gynoid verts>0.5: {(masks[:,7]>0.5).sum()}")
    for k, v in joints.items():
        print(f"  joint {k}: {len(v)} verts")
    print(f"  height {pos[:,1].max()-pos[:,1].min():.2f} units")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
