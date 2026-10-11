#!/usr/bin/env python3
"""Mario Raceway for the kart demo, from the decompilation's data and your own rip of the course.

Two things come out of this script, and the demo needs only the first:

* ``addons/gta/mk/scenes/mario_raceway.tscn``, the **primitive course**, which is committed. Its
  racing line, item boxes, trees and piranha plants are the game's own placements, read out of
  ``courses/mario_raceway/course_data.c`` in the public mk64 decompilation (fetched into
  ``.addon_cache/mk64/`` the first time). Its road is a flat slab extruded along the real road's
  centre line, 11 m wide as the game's is, its walls are boxes where the game's fences stand, the
  grandstand is a box of the right size in the right place and the warp pipe is a hollow cylinder
  the road runs through. The collision is the shape of the real course; only the dressing is
  primitive.

* ``addons/gta/mk/assets/courses/mario_raceway.glb``, the **ripped course**, which is git-ignored:
  the textured model converted to metres and the game's own axes, with collision-only nodes for
  the road, the grass, the sand and the solid things. ``MkCourse`` swaps it in for the primitives
  when it is there. The rip is the one on The Models Resource (a Blender export of the course as
  ``Mario Raceway.obj`` with its textures beside it); give the script the zip or the folder.

Both come from the same fit: the game's track path, in game units, is laid over the rip's road
until it runs down the middle of it, which gives the rip's scale and orientation. The scale is
read, not assumed, and printed. One game unit is a ninth of a metre (``MkConst.UNIT``).

    python tools/mk64_course.py "Nintendo 64 - Mario Kart 64 - Courses - Mario Raceway.zip"
    python tools/mk64_course.py --rip "path/to/Mario Raceway"   # an unpacked folder
    python tools/mk64_course.py --scene-only                    # the primitive scene needs the rip too:
                                                                #   the road centre line is measured on it

Needs Pillow for the road mask and the textures.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import re
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tm2"))
import glb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
UNIT_METRES = 1.0 / 9.0  # MkConst.UNIT
COURSE = "mario_raceway"
SCENE = ROOT / "addons/gta/mk/scenes/mario_raceway.tscn"
MODEL = ROOT / "addons/gta/mk/assets/courses/mario_raceway.glb"
CACHE = ROOT / ".addon_cache/mk64"
DECOMP_URL = "https://raw.githubusercontent.com/n64decomp/mk64/master/courses/mario_raceway/course_data.c"
RACING_LINE_SCRIPT = "res://addons/gta/mk/scripts/mk_course.gd"
ITEM_BOX_SCENE = "res://addons/gta/mk/scenes/mk_item_box.tscn"

ROAD_WIDTH_UNITS = 99.0  # measured on the rip against the game's path: 11.0 m, the same all the way round
WALL_HEIGHT_M = 2.5
WALL_THICKNESS_M = 0.3

# The rip's groups, by the number Blender left on each "Shape_IndexedFaceSet", and what each is.
# Read off the textures and the footprint of every group; see the README for the method.
RIP_GROUPS = {
    # the finish stripe is its own polygon sitting in a hole cut in the road, so it is road too
    "road": {"030", "032"},
    "grass": {"062", "108", "110"},
    "sand": {"042", "044"},
    # fences, the warp pipe, the grandstand, the toadstool and the ring of hills: things a kart stops against
    "solid": {"120", "084", "007", "014", "010", "147", "117", "119", "073", "126", "134", "145"},
}
RIP_FENCES = ["120", "084", "007", "014", "010"]
RIP_WARP_PIPE = "147"  # the giant green pipe the road runs through before the last corner
RIP_GRANDSTAND = "117"  # the stand by the start, with the Mario cap on top
START_LINE_TEXTURE = "92276F6"  # the finish stripe's texture hash in the rip; its group anchors the fit


# ---------------------------------------------------------------------------
# The decompilation's data

def fetch_course_data(cache: Path = CACHE) -> str:
    """The course's data file from the decompilation, cached beside the addon cache."""
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / "mario_raceway_course_data.c"
    if not target.is_file():
        print(f"fetching {DECOMP_URL}")
        with urllib.request.urlopen(DECOMP_URL, timeout=60) as response:
            target.write_bytes(response.read())
    return target.read_text(encoding="utf-8", errors="replace")


