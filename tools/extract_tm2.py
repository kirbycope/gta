"""Build the Twisted Metal 2 level assets from your own copy of the game.

The Twisted Metal 2 data is Sony's and is not redistributed with this
repository, so the assets this writes are git-ignored. Point this at a disc
image and it produces the level geometry the demo scene expects.

    python tools/extract_tm2.py "Twisted Metal 2 (USA) (SCUS-94306).iso" --level FREEWAY
    python tools/extract_tm2.py tm2.iso --level ROOF --out addons/gta/tw/assets

Two discs are understood, told apart by their tree:

    PlayStation   /DMD/<LEVEL>.DMD geometry, /TMS/<LEVEL>.TMS textures and
                  /TERRAIN/<abbr>.PTS AI waypoints. Levels come out textured.
    PC            /LEVELDB/<LEVEL>.DPC, the same node tree with a different
                  magic; no texture bank has been decoded for it, so levels
                  come out with vertex colours only.

FREEWAY is Los Angeles (Quake Zone Rumble), ROOF New York (The Big Leap),
SROOF the split-screen Los Angeles roof tops and BURB Cyburbia, after the
game's own level table.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tm2'))

import dmd      # noqa: E402
import dpc      # noqa: E402
import glb      # noqa: E402
import iso      # noqa: E402
import pts      # noqa: E402
import tms      # noqa: E402

# One game unit is 1/64 m. Derived from the disc rather than read out of it:
# at this scale the drivable quads are about 6 m across, the AI waypoints sit
# about 25 m apart and the Los Angeles play area is 252 x 166 m, which are all
# sane together. The game's own constant has not been found, so treat this as
# the one tuned number in the pipeline.
SCALE = 1.0 / 64.0

# Twisted Metal draws a painted skyline as a handful of enormous quads sitting
# far outside the arena. They swamp the level in an engine that has its own sky,
# so they are left out: an untextured face bigger than BACKDROP_AREA square
# metres (the sky dome is vertex coloured), or a textured one bigger than
# BACKDROP_BILLBOARD_AREA that also stands BACKDROP_BILLBOARD_HEIGHT metres tall
# (the skyscraper billboards round New York). Big flat textured faces are the
# streets: Los Angeles's slabs run to 2,900 square metres, and dropping those
# by area alone took the floor out from under the cars.
BACKDROP_AREA = 400.0
BACKDROP_BILLBOARD_AREA = 2000.0
BACKDROP_BILLBOARD_HEIGHT = 20.0

# A mesh no node of the tree reaches is placed by game code, not by the file.
# The big ones are level pieces already in world space and are kept; a small
# one sitting at the origin is a prop (pickup, debris, an animation state)
# with nowhere to go, and would only pile up at the arena centre.
LOOSE_RADIUS = 500      # game units from the origin
LOOSE_EXTENT = 1200     # game units across

# A face with a corner on its mesh's own origin and another tens of metres
# away is a billboard the game stretches from code (the fire pit's flames in
# Los Angeles: ten single-quad meshes, 82 m slivers); without that code it is
# a sliver across the arena, so it is left out.
ANCHOR_RADIUS = 64      # game units: a vertex this close to the origin anchors it
ANCHOR_REACH = 1200     # game units: and another this far away makes it a sliver

# Collision skirts. The plateau slabs stop at their edge with no side face, so
# a car that drops off a kerb gap lands under the slab. Every edge of a flat
# face above SKIRT_FLOOR_MIN that no other face shares gets a vertical quad
# straight down to SKIRT_BOTTOM, emitted as a collision-only node. Where a
# slope face shares the edge there is no skirt.
SKIRT_FLAT = 0.5        # m: a face spanning less than this vertically is flat
SKIRT_FLOOR_MIN = 1.0   # m: only flat faces above this get skirts
SKIRT_BOTTOM = -4.0     # m: the demo's invisible floor
SKIRT_SNAP = 0.05       # m: two vertices this close are the same edge end
SKIRT_PROBE = 0.75      # m: look this far outward from an unshared edge
SKIRT_DROP = 1.0        # m: ground found within this far below the edge is no cliff
SKIRT_RISE = 0.5        # m: or this far above it

# Collision is a policy of its own, separate from the drawing: a car stands on
# or runs into a face that is mostly horizontal (ground, kerbs, ramps, slopes)
# over COLLISION_FLOOR_AREA, or mostly vertical (walls, tunnel sides, the
# sign's letters) over COLLISION_WALL_AREA. Slivers and the small code-placed
# meshes (pickups, signs, debris, which the game never makes solid) are left
# out, so a chassis box never wedges inside a prop that Godot's trimesh would
# never push it back out of.
COLLISION_UP = 0.3            # |normal.y| above this is a floor-like face
COLLISION_FLOOR_AREA = 1.0    # m2
COLLISION_WALL_AREA = 8.0     # m2
COLLISION_SLIVER = 12.0       # longest edge over shortest edge
COLLISION_PROP_EXTENT = 6.0   # m: an out-of-tree mesh smaller than this is a prop

LEVELS = {
    'FREEWAY': 'los_angeles',
    'ROOF': 'new_york',
    'SROOF': 'los_angeles_rooftops',
    'BURB': 'cyburbia',
    'PARIS': 'paris',
    'HKONG': 'hong_kong',
    'HONGKONG': 'hong_kong',
    'GLACIER': 'antarctica',
    'DISH': 'antarctica_dish',
    'SWAMP': 'amazonia',
    'ISLANDS': 'islands',
    'DEN': 'denmark',
}

# The /TERRAIN folder names each level by an abbreviation.
TERRAIN = {'ROOF': 'ROOF', 'SROOF': 'SROOF', 'PARIS': 'PARIS', 'HONGKONG': 'HKONG',
           'HKONG': 'HKONG', 'GLACIER': 'ICE', 'DISH': 'DISH', 'SWAMP': 'SWAMP',
           'FREEWAY': 'FWY', 'BURB': 'CYB', 'DEN': 'DEN', 'ISLANDS': 'LAVA'}


def _face_area(verts, idx):
    """Area of a polygon given as indices into [param verts]."""
    total = 0.0
    a = verts[idx[0]]
    for k in range(1, len(idx) - 1):
        b, c = verts[idx[k]], verts[idx[k + 1]]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        w = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * w[2] - u[2] * w[1],
             u[2] * w[0] - u[0] * w[2],
             u[0] * w[1] - u[1] * w[0])
        total += 0.5 * (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5
    return total


def _triangles(n, base):
    # PlayStation quads are in strip order (0 1 / 2 3), not round the ring
    if n == 4:
        return [(base, base + 1, base + 2), (base + 1, base + 3, base + 2)]
    return [(base, base + 1, base + 2)]


def _is_backdrop(verts, idx, textured):
    """See BACKDROP_AREA: the painted skyline, not the arena."""
    area = _face_area(verts, idx)
    if not textured:
        return area > BACKDROP_AREA
    ys = [verts[i][1] for i in idx]
    return area > BACKDROP_BILLBOARD_AREA and max(ys) - min(ys) > BACKDROP_BILLBOARD_HEIGHT


def _loose(m):
    """True for an unplaced prop: see LOOSE_RADIUS."""
    if m.in_tree:
        return False
    used = sorted({i for f in m.faces for i in f.idx})
    vs = [m.verts[i] for i in used]
    c = [sum(v[k] for v in vs) / len(vs) for k in range(3)]
    ext = max(max(v[k] for v in vs) - min(v[k] for v in vs) for k in range(3))
    return (c[0] ** 2 + c[1] ** 2 + c[2] ** 2) ** 0.5 < LOOSE_RADIUS and ext < LOOSE_EXTENT


def _anchored_sliver(m):
    """True for a code-stretched billboard: see ANCHOR_RADIUS."""
    if m.in_tree:
        return False
    for f in m.faces:
        vs = [m.verts[i] for i in f.idx]
        near = any((v[0] ** 2 + v[1] ** 2 + v[2] ** 2) ** 0.5 < ANCHOR_RADIUS for v in vs)
        far = any((v[0] ** 2 + v[1] ** 2 + v[2] ** 2) ** 0.5 > ANCHOR_REACH for v in vs)
        if near and far:
            return True
    return False


def _face_normal_y(verts, idx):
    a, b, c = verts[idx[0]], verts[idx[1]], verts[idx[2]]
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    w = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
    length = (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5
    return abs(n[1]) / length if length else 0.0


def _ring(idx):
    # quads are in strip order, so the ring is 0 1 3 2
    return [idx[0], idx[1], idx[3], idx[2]] if len(idx) == 4 else list(idx)


def _collision(verts, faces):
    """The faces a car stands on or runs into: see COLLISION_UP. [param faces]
    is [(indices, Face, Mesh)] in metres, Y up. Returns (verts, tris, counts)."""
    extent = {}
    for idx, f, m in faces:
        if m.in_tree or id(m) in extent:
            continue
        used = sorted({i for fc in m.faces for i in fc.idx})
        vs = [m.verts[i] for i in used]
        extent[id(m)] = max(max(v[k] for v in vs) - min(v[k] for v in vs) for k in range(3)) * SCALE
    counts = {'floor': 0, 'wall': 0, 'small floor': 0, 'small wall': 0, 'sliver': 0, 'prop': 0}
    out_v, out_t = [], []
    for idx, f, m in faces:
        if not m.in_tree and extent[id(m)] < COLLISION_PROP_EXTENT:
            counts['prop'] += 1
            continue
        ring = _ring(idx)
        edges = []
        for k in range(len(ring)):
            a, b = verts[ring[k]], verts[ring[(k + 1) % len(ring)]]
            edges.append(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5)
        if min(edges) <= 0 or max(edges) / min(edges) > COLLISION_SLIVER:
            counts['sliver'] += 1
            continue
        area = _face_area(verts, idx)
        if _face_normal_y(verts, idx) > COLLISION_UP:
            if area <= COLLISION_FLOOR_AREA:
                counts['small floor'] += 1
                continue
            counts['floor'] += 1
        else:
            if area <= COLLISION_WALL_AREA:
                counts['small wall'] += 1
                continue
            counts['wall'] += 1
        base = len(out_v)
        out_v += [verts[i] for i in idx]
        out_t += _triangles(len(idx), base)
    return out_v, out_t, counts


def _skirts(verts, faces):
    """Vertical collision quads under the unshared edges of raised flat
    faces that are genuine drops: see SKIRT_FLAT. [param faces] is
    [(indices, Face)] in metres, Y up. Returns (verts, tris, unshared edge
    count, skirt count)."""
    def snap(v):
        return tuple(int(round(c / SKIRT_SNAP)) for c in v)

    def edges(idx):
        ring = _ring(idx)
        return [(ring[k], ring[(k + 1) % len(ring)]) for k in range(len(ring))]

    count = {}
    for idx, f in faces:
        for a, b in edges(idx):
            key = tuple(sorted((snap(verts[a]), snap(verts[b]))))
            count[key] = count.get(key, 0) + 1

    # every kept face in a 4 m grid over the ground plane, for the drop test
    cell = 4.0
    grid = {}
    tris = []
    for idx, f in faces:
        ring = _ring(idx)
        for t in ([ring[0], ring[1], ring[2]], [ring[0], ring[2], ring[3]]) if len(ring) == 4 else ([ring],):
            t = t if len(ring) == 4 else ring
            pts = [verts[i] for i in t]
            tris.append(pts)
            xs = [q[0] for q in pts]
            zs = [q[2] for q in pts]
            for cx in range(int(min(xs) // cell), int(max(xs) // cell) + 1):
                for cz in range(int(min(zs) // cell), int(max(zs) // cell) + 1):
                    grid.setdefault((cx, cz), []).append(len(tris) - 1)

    def height_at(tri, x, z):
        """Height of the triangle's plane at (x, z) if the point is inside it in xz."""
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
        d = (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
        if abs(d) < 1e-9:
            return None
        u = ((x - ax) * (cz - az) - (z - az) * (cx - ax)) / d
        v = ((bx - ax) * (z - az) - (bz - az) * (x - ax)) / d
        if u < -1e-6 or v < -1e-6 or u + v > 1 + 1e-6:
            return None
        return ay + u * (by - ay) + v * (cy - ay)

    def ground_beyond(x, z, y):
        for ti in grid.get((int(x // cell), int(z // cell)), ()):
            h = height_at(tris[ti], x, z)
            if h is not None and y - SKIRT_DROP <= h <= y + SKIRT_RISE:
                return True
        return False

    out_v, out_t, unshared, kept = [], [], 0, 0
    for idx, f in faces:
        ys = [verts[i][1] for i in idx]
        if max(ys) - min(ys) >= SKIRT_FLAT or min(ys) <= SKIRT_FLOOR_MIN:
            continue
        cen = [sum(verts[i][k] for i in idx) / len(idx) for k in range(3)]
        for a, b in edges(idx):
            key = tuple(sorted((snap(verts[a]), snap(verts[b]))))
            if count[key] != 1:
                continue
            unshared += 1
            pa, pb = verts[a], verts[b]
            mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2)
            dx, dz = pb[0] - pa[0], pb[2] - pa[2]
            length = (dx * dx + dz * dz) ** 0.5
            if length < 1e-6:
                continue
            px, pz = -dz / length, dx / length
            if px * (mid[0] - cen[0]) + pz * (mid[2] - cen[2]) < 0:
                px, pz = -px, -pz
            qx, qz = mid[0] + SKIRT_PROBE * px, mid[2] + SKIRT_PROBE * pz
            if ground_beyond(qx, qz, mid[1]):
                continue        # ground carries on past the edge: no cliff
            kept += 1
            base = len(out_v)
            out_v += [pa, pb, (pa[0], SKIRT_BOTTOM, pa[2]), (pb[0], SKIRT_BOTTOM, pb[2])]
            out_t += [(base, base + 1, base + 2), (base + 1, base + 3, base + 2)]
    return out_v, out_t, unshared, kept


def build_ps1(disc, key, name, work, out_dir, pages_dir=None):
    dmd_path = os.path.join(work, key + '.DMD')
    tms_path = os.path.join(work, key + '.TMS')
    disc.extract('/DMD/%s.DMD' % key, dmd_path)
    disc.extract('/TMS/%s.TMS' % key, tms_path)
    db = dmd.Dmd(dmd_path)
    bank = tms.Tms(tms_path)

    loose = {id(m) for m in db.meshes if _loose(m)}
    loose_faces = sum(len(m.faces) for m in db.meshes if id(m) in loose)
    slivers = {id(m) for m in db.meshes if _anchored_sliver(m)}
    loose |= slivers
    verts_in, faces_in = db.merged(scale=SCALE, translate=True)

    # bucket the faces by material: one per (tpage, clut, window), one untextured
    buckets = {}
    kept = []
    dropped = 0
    for idx, f, m in faces_in:
        if id(m) in loose:
            continue
        if _is_backdrop(verts_in, idx, f.textured):
            dropped += 1        # the painted skyline, not part of the arena
            continue
        k = (f.tpage, f.clut, f.window) if f.textured else None
        buckets.setdefault(k, []).append((idx, f))
        kept.append((idx, f, m))

    # extraction policy, not the game's data: what a car collides with, and
    # skirts under the open edges of the raised slabs
    col_v, col_t, col_counts = _collision(verts_in, kept)
    skirt_v, skirt_t, skirt_edges, skirt_kept = _skirts(verts_in, [fc for b in buckets.values() for fc in b])

    primitives = []
    for k in sorted(buckets, key=lambda x: (0, 0, 0, 0) if x is None else (1, x[0], x[1], x[2] or 0)):
        faces = buckets[k]
        verts, colors, uvs, tris = [], [], [], []
        png = None
        mask = False
        if k is None:
            for idx, f in faces:
                base = len(verts)
                for i, rgb in zip(idx, f.colors):
                    verts.append(verts_in[i])
                    colors.append((rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0))
                tris += _triangles(len(idx), base)
            mat_name = 'flat'
            uvs = None
        else:
            tpage, clut, window = k
            page = bank.page(tpage, clut, window)
            u0 = min(u for _, f in faces for u, v in f.uvs)
            u1 = max(u for _, f in faces for u, v in f.uvs)
            v0 = min(v for _, f in faces for u, v in f.uvs)
            v1 = max(v for _, f in faces for u, v in f.uvs)
            w, h = u1 - u0 + 1, v1 - v0 + 1
            png = tms.png(page, u0, v0, w, h)
            mask = any(page[y][x][3] == 0 for y in range(v0, v1 + 1) for x in range(u0, u1 + 1))
            for idx, f in faces:
                base = len(verts)
                fu1 = max(u for u, v in f.uvs)
                fu0 = min(u for u, v in f.uvs)
                fv1 = max(v for u, v in f.uvs)
                fv0 = min(v for u, v in f.uvs)
                for i, rgb, (u, v) in zip(idx, f.colors, f.uvs):
                    verts.append(verts_in[i])
                    # 0x80 is neutral on a textured face
                    colors.append((min(rgb[0] / 128.0, 1.0), min(rgb[1] / 128.0, 1.0),
                                   min(rgb[2] / 128.0, 1.0), 1.0))
                    # texel coordinates are inclusive: a face from u 2 to 8
                    # covers texels 2..8, so the far edge lands past texel 8
                    uu = u - u0 + (1 if u == fu1 and fu1 != fu0 else 0)
                    vv = v - v0 + (1 if v == fv1 and fv1 != fv0 else 0)
                    uvs.append((uu / w, vv / h))
                tris += _triangles(len(idx), base)
            mat_name = 'tp%04x_cl%04x' % (tpage, clut) + ('_w%08x' % window if window else '')
            if pages_dir:
                os.makedirs(pages_dir, exist_ok=True)
                with open(os.path.join(pages_dir, '%s_%s.png' % (name, mat_name)), 'wb') as f:
                    f.write(tms.png(page))
        primitives.append({'verts': verts, 'colors': colors, 'uvs': uvs, 'tris': tris,
                           'png': png, 'mask': mask, 'name': mat_name})

    os.makedirs(out_dir, exist_ok=True)
    glb_path = os.path.join(out_dir, name + '.glb')
    # the drawn chunks are visible only; the -colonly nodes make StaticBody3Ds
    # with trimesh shapes and no visible mesh
    nv, nt = glb.write_glb_textured(glb_path, primitives, name=name,
                                    colonly=[(name + '_collision-colonly', col_v, col_t),
                                             (name + '_skirts-colonly', skirt_v, skirt_t)])
    print('%s: %d meshes (%d in the tree), %d materials, %d verts, %d tris -> %s'
          % (key, len(db.meshes), sum(1 for m in db.meshes if m.in_tree),
             len(primitives), nv, nt, glb_path))
    if dropped:
        print('   %d backdrop faces left out' % dropped)
    if loose:
        print('   %d unplaced props (%d faces) and %d code-stretched billboards left out'
              % (len(loose) - len(slivers), loose_faces, len(slivers)))
    print('   collision: %d floor and %d wall faces kept; %d small floor, %d small wall, '
          '%d sliver, %d prop faces left out -> %s_collision-colonly'
          % (col_counts['floor'], col_counts['wall'], col_counts['small floor'],
             col_counts['small wall'], col_counts['sliver'], col_counts['prop'], name))
    print('   %d collision skirt quads at genuine drops, of %d unshared edges -> %s_skirts-colonly'
          % (skirt_kept, skirt_edges, name))
    if db.skipped or db.dropped:
        print('   %d mesh blocks and %d stray faces rejected as unparsed'
              % (db.skipped, db.dropped))
    if db.unknown_ops:
        print('   unknown node opcodes: %s' % db.unknown_ops)


def build_pc(disc, key, name, work, out_dir):
    dpc_path = os.path.join(work, key + '.DPC')
    disc.extract('/LEVELDB/%s.DPC' % key, dpc_path)

    db = dpc.Dpc(dpc_path)
    verts_in, faces_in = db.merged(scale=SCALE)

    verts, colors, tris, dropped = [], [], [], 0
    for idx, uvs, rgb, code in faces_in:
        if _face_area(verts_in, idx) > BACKDROP_AREA:
            dropped += 1        # the painted skyline, not part of the arena
            continue
        base = len(verts)
        for i in idx:
            verts.append(verts_in[i])
            colors.append((rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0))
        # the indices run round the polygon, so a quad fans from its first
        # corner; pairing them the PlayStation way turns the level inside out
        if len(idx) == 4:
            tris += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
        else:
            tris.append((base, base + 1, base + 2))

    os.makedirs(out_dir, exist_ok=True)
    glb_path = os.path.join(out_dir, name + '.glb')
    glb.write_glb(glb_path, verts, colors, tris, name=name + '-col')
    print('%s: %d meshes, %d verts, %d tris -> %s'
          % (key, len(db.meshes), len(verts), len(tris), glb_path))
    if dropped:
        print('   %d backdrop faces left out' % dropped)
    if db.skipped or db.dropped:
        print('   %d mesh blocks and %d stray faces rejected as unparsed'
              % (db.skipped, db.dropped))


def build_level(image, key, out_dir, pages_dir=None):
    name = LEVELS.get(key, key.lower())
    disc = iso.Iso(image)
    work = os.path.join(out_dir, '.src')
    os.makedirs(work, exist_ok=True)

    if '/DMD/%s.DMD' % key in disc.files:
        build_ps1(disc, key, name, work, out_dir, pages_dir)
    elif '/LEVELDB/%s.DPC' % key in disc.files:
        build_pc(disc, key, name, work, out_dir)
    else:
        raise SystemExit('%s: no /DMD/%s.DMD or /LEVELDB/%s.DPC on this disc' % (image, key, key))

    # the AI driving waypoints that live beside the level
    terrain = TERRAIN.get(key)
    if terrain and '/TERRAIN/%s.PTS' % terrain in disc.files:
        p = os.path.join(work, terrain + '.PTS')
        disc.extract('/TERRAIN/%s.PTS' % terrain, p)
        points = pts.read_points(p, SCALE)
        res = os.path.join(out_dir, name + '_waypoints.tres')
        header = (
            '[gd_resource type="Resource" script_class="TwWaypoints" '
            'load_steps=2 format=3]\n\n'
            '[ext_resource type="Script" '
            'path="res://addons/gta/tw/scripts/tw_waypoints.gd" id="1_wp"]\n\n'
            '[resource]\n'
            'script = ExtResource("1_wp")\n'
        )
        body = 'points = PackedVector3Array(%s)\n' % ', '.join(
            '%.3f, %.3f, %.3f' % q['pos'] for q in points)
        with open(res, 'w') as f:
            f.write(header)
            f.write(body)
        print('%s: %d AI waypoints -> %s' % (key, len(points), res))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('image', help='Twisted Metal 2 disc image (.iso, or a MODE1/MODE2 2352-byte .bin)')
    ap.add_argument('--level', default='ROOF', help='level key on the disc (default ROOF)')
    ap.add_argument('--all', action='store_true', help='build every level the disc has')
    ap.add_argument('--out', default=os.path.join('addons', 'gta', 'tw', 'assets'))
    ap.add_argument('--pages', help='also write every decoded texture page as PNG into this folder')
    a = ap.parse_args()
    if a.all:
        disc = iso.Iso(a.image)
        keys = sorted(k for k in LEVELS
                      if '/DMD/%s.DMD' % k in disc.files or '/LEVELDB/%s.DPC' % k in disc.files)
    else:
        keys = [a.level.upper()]
    for k in keys:
        build_level(a.image, k, a.out, a.pages)


if __name__ == '__main__':
    main()
