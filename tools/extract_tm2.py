"""Build the Twisted Metal 2 level assets from your own copy of the game.

The Twisted Metal 2 data is Sony's and is not redistributed with this
repository, so the assets this writes are git-ignored. Point this at the disc
image and it produces the level geometry the demo scene expects.

    python tools/extract_tm2.py "Twisted Metal 2 (USA) (Track 01).bin"
    python tools/extract_tm2.py tm2.iso --level ROOF --out addons/gta/tw/assets

The disc holds twelve levels under /LEVELDB as .DPC geometry databases.
ROOF is Los Angeles, the "Quake Zone Rumble" rooftop arena; SROOF is the
reduced split-screen copy of it, as HKONG is of HONGKONG.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tm2'))

import dpc      # noqa: E402
import glb      # noqa: E402
import iso      # noqa: E402
import pts      # noqa: E402

# One game unit is 1/64 m. Derived from the disc rather than read out of it:
# at this scale the drivable quads are about 6 m across, the AI waypoints sit
# about 25 m apart and the Los Angeles play area is 252 x 166 m, which are all
# sane together. The game's own constant has not been found, so treat this as
# the one tuned number in the pipeline.
SCALE = 1.0 / 64.0

# Twisted Metal draws a painted skyline as a handful of enormous quads sitting
# far outside the arena. They swamp the level in an engine that has its own sky,
# so any face bigger than this many square metres is treated as backdrop and
# left out. The real drivable quads are about 6 m across.
BACKDROP_AREA = 400.0

LEVELS = {
    'ROOF': 'los_angeles',
    'SROOF': 'los_angeles_split',
    'PARIS': 'paris',
    'HONGKONG': 'hong_kong',
    'GLACIER': 'antarctica',
    'DISH': 'antarctica_dish',
    'SWAMP': 'amazonia',
    'ISLANDS': 'islands',
    'FREEWAY': 'freeway',
    'BURB': 'suburbs',
    'DEN': 'denmark',
}


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


def build_level(image, key, out_dir):
    name = LEVELS.get(key, key.lower())
    disc = iso.Iso(image)
    work = os.path.join(out_dir, '.src')
    os.makedirs(work, exist_ok=True)

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
    # the -col suffix is Godot's import hint: the importer gives the mesh a
    # StaticBody3D with a trimesh shape, so the level collides with no code
    glb.write_glb(glb_path, verts, colors, tris, name=name + '-col')
    print('%s: %d meshes, %d verts, %d tris -> %s'
          % (key, len(db.meshes), len(verts), len(tris), glb_path))
    if dropped:
        print('   %d backdrop faces left out' % dropped)
    if db.skipped or db.dropped:
        print('   %d mesh blocks and %d stray faces rejected as unparsed'
              % (db.skipped, db.dropped))

    # the AI driving waypoints that live beside the level
    terrain = {'ROOF': 'ROOF', 'SROOF': 'SROOF', 'PARIS': 'PARIS', 'HONGKONG': 'HKONG',
               'GLACIER': 'ICE', 'DISH': 'DISH', 'SWAMP': 'SWAMP', 'FREEWAY': 'FWY',
               'BURB': 'CYB', 'DEN': 'DEN'}.get(key)
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
    ap.add_argument('image', help='Twisted Metal 2 disc image (.iso or MODE1/2352 .bin)')
    ap.add_argument('--level', default='ROOF', help='level key on the disc (default ROOF)')
    ap.add_argument('--all', action='store_true', help='build every level')
    ap.add_argument('--out', default=os.path.join('addons', 'gta', 'assets', 'twistedmetal2'))
    a = ap.parse_args()
    keys = sorted(LEVELS) if a.all else [a.level.upper()]
    for k in keys:
        build_level(a.image, k, a.out)


if __name__ == '__main__':
    main()