def parse_path(source: str, name: str) -> list[tuple[int, int, int, int]]:
    """A TrackPathPoint table: (x, y, z, section) in game units, without the -32768 terminator."""
    match = re.search(re.escape(name) + r"\[\] = \{(.*?)\n\};", source, re.S)
    if not match:
        raise ValueError(f"no table {name}")
    points = re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(\d+)\s*\}", match.group(1))
    return [tuple(int(v) for v in p) for p in points if int(p[0]) != -32768]


def parse_spawns(source: str, name: str) -> list[tuple[int, int, int, int]]:
    """An ActorSpawnData table: (x, y, z, kind), without the terminator."""
    match = re.search(re.escape(name) + r"\[\] = \{(.*?)\n\};", source, re.S)
    if not match:
        raise ValueError(f"no table {name}")
    points = re.findall(r"\{\s*\{\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\s*\},\s*\{\s*(\d+)\s*\}\s*\}", match.group(1))
    return [tuple(int(v) for v in p) for p in points if int(p[0]) != -32768]


def course_tables(source: str) -> dict:
    return {
        "path": parse_path(source, "d_course_mario_raceway_track_path"),
        "boxes": parse_spawns(source, "d_course_mario_raceway_item_box_spawns"),
        "plants": parse_spawns(source, "d_course_mario_raceway_piranha_plant_spawns"),
        "trees": parse_spawns(source, "d_course_mario_raceway_tree_spawns"),
    }


def lap_length(path: list) -> float:
    return sum(math.dist((path[i][0], path[i][2]), (path[(i + 1) % len(path)][0], path[(i + 1) % len(path)][2]))
               for i in range(len(path)))


# ---------------------------------------------------------------------------
# The rip

class Rip:
    """The OBJ: vertices, UVs, faces grouped by object, and each material's texture file."""

    def __init__(self, folder: Path):
        obj = next(folder.glob("*.obj"))
        self.folder = folder
        self.verts: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.groups: dict[str, list[tuple[list[int], list[int], str]]] = {}
        self.textures: dict[str, str] = {}
        mtl = obj.with_suffix(".mtl")
        material = None
        for line in mtl.read_text(encoding="utf-8", errors="replace").splitlines():
            tokens = line.split()
            if not tokens:
                continue
            if tokens[0] == "newmtl":
                material = tokens[1]
            elif tokens[0] == "map_Kd" and material:
                self.textures[material] = " ".join(tokens[1:])
        group = "(none)"
        material = ""
        for line in obj.read_text(encoding="utf-8", errors="replace").splitlines():
            tokens = line.split()
            if not tokens:
                continue
            if tokens[0] == "v":
                self.verts.append((float(tokens[1]), float(tokens[2]), float(tokens[3])))
            elif tokens[0] == "vt":
                self.uvs.append((float(tokens[1]), float(tokens[2])))
            elif tokens[0] in ("g", "o"):
                group = tokens[1].split(".")[-1]
                self.groups.setdefault(group, [])
            elif tokens[0] == "usemtl":
                material = tokens[1]
            elif tokens[0] == "f":
                corners = [c.split("/") for c in tokens[1:]]
                vi = [int(c[0]) - 1 for c in corners]
                ti = [int(c[1]) - 1 if len(c) > 1 and c[1] else -1 for c in corners]
                self.groups.setdefault(group, []).append((vi, ti, material))

    def bounds(self):
        xs = [v[0] for v in self.verts]
        zs = [v[2] for v in self.verts]
        return min(xs), max(xs), min(zs), max(zs)

    def group_with_texture(self, hash_prefix: str) -> str | None:
        for group, faces in self.groups.items():
            if any(self.textures.get(m, "").startswith(hash_prefix) for _, _, m in faces):
                return group
        return None


