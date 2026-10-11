"""Read the Twisted Metal 2 /TERRAIN tables: .GRP height zones and .RMP ramps.

Neither is a mesh. Every level's files are the same size (GRP 6,036 bytes,
RMP 6,300, PTS 3,360), so they are fixed-capacity tables the game loads as
structs and queries by (x, y): its ground height is a lookup, not a polygon
test, which is why a car never falls through a gap in the drawn level.

GRP  s32 pos[35][3] (x, y, z), s32 w[35], s32 h[35]: axis-aligned rectangles
     from (x, y) to (x + w, y + h) at height z; FREEWAY fills 20 points and
     19 sizes, the last point (-16000, -8000, 96) with (32000, 16000) being
     the whole level at the default height. Later words are unrelated state.
RMP  225 records of 28 bytes: u8 a, u8 b (flags), i16 -1, u16 w, u16 h,
     i16 dx, i16 dy (a direction in 1/4096), u16 z[4] (corner heights, only
     ever 0, 96, 192 or 240), i32 x, i32 y (corner). FREEWAY uses 124, all
     inside x +-133 m, y -93..68 m: the inner arena's patches, from 3 x 6 m
     kerbs to 37 x 49 m zones.
Units are the DMD's (1/64 m), Z up.

These are the game's own driving model, not the drawn level: checked against
the DMD with every corner order, the RMP heights agree with the drawn surface
at fewer than half the corners and the disagreement is not a constant
offset, and the GRP zones agree on 46 percent of the drawn faces inside them.
So they are read here for reference and are not emitted as collision; a
trimesh built from them would float above or below the drawn floor by up to
a few metres over most of the arena.
"""
import struct

RMP_RECORD = 28


def read_rmp(path):
    d = open(path, 'rb').read()
    out = []
    for i in range(0, len(d) - RMP_RECORD + 1, RMP_RECORD):
        a, b, _, w, h, dx, dy, z0, z1, z2, z3, x, y = struct.unpack_from('<BBhHHhhHHHHii', d, i)
        if w or h:
            out.append({'flags': (a, b), 'w': w, 'h': h, 'dir': (dx, dy),
                        'z': (z0, z1, z2, z3), 'x': x, 'y': y})
    return out


def read_grp(path):
    d = open(path, 'rb').read()
    ints = struct.unpack_from('<%di' % (len(d) // 4), d)
    pts = [ints[3 * i:3 * i + 3] for i in range(35)]
    w, h = ints[105 + 3:105 + 3 + 35], ints[143:143 + 35]
    out = []
    for i, (x, y, z) in enumerate(pts):
        if (x or y or z) and (w[i] or h[i]):
            out.append({'x': x, 'y': y, 'z': z, 'w': w[i], 'h': h[i]})
    return out


def ramp_quads(ramps, order=(0, 1, 2, 3)):
    """Each ramp as four (x, y, z) corners: (x,y), (x+w,y), (x,y+h), (x+w,y+h)
    with the four heights dealt out in [param order]."""
    quads = []
    for r in ramps:
        x, y, w, h = r['x'], r['y'], r['w'], r['h']
        z = [r['z'][k] for k in order]
        quads.append([(x, y, z[0]), (x + w, y, z[1]), (x, y + h, z[2]), (x + w, y + h, z[3])])
    return quads


def to_godot(quads, scale=1.0 / 64.0):
    """Quads in game units, Z up, to Godot metres, Y up: (verts, tris) with
    PlayStation strip order (0 1 / 2 3)."""
    verts, tris = [], []
    for q in quads:
        base = len(verts)
        for x, y, z in q:
            verts.append((x * scale, z * scale, y * scale))
        tris += [(base, base + 1, base + 2), (base + 1, base + 3, base + 2)]
    return verts, tris
