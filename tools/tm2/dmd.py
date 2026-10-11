"""Read the .DMD model databases from the Twisted Metal 2 PlayStation disc.

Reverse engineered from the retail data, checked against aybe's Twisted Metal 1
viewer (github.com/aybe/Twisted) and the TM1 decompilation's DbNode structs
(github.com/abelbriggs1/tm1_decomp, include/tm1/db.h); TM1 and TM2 share the
SingleTrac engine. The PC release's .DPC (see dpc.py) is this same structure
with a different magic.

File
    +0x00 "DXSP", u32 version 0x43, u32 unix stamp, u32 BASE (0x80019c40)
    +0x10 u32 3, u32 pRootTable
    pRootTable: u32 nRoots, u32 root[nRoots]
    Every pointer is absolute against BASE: fileOffset = pointer - BASE.

Hierarchy node
    byte 0 is the opcode that selects the layout, byte 1 a sub-kind, u16 at +2
    the "kind" the game's interactive scan keys on. Children are pointers.
        op 0   leaf. sub-kind 0xFF is a mesh (below); 0x10 is a sprite/other
        op 1   u8 nChild at +0x14, children at +0x18
        op 2   s32 nChild at +0x10, children at +0x14 point at 12-byte
               sub-nodes whose +8 is the real child
        op 3   u8 nChild at +0x0B, children at +0x20 (TM1 had them at +0x10)
        op 4   s32 t[3] at +0x04 translation, u8 nChild at +0x12, children +0x14
        op 5   MATRIX at +0x04 (s16 m[9], pad, s32 t[3] at +0x18),
               u8 nChild at +0x26, children at +0x28
        op 6/7/8  effect, light and the like: no children (68 / 52 / 84 bytes)
        op 9   u8 nChild at +0x06, children at +0x08
        op 11  two children at +0x0C and +0x10
        op 12  (TM2 only) u16 nChild at +0x06, children at +0x08: a plain list

Mesh node (op 0, sub-kind 0xFF)
    +0x04 u32  pVerts     this mesh's slice of the shared vertex pool
    +0x08 u32  pNormals
    +0x0c u32  pPolys     node address + 0x2c
    +0x10 u16  nPolys
    +0x1c i32  centre x, y, z
    +0x28 u32  radius
    +0x2c      the polygon records

Vertex
    PSX SVECTOR: i16 x, y, z and two bytes of padding. Z is up in this game.

Polygon record (a compressed PSX GPU primitive; the screen x,y pairs are left out)
    +0  u8  low nibble 3 or 4 = textured tri/quad, 0 = untextured;
            bit 0x80 = a texture window word follows the UVs
    +1  u8  colours carried: 1 flat, 3 or 4 gouraud
    +2  u8  record size in dwords
    +3  u8  size of the finished GPU primitive in words
    +4  u16 vertexIndex[4], relative to pVerts (a triangle leaves the 4th 0)
    +12 u32 unknown (constant per family, not a pointer)
    +16 u8 r, g, b, code  x colours   code: 0x20 F3 0x28 F4 0x24 FT3 0x2c FT4
                                           0x30 G3 0x38 G4 0x34 GT3 0x3c GT4
            bit 3 of the code = quad, bit 4 gouraud, bit 2 textured, bit 1
            semi-transparent, 0x80 is neutral for a textured face
    then, textured only, per vertex: u8 u, u8 v, u16 (clut on the 1st,
            tpage on the 2nd, 0 after) exactly as in POLY_FT4
    then, bit 0x80 only: u32 texture window (GPU E2 command)
    then, when 8 bytes remain: u16 normalIndex[4]
"""
import struct

BASE = 0x80019c40
MESH_SIG = bytes([0x00, 0xFF, 0x00, 0x00])


class Face:
    __slots__ = ('idx', 'colors', 'code', 'uvs', 'clut', 'tpage', 'window')

    def __init__(self, idx, colors, code, uvs, clut, tpage, window):
        self.idx = idx            # vertex indices relative to the mesh's pVerts
        self.colors = colors      # one (r, g, b) per vertex
        self.code = code          # PSX GPU command byte
        self.uvs = uvs            # [(u, v)] texels in the page, or None
        self.clut = clut          # PSX clut word, or None
        self.tpage = tpage        # PSX tpage word, or None
        self.window = window      # PSX texture window word, or None

    @property
    def textured(self):
        return self.uvs is not None