def unpack(rip: Path, scratch: Path) -> Path:
    """The folder holding the OBJ, unpacking a zip into [param scratch] first."""
    if rip.is_dir():
        return rip
    with zipfile.ZipFile(rip) as archive:
        archive.extractall(scratch)
    return next(scratch.rglob("*.obj")).parent


class RoadMask:
    """The road's footprint rasterised, so a point can be asked whether it is on the road."""

    def __init__(self, rip: Rip, groups: set[str], pixels_per_unit: float = 500.0):
        from PIL import Image, ImageDraw

        self.x0, x1, self.z0, z1 = rip.bounds()
        self.scale = pixels_per_unit
        self.width = int((x1 - self.x0) * self.scale) + 2
        self.height = int((z1 - self.z0) * self.scale) + 2
        image = Image.new("L", (self.width, self.height), 0)
        draw = ImageDraw.Draw(image)
        for group in groups:
            for vi, _, _ in rip.groups.get(group, []):
                draw.polygon([self.pixel(rip.verts[i][0], rip.verts[i][2]) for i in vi], fill=255)
        self.pixels = image.load()

    def pixel(self, x: float, z: float) -> tuple[float, float]:
        return ((x - self.x0) * self.scale, (z - self.z0) * self.scale)

    def on_road(self, x: float, z: float) -> bool:
        px, pz = self.pixel(x, z)
        if 0 <= px < self.width and 0 <= pz < self.height:
            return self.pixels[int(px), int(pz)] > 0
        return False


class Fit:
    """rip = A * game / k + t on the ground plane; y scales by 1 / k."""

    MAPS = [((1, 0), (0, 1)), ((1, 0), (0, -1)), ((-1, 0), (0, 1)), ((-1, 0), (0, -1)),
            ((0, 1), (1, 0)), ((0, 1), (-1, 0)), ((0, -1), (1, 0)), ((0, -1), (-1, 0))]

    def __init__(self, a, k: float, t):
        self.a = a
        self.k = k
        self.t = t

    def to_rip(self, gx: float, gz: float) -> tuple[float, float]:
        return (self.a[0][0] * gx + self.a[0][1] * gz) / self.k + self.t[0], \
               (self.a[1][0] * gx + self.a[1][1] * gz) / self.k + self.t[1]

    def to_game(self, rx: float, rz: float) -> tuple[float, float]:
        dx, dz = (rx - self.t[0]) * self.k, (rz - self.t[1]) * self.k
        # the maps are orthogonal, so the inverse is the transpose
        return self.a[0][0] * dx + self.a[1][0] * dz, self.a[0][1] * dx + self.a[1][1] * dz

    def rip_to_metres(self, v) -> tuple[float, float, float]:
        gx, gz = self.to_game(v[0], v[2])
        return gx * UNIT_METRES, v[1] * self.k * UNIT_METRES, gz * UNIT_METRES


def fit_path_to_rip(rip: Rip, path: list, mask: RoadMask, start_line: tuple[float, float]) -> Fit:
    """Lay the game's path over the rip's road: the orientation and scale that put the most of
    the path on the road, with the path's first point anchored on the rip's finish stripe."""
    samples = path[::3]
    best = None
    for a in Fit.MAPS:
        for k in range(600, 1400, 4):
            base = Fit(a, float(k), (0.0, 0.0))
            sx, sz = base.to_rip(samples[0][0], samples[0][2])
            anchor = (start_line[0] - sx, start_line[1] - sz)
            for dx in range(-6, 7):
                for dz in range(-6, 7):
                    fit = Fit(a, float(k), (anchor[0] + dx * 0.01, anchor[1] + dz * 0.01))
                    hits = sum(mask.on_road(*fit.to_rip(p[0], p[2])) for p in samples)
                    if best is None or hits > best[0]:
                        best = (hits, fit)
    hits, fit = best
    # refine: every point, finer steps
    for _ in range(2):
        for dk in (-3, -2, -1, 0, 1, 2, 3):
            for dx in range(-5, 6):
                for dz in range(-5, 6):
                    trial = Fit(fit.a, fit.k + dk, (fit.t[0] + dx * 0.002, fit.t[1] + dz * 0.002))
                    h = sum(mask.on_road(*trial.to_rip(p[0], p[2])) for p in path)
                    if h > hits or (h == hits and trial is not fit and False):
                        hits, fit = h, trial
    on = sum(mask.on_road(*fit.to_rip(p[0], p[2])) for p in path)
    print(f"  fit: map {fit.a}, {fit.k:.0f} game units per rip unit, {on} of {len(path)} path points on the road")
    return fit


def road_centre_line(rip: Rip, mask: RoadMask, fit: Fit, path: list, every: int = 3) -> list[tuple[float, float, float]]:
    """The middle of the road beside each path point, in game units, with the road width there.
    The game's path is the racing line and hugs the inside of bends, so the road is measured
    rather than extruded along it."""
    out = []
    n = len(path)
    for i in range(0, n, every):
        p = fit.to_rip(path[i][0], path[i][2])
        q = fit.to_rip(path[(i + 1) % n][0], path[(i + 1) % n][2])
        dx, dz = q[0] - p[0], q[1] - p[1]
        length = math.hypot(dx, dz)
        if length < 1e-9:
            continue
        nx, nz = -dz / length, dx / length
        reach = [0.0, 0.0]
        for side, sign in enumerate((1.0, -1.0)):
            step = 0.0
            while step < 0.3 and mask.on_road(p[0] + nx * sign * step, p[1] + nz * sign * step):
                step += 0.001
            reach[side] = step
        if reach[0] + reach[1] < 0.02:
            continue  # off the road entirely, which happens at the tunnel of a different course
        mid = (reach[0] - reach[1]) / 2.0
        cx, cz = p[0] + nx * mid, p[1] + nz * mid
        gx, gz = fit.to_game(cx, cz)
        out.append((gx, gz, (reach[0] + reach[1]) * fit.k))
    return out


def fence_segments(rip: Rip, fit: Fit) -> list[tuple[tuple[float, float, float], tuple[float, float, float]]]:
    """Each vertical fence quad's bottom edge, in metres, (a, b). Every quad in the rip is two
    triangles, so each is seen twice; the duplicates are dropped."""
    seen = set()
    segments = []
    for group in RIP_FENCES:
        for vi, _, _ in rip.groups.get(group, []):
            corners = [rip.verts[i] for i in vi]
            ys = [c[1] for c in corners]
            if max(ys) - min(ys) < 0.01:
                continue
            # the two corners that are furthest apart on the ground are the fence's ends; the
            # other triangle of the same quad gives the same ends, so it is dropped by (x, z)
            ends = max(((p, q) for p in corners for q in corners),
                       key=lambda pq: math.hypot(pq[0][0] - pq[1][0], pq[0][2] - pq[1][2]))
            floor = min(ys)
            a = fit.rip_to_metres((ends[0][0], floor, ends[0][2]))
            b = fit.rip_to_metres((ends[1][0], floor, ends[1][2]))
            if math.dist(a, b) < 0.5:
                continue
            key = tuple(sorted([(round(a[0], 1), round(a[2], 1)), (round(b[0], 1), round(b[2], 1))]))
            if key in seen:
                continue
            seen.add(key)
            segments.append((a, b))
    return segments


def group_box(rip: Rip, fit: Fit, group: str) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """Centre and size, in metres, of a group's bounding box."""
    points = [fit.rip_to_metres(rip.verts[i]) for vi, _, _ in rip.groups[group] for i in vi]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return tuple((lo[i] + hi[i]) / 2 for i in range(3)), tuple(hi[i] - lo[i] for i in range(3))


# ---------------------------------------------------------------------------
# The ripped course as a glTF