class Mesh:
    __slots__ = ('off', 'vbase', 'verts', 'faces', 'loc', 'rot', 'in_tree', 'centre')

    def __init__(self, off, vbase, verts, faces, loc, rot, in_tree, centre):
        self.off = off
        self.vbase = vbase        # file offset of the vertex slice
        self.verts = verts        # [(x, y, z)] game units, index 0 = pVerts
        self.faces = faces
        self.loc = loc            # world translation composed from op 4 / op 5 ancestors
        self.rot = rot            # world rotation, 3x3 row-major, from op 5 ancestors
        self.in_tree = in_tree
        self.centre = centre


IDENTITY = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


def _mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def _apply(r, v):
    return tuple(r[i][0] * v[0] + r[i][1] * v[1] + r[i][2] * v[2] for i in range(3))


class Dmd:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        self.n = len(self.d)
        if self.d[:4] != b'DXSP':
            raise ValueError('not a PS1 DMD file: %s' % path)
        self.meshes = []
        self.skipped = 0          # mesh blocks whose records did not parse
        self.dropped = 0          # faces whose indices fell outside the pool
        self.unknown_ops = {}
        self._seen = set()        # node offsets reached from the roots
        self._parsed = {}         # mesh offset -> (vbase, verts, faces, centre) or None
        self._walk()
        self._scan()

    # -- primitives -----------------------------------------------------
    def u32(self, o):
        return struct.unpack_from('<I', self.d, o)[0] if 0 <= o <= self.n - 4 else None

    def u16(self, o):
        return struct.unpack_from('<H', self.d, o)[0] if 0 <= o <= self.n - 2 else 0

    def off(self, ptr):
        if ptr is None:
            return None
        o = ptr - BASE
        return o if 0 <= o < self.n else None

    # -- hierarchy ------------------------------------------------------
    def _children(self, o):
        d, op = self.d, self.d[o]
        if op == 1:
            return [self.u32(o + 0x18 + 4 * i) for i in range(d[o + 0x14])]
        if op == 2:
            out = []
            for i in range(self.u32(o + 0x10) or 0):
                sub = self.off(self.u32(o + 0x14 + 4 * i))
                if sub is not None:
                    out.append(self.u32(sub + 8))
            return out
        if op == 3:
            return [self.u32(o + 0x20 + 4 * i) for i in range(d[o + 0x0B])]
        if op == 4:
            return [self.u32(o + 0x14 + 4 * i) for i in range(d[o + 0x12])]
        if op == 5:
            return [self.u32(o + 0x28 + 4 * i) for i in range(d[o + 0x26])]
        if op == 9:
            return [self.u32(o + 0x08 + 4 * i) for i in range(d[o + 0x06])]
        if op == 11:
            return [self.u32(o + 0x0C), self.u32(o + 0x10)]
        if op == 12:
            return [self.u32(o + 0x08 + 4 * i) for i in range(self.u16(o + 0x06))]
        if op not in (0, 6, 7, 8):
            key = (op, d[o + 1])
            self.unknown_ops[key] = self.unknown_ops.get(key, 0) + 1
        return []

    def _walk(self):
        """Every path from a root to a mesh is one placed instance of it: a
        ground tile is one mesh node referenced from a translation node per
        position, so a visit is keyed by node and transform, not node alone."""
        tab = self.off(self.u32(0x14))
        n = self.u32(tab)
        stack = [(self.off(self.u32(tab + 4 + 4 * i)), IDENTITY, (0, 0, 0)) for i in range(n)]
        visited = set()
        while stack:
            o, rot, loc = stack.pop()
            if o is None or o + 4 > self.n or (o, rot, loc) in visited:
                continue
            visited.add((o, rot, loc))
            self._seen.add(o)
            op = self.d[o]
            if op == 0:
                if self.d[o + 1] == 0xFF:
                    self._mesh(o, loc, rot, True)
                continue
            if op == 4:
                t = _apply(rot, struct.unpack_from('<3i', self.d, o + 4))
                loc = (loc[0] + t[0], loc[1] + t[1], loc[2] + t[2])
            elif op == 5:
                # a PlayStation MATRIX: s16 m[3][3] in 1/4096 units then s32 t[3];
                # the GTE applies it as v' = M v + t
                m = struct.unpack_from('<9h', self.d, o + 4)
                local = tuple(tuple(m[3 * i + j] / 4096.0 for j in range(3)) for i in range(3))
                t = _apply(rot, struct.unpack_from('<3i', self.d, o + 0x18))
                loc = (loc[0] + t[0], loc[1] + t[1], loc[2] + t[2])
                rot = _mul(rot, local)
            for k in self._children(o):
                if k:
                    stack.append((self.off(k), rot, loc))

    def _scan(self):
        """Mesh nodes no root reaches: whole sub-trees of the level are only
        referenced from code (interactive objects), so pick them up by their
        signature, trusting only a node whose pPolys is its own address + 0x2c."""
        pos = 0
        while True:
            i = self.d.find(MESH_SIG, pos)
            if i < 0:
                break
            pos = i + 4
            if i % 4 == 0 and i not in self._seen and self.u32(i + 0xC) == BASE + i + 0x2C \
                    and self.off(self.u32(i + 4)) is not None:
                self._seen.add(i)
                self._mesh(i, (0, 0, 0), IDENTITY, False)

    # -- mesh -----------------------------------------------------------
    def _mesh(self, o, loc, rot, in_tree):
        if o in self._parsed:
            parsed = self._parsed[o]
            if parsed:
                vo, verts, faces, centre = parsed
                self.meshes.append(Mesh(o, vo, verts, faces, loc, rot, in_tree, centre))
            return
        self._parsed[o] = None
        vo = self.off(self.u32(o + 4))
        pp = self.off(self.u32(o + 0xC))
        npoly = self.u16(o + 0x10)
        if vo is None or pp is None or not npoly or npoly > 8192:
            self.skipped += 1
            return
        faces, q, top = [], pp, -1
        for _ in range(npoly):
            if q + 20 > self.n:
                break
            b0, b1, size = self.d[q], self.d[q + 1], self.d[q + 2] * 4
            code = self.d[q + 19]
            if b1 not in (1, 3, 4) or size < 20 or q + size > self.n:
                break
            nv = 4 if code & 0x08 else 3
            if (b0 & 0x0F) not in (0, nv):
                break
            idx = struct.unpack_from('<4H', self.d, q + 4)[:nv]
            ncol = b1
            colors = [tuple(self.d[q + 16 + 4 * k:q + 19 + 4 * k]) for k in range(ncol)]
            if ncol == 1:
                colors = colors * nv
            elif ncol < nv:
                colors = colors + [colors[-1]] * (nv - ncol)
            p = q + 16 + 4 * ncol
            uvs = clut = tpage = window = None
            if b0 & 0x0F:
                if p + 4 * nv > q + size:
                    break
                uvs = [(self.d[p + 4 * k], self.d[p + 1 + 4 * k]) for k in range(nv)]
                clut = self.u16(p + 2)
                tpage = self.u16(p + 6)
                p += 4 * nv
                if b0 & 0x80:
                    window = self.u32(p)
                    p += 4
            faces.append(Face(idx, colors, code, uvs, clut, tpage, window))
            top = max(top, max(idx))
            q += size
        if len(faces) != npoly or top < 0 or top > 16384:
            self.skipped += 1
            return
        verts = []
        for k in range(top + 1):
            b = vo + 8 * k
            verts.append(struct.unpack_from('<3h', self.d, b) if b + 6 <= self.n else (0, 0, 0))
        centre = struct.unpack_from('<3i', self.d, o + 0x1C)
        self._parsed[o] = (vo, verts, faces, centre)
        self.meshes.append(Mesh(o, vo, verts, faces, loc, rot, in_tree, centre))

    # -- output ---------------------------------------------------------
    def merged(self, scale=1.0 / 64.0, translate=False):
        """One vertex soup in Godot axes (game Z up becomes Godot Y up).

        Returns (verts, faces) where each face is (indices, Face, mesh)."""
        vs, fs, pool = [], [], {}
        for m in self.meshes:
            t, r = (m.loc, m.rot) if translate else ((0, 0, 0), IDENTITY)
            for f in m.faces:
                if max(f.idx) >= len(m.verts):
                    self.dropped += 1
                    continue
                out = []
                for i in f.idx:
                    key = (m.vbase + 8 * i, t, r)
                    j = pool.get(key)
                    if j is None:
                        x, y, z = _apply(r, m.verts[i])
                        j = pool[key] = len(vs)
                        vs.append(((x + t[0]) * scale, (z + t[2]) * scale, (y + t[1]) * scale))
                    out.append(j)
                fs.append((out, f, m))
        return vs, fs