def write_model(rip: Rip, fit: Fit, out: Path) -> tuple[int, int]:
    primitives = []
    by_material: dict[str, list] = {}
    for faces in rip.groups.values():
        for face in faces:
            by_material.setdefault(face[2], []).append(face)
    for material, faces in by_material.items():
        texture = rip.textures.get(material, "")
        png = (rip.folder / texture).read_bytes() if texture and (rip.folder / texture).is_file() else None
        verts, uvs, tris = [], [], []
        for vi, ti, _ in faces:
            base = len(verts)
            for v, t in zip(vi, ti):
                verts.append(fit.rip_to_metres(rip.verts[v]))
                u, w = rip.uvs[t] if t >= 0 else (0.0, 0.0)
                uvs.append((u, 1.0 - w))  # OBJ counts v from the bottom, glTF from the top
            for i in range(1, len(vi) - 1):
                tris.append((base, base + i, base + i + 1))
        primitives.append({"verts": verts, "colors": [(1.0, 1.0, 1.0, 1.0)] * len(verts),
                           "uvs": uvs if png else None, "tris": tris, "png": png,
                           "name": Path(texture).stem if texture else material,
                           "mask": "tran" in texture})
    colonly = []
    for kind, groups in RIP_GROUPS.items():
        verts, tris = [], []
        for group in groups:
            for vi, _, _ in rip.groups.get(group, []):
                base = len(verts)
                verts.extend(fit.rip_to_metres(rip.verts[i]) for i in vi)
                for i in range(1, len(vi) - 1):
                    tris.append((base, base + i, base + i + 1))
        if tris:
            colonly.append((f"{kind}-colonly", verts, tris))
    out.parent.mkdir(parents=True, exist_ok=True)
    return glb.write_glb_textured(str(out), primitives, name=COURSE, colonly=colonly, wrap="repeat")


# ---------------------------------------------------------------------------
# The primitive scene

def metres(p) -> tuple[float, float, float]:
    return p[0] * UNIT_METRES, p[1] * UNIT_METRES, p[2] * UNIT_METRES


def fmt(value: float) -> str:
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def vec3(p) -> str:
    return f"Vector3({fmt(p[0])}, {fmt(p[1])}, {fmt(p[2])})"


def transform(origin, facing=(0.0, 0.0, 1.0)) -> str:
    """A Transform3D text whose +Z points along [param facing] on the ground: rows of the basis,
    which is how Godot writes it, then the origin."""
    dx, dz = facing[0], facing[2]
    length = math.hypot(dx, dz) or 1.0
    dx, dz = dx / length, dz / length
    rows = (dz, 0.0, dx, 0.0, 1.0, 0.0, -dx, 0.0, dz)
    return "Transform3D(" + ", ".join(fmt(v) for v in rows) + ", " + ", ".join(fmt(v) for v in origin) + ")"


def curve3d(points: list, closed: bool = True) -> str:
    flat = []
    for p in points:
        flat.extend([0, 0, 0, 0, 0, 0, fmt(p[0]), fmt(p[1]), fmt(p[2])])
    return ('{\n"points": PackedVector3Array(%s),\n"tilts": PackedFloat32Array(%s)\n}\npoint_count = %d\nclosed = %s'
            % (", ".join(str(v) for v in flat), ", ".join("0" for _ in points), len(points), "true" if closed else "false"))


def grid_slots(path: list) -> list[tuple[tuple[float, float, float], tuple[float, float, float]]]:
    """Eight (origin, facing) pairs behind the line: two staggered columns, as the game's grid."""
    start = metres(path[0])
    ahead = metres(path[1])
    dx, dz = ahead[0] - start[0], ahead[2] - start[2]
    length = math.hypot(dx, dz)
    dx, dz = dx / length, dz / length
    rx, rz = -dz, dx  # to the right of the direction of travel
    slots = []
    for i in range(8):
        row, column = i // 2, i % 2
        back = 12.0 + row * 4.5 + column * 2.0  # the line stays ahead of everyone through the lights
        side = 2.2 if column == 0 else -2.2
        origin = (start[0] - dx * back + rx * side, start[1] + 0.6, start[2] - dz * back + rz * side)
        slots.append((origin, (dx, 0.0, dz)))
    return slots


def write_scene(tables: dict, centre_line: list, fences: list, pipe, grandstand, out: Path, model_res: str) -> None:
    path = tables["path"]
    start = metres(path[0])
    ahead = metres(path[1])
    facing = (ahead[0] - start[0], 0.0, ahead[2] - start[2])
    lines = []
    ext = [f'[ext_resource type="Script" path="{RACING_LINE_SCRIPT}" id="1_course"]',
           f'[ext_resource type="PackedScene" path="{ITEM_BOX_SCENE}" id="2_box"]']
    sub = []
    sub.append('[sub_resource type="Curve3D" id="Curve3D_racing"]\n_data = %s\n' % curve3d([metres(p) for p in path]))
    road_points = [(gx * UNIT_METRES, 0.0, gz * UNIT_METRES) for gx, gz, _ in centre_line]
    sub.append('[sub_resource type="Curve3D" id="Curve3D_road"]\n_data = %s\n' % curve3d(road_points))
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_road"]\nalbedo_color = Color(0.3, 0.31, 0.34, 1)\nroughness = 0.92\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_grass"]\nalbedo_color = Color(0.33, 0.52, 0.24, 1)\nroughness = 1.0\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_wall"]\nalbedo_color = Color(0.82, 0.78, 0.66, 1)\nroughness = 0.9\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_line"]\nalbedo_color = Color(0.95, 0.95, 0.93, 1)\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_trunk"]\nalbedo_color = Color(0.42, 0.3, 0.18, 1)\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_leaves"]\nalbedo_color = Color(0.2, 0.45, 0.2, 1)\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_plant"]\nalbedo_color = Color(0.8, 0.15, 0.15, 1)\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_stand"]\nalbedo_color = Color(0.55, 0.42, 0.3, 1)\n')
    sub.append('[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_pipe"]\nalbedo_color = Color(0.2, 0.6, 0.25, 1)\nroughness = 0.6\n')
    sub.append('[sub_resource type="PlaneMesh" id="PlaneMesh_ground"]\nsize = Vector2(1200, 1200)\n')
    sub.append('[sub_resource type="BoxShape3D" id="BoxShape3D_ground"]\nsize = Vector3(1200, 1, 1200)\n')
    sub.append('[sub_resource type="BoxMesh" id="BoxMesh_line"]\nsize = Vector3(%s, 0.02, 1.2)\n' % fmt(ROAD_WIDTH_UNITS * UNIT_METRES))

    half = ROAD_WIDTH_UNITS * UNIT_METRES / 2.0
    nodes = []
    nodes.append(f'[node name="MarioRaceway" type="Node3D"]\nscript = ExtResource("1_course")\nmodel = "{model_res}"\n')
    nodes.append('[node name="RacingLine" type="Path3D" parent="."]\ncurve = SubResource("Curve3D_racing")\n')
    nodes.append('[node name="RoadLine" type="Path3D" parent="."]\ncurve = SubResource("Curve3D_road")\n')
    nodes.append('[node name="Road" type="CSGPolygon3D" parent="."]\nuse_collision = true\n'
                 f'polygon = PackedVector2Array({fmt(-half)}, -0.3, {fmt(half)}, -0.3, {fmt(half)}, 0, {fmt(-half)}, 0)\n'
                 'mode = 2\npath_node = NodePath("../RoadLine")\npath_interval_type = 0\npath_interval = 2.0\n'
                 'path_simplify_angle = 0.0\npath_rotation = 2\npath_local = true\npath_continuous_u = true\n'
                 'path_joined = true\nmaterial = SubResource("StandardMaterial3D_road")\n')
    nodes.append('[node name="Ground" type="StaticBody3D" parent="."]\n'
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.02, 0)\nmetadata/mk_surface = 8\n')
    nodes.append('[node name="Mesh" type="MeshInstance3D" parent="Ground"]\nmesh = SubResource("PlaneMesh_ground")\n'
                 'surface_material_override/0 = SubResource("StandardMaterial3D_grass")\n')
    nodes.append('[node name="Collision" type="CollisionShape3D" parent="Ground"]\n'
                 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)\nshape = SubResource("BoxShape3D_ground")\n')
    nodes.append('[node name="StartLine" type="MeshInstance3D" parent="."]\n'
                 f'transform = {transform((start[0], 0.011, start[2]), facing)}\nmesh = SubResource("BoxMesh_line")\n'
                 'surface_material_override/0 = SubResource("StandardMaterial3D_line")\n')
    nodes.append('[node name="Walls" type="Node3D" parent="."]\n')
    for i, (a, b) in enumerate(fences, 1):
        mid = ((a[0] + b[0]) / 2, min(a[1], b[1]) + WALL_HEIGHT_M / 2, (a[2] + b[2]) / 2)
        along = (b[0] - a[0], 0.0, b[2] - a[2])
        length = math.hypot(along[0], along[2])
        nodes.append(f'[node name="Wall{i}" type="CSGBox3D" parent="Walls"]\ntransform = {transform(mid, along)}\n'
                     f'use_collision = true\nsize = Vector3({fmt(WALL_THICKNESS_M)}, {fmt(WALL_HEIGHT_M)}, {fmt(length)})\n'
                     'material = SubResource("StandardMaterial3D_wall")\n')
    nodes.append('[node name="StartGrid" type="Node3D" parent="."]\n')
    for i, (origin, face) in enumerate(grid_slots(path), 1):
        nodes.append(f'[node name="Slot{i}" type="Marker3D" parent="StartGrid"]\ntransform = {transform(origin, face)}\n')
    nodes.append('[node name="ItemBoxes" type="Node3D" parent="."]\n')
    for i, box in enumerate(tables["boxes"], 1):
        p = metres(box)
        nodes.append(f'[node name="Box{i}" parent="ItemBoxes" instance=ExtResource("2_box")]\n'
                     f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(p[0])}, {fmt(p[1] + 1.2)}, {fmt(p[2])})\n')
    nodes.append('[node name="Props" type="Node3D" parent="."]\n')
    for i, tree in enumerate(tables["trees"], 1):
        p = metres(tree)
        nodes.append(f'[node name="Tree{i}" type="CSGCylinder3D" parent="Props"]\n'
                     f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(p[0])}, {fmt(p[1] + 1.5)}, {fmt(p[2])})\n'
                     'use_collision = true\nradius = 0.35\nheight = 3.0\nmaterial = SubResource("StandardMaterial3D_trunk")\n')
        nodes.append(f'[node name="Crown" type="CSGSphere3D" parent="Props/Tree{i}"]\n'
                     'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.6, 0)\nradius = 2.4\n'
                     'material = SubResource("StandardMaterial3D_leaves")\n')
    for i, plant in enumerate(tables["plants"], 1):
        p = metres(plant)
        nodes.append(f'[node name="PiranhaPlant{i}" type="CSGCylinder3D" parent="Props"]\n'
                     f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(p[0])}, {fmt(p[1] + 0.8)}, {fmt(p[2])})\n'
                     'use_collision = true\nradius = 0.6\nheight = 1.6\nmaterial = SubResource("StandardMaterial3D_plant")\n')
    centre, size = grandstand
    nodes.append('[node name="Grandstand" type="CSGBox3D" parent="Props"]\n'
                 f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {fmt(centre[0])}, {fmt(centre[1])}, {fmt(centre[2])})\n'
                 f'use_collision = true\nsize = {vec3(size)}\nmaterial = SubResource("StandardMaterial3D_stand")\n')
    # the pipe lies along the longer of its ground axes, hollow, with the road through the hole
    centre, size = pipe
    along_x = size[0] >= size[2]
    length = size[0] if along_x else size[2]
    radius = max(size[1], size[2] if along_x else size[0]) / 2.0
    # a cylinder stands on Y; the rows of a basis that lays it along X or along Z
    lay = "0, -1, 0, 1, 0, 0, 0, 0, 1" if along_x else "1, 0, 0, 0, 0, -1, 0, 1, 0"
    nodes.append('[node name="WarpPipe" type="CSGCombiner3D" parent="Props"]\n'
                 f'transform = Transform3D({lay}, {fmt(centre[0])}, {fmt(centre[1])}, {fmt(centre[2])})\nuse_collision = true\n')
    nodes.append(f'[node name="Outer" type="CSGCylinder3D" parent="Props/WarpPipe"]\nradius = {fmt(radius)}\nheight = {fmt(length)}\n'
                 'sides = 24\nmaterial = SubResource("StandardMaterial3D_pipe")\n')
    nodes.append(f'[node name="Bore" type="CSGCylinder3D" parent="Props/WarpPipe"]\noperation = 2\nradius = {fmt(radius - 0.8)}\n'
                 f'height = {fmt(length + 2.0)}\nsides = 24\n')

    steps = len(ext) + len(sub) + 1
    lines.append(f"[gd_scene load_steps={steps} format=3]\n")
    lines.extend(ext)
    lines.append("")
    lines.extend(sub)
    lines.extend(nodes)
    out.write_text("\n".join(lines), encoding="utf-8", newline="\n")


# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("rip", nargs="?", type=Path, help="the rip, a zip or the unpacked folder with Mario Raceway.obj")
    parser.add_argument("--rip", dest="rip_flag", type=Path, help="the same, as a flag")
    parser.add_argument("--scene", type=Path, default=SCENE, help=f"the primitive scene to write (default {SCENE})")
    parser.add_argument("--model", type=Path, default=MODEL, help=f"the glTF to write (default {MODEL})")
    parser.add_argument("--no-model", action="store_true", help="write only the primitive scene")
    args = parser.parse_args()
    rip_path = args.rip_flag or args.rip
    if rip_path is None or not rip_path.exists():
        print("give the rip: the zip from The Models Resource or its unpacked folder", file=sys.stderr)
        return 2
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("Pillow is not installed (python -m pip install pillow)", file=sys.stderr)
        return 2

    tables = course_tables(fetch_course_data())
    path = tables["path"]
    print(f"decompilation: {len(path)} path points, lap {lap_length(path):.0f} units = {lap_length(path) * UNIT_METRES:.0f} m, "
          f"{len(tables['boxes'])} item boxes, {len(tables['trees'])} trees, {len(tables['plants'])} piranha plants")

    with tempfile.TemporaryDirectory() as scratch:
        rip = Rip(unpack(rip_path, Path(scratch)))
        print(f"rip: {len(rip.verts)} vertices, {sum(len(f) for f in rip.groups.values())} faces, {len(rip.groups)} groups")
        start_group = rip.group_with_texture(START_LINE_TEXTURE)
        if start_group is None:
            print("the rip has no finish stripe to anchor the fit on", file=sys.stderr)
            return 1
        stripe = [rip.verts[i] for vi, _, _ in rip.groups[start_group] for i in vi]
        start_line = (sum(v[0] for v in stripe) / len(stripe), sum(v[2] for v in stripe) / len(stripe))
        mask = RoadMask(rip, RIP_GROUPS["road"])
        fit = fit_path_to_rip(rip, path, mask, start_line)
        centre = road_centre_line(rip, mask, fit, path)
        widths = sorted(w for _, _, w in centre)
        print(f"  road: {len(centre)} centre line points, width median {widths[len(widths) // 2]:.0f} units"
              f" = {widths[len(widths) // 2] * UNIT_METRES:.1f} m")
        fences = fence_segments(rip, fit)
        pipe = group_box(rip, fit, RIP_WARP_PIPE)
        grandstand = group_box(rip, fit, RIP_GRANDSTAND)
        print(f"  {len(fences)} fence segments, warp pipe {vec3(pipe[1])} m, grandstand {vec3(grandstand[1])} m")

        model_res = "res://" + args.model.resolve().relative_to(ROOT.resolve()).as_posix() \
            if args.model.resolve().is_relative_to(ROOT.resolve()) else args.model.as_posix()
        write_scene(tables, centre, fences, pipe, grandstand, args.scene, model_res)
        print(f"wrote {args.scene}")
        if not args.no_model:
            nv, nt = write_model(rip, fit, args.model)
            print(f"wrote {args.model}: {nv} vertices, {nt} triangles, collision for "
                  + ", ".join(RIP_GROUPS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
