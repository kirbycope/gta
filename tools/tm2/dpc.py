"""Read the .DPC model databases from the Twisted Metal 2 PC disc.

Reverse engineered from the retail data; no game code was used.

File
    "DCPMC", u32 stamp, u32 loadBase, ... , u32 nRoots, u32 rootPtrs[]
    Pointers are absolute against BASE, so fileOffset = pointer - BASE.

Mesh node (the only node kind this module needs)
    +0x00 u32  0x0000ff00
    +0x04 u32  pVerts        start of this mesh's slice of the vertex pool
    +0x08 u32  pNormals
    +0x0c u32  pPolys        always the node address + 0x2c, which is the
                             invariant used to tell a real node from a stray
                             0x0000ff00 word elsewhere in the file
    +0x10 u32  nPolys
    +0x1c i32  centre x, y, z
    +0x28 u32  radius
    +0x2c      the polygon records

Vertex
    PSX SVECTOR: i16 x, y, z and two bytes of padding. Z is up in this game.

Polygon record
    u8 nVerts (0x80 is a flag bit), u8 0x01, u8 sizeInDwords, u8 primWords
    u16 vertexIndex[nVerts]   relative to the node's own pVerts
    then a partly prebuilt PSX GPU primitive whose fourth word is
    rgb + command code (0x2c textured quad, 0x3c gouraud textured quad),
    followed by one u16 u, u16 v pair per vertex.
"""
import struct

BASE = 0x80019c40
MESH_SIG = bytes([0x00, 0xFF, 0x00, 0x00])


class Mesh:
    __slots__ = ('off', 'verts', 'faces', 'vbase')

    def __init__(self, off, verts, faces):
        self.off = off
        self.verts = verts      # [(x, y, z)] in game units
        self.faces = faces      # [(indices, uvs, rgb, code)]


class Dpc:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        self.n = len(self.d)
        if self.d[:5] != b'DCPMC':
            raise ValueError('not a DPC file: %s' % path)
        self.meshes = []
        self.skipped = 0
        self.dropped = 0
        self._scan()

    def u32(self, o):
        return struct.unpack('<I', self.d[o:o + 4])[0] if 0 <= o <= self.n - 4 else None

    def u16(self, o):
        return struct.unpack('<H', self.d[o:o + 2])[0] if 0 <= o <= self.n - 2 else 0

    def off(self, ptr):
        if ptr is None:
            return None
        o = ptr - BASE
        return o if 0 <= o < self.n else None

    def _scan(self):
        # pass one: every node whose pPolys points at its own body + 0x2c
        offs, pos = [], 0
        while True:
            i = self.d.find(MESH_SIG, pos)
            if i < 0:
                break
            pos = i + 4
            if i % 4 == 0 and self.u32(i + 0xC) == BASE + i + 0x2C                     and self.off(self.u32(i + 4)) is not None:
                offs.append(i)
        offs.sort()
        # pass two: a block is only trusted if its records tile exactly up to
        # the next node, and every vertex lands inside the node's own sphere
        for k, o in enumerate(offs):
            limit = offs[k + 1] if k + 1 < len(offs) else self.n
            self._mesh(o, limit)

    def _mesh(self, o, limit):
        vo = self.off(self.u32(o + 4))
        npoly = self.u32(o + 0x10)
        if not npoly or npoly > 4096:
            self.skipped += 1
            return
        faces, q, top = [], o + 0x2C, -1
        for _ in range(npoly):
            if q + 4 > self.n:
                break
            nv = self.d[q] & 0x0F
            if self.d[q + 1] != 0x01 or nv not in (3, 4):
                break
            size = self.d[q + 2] * 4
            if size < 12 or q + size > self.n:
                break
            idx = struct.unpack('<%dH' % nv, self.d[q + 4:q + 4 + 2 * nv])
            pbase = q + 4 + ((2 * nv + 3) // 4) * 4
            rgb, code = self.d[pbase + 12:pbase + 15], self.d[pbase + 15]
            uvs = tuple((self.u16(pbase + 16 + 4 * k), self.u16(pbase + 18 + 4 * k))
                        for k in range(nv))
            faces.append((idx, uvs, tuple(rgb), code))
            top = max(top, max(idx))
            q += size
        if len(faces) != npoly or not (o + 0x2C < q <= limit):
            self.skipped += 1          # records did not tile: do not trust it
            return
        if top < 0 or top > 8192:
            self.skipped += 1
            return
        verts = []
        for k in range(top + 1):
            b = vo + 8 * k
            verts.append(struct.unpack('<3h', self.d[b:b + 6]) if b + 6 <= self.n else (0, 0, 0))
        cx, cy, cz = struct.unpack('<3i', self.d[o + 0x1C:o + 0x28])
        rad = struct.unpack('<I', self.d[o + 0x28:o + 0x2C])[0] * 1.35 + 64
        inside = []
        for idx, uvs, rgb, code in faces:
            if all((verts[i][0] - cx) ** 2 + (verts[i][1] - cy) ** 2
                   + (verts[i][2] - cz) ** 2 <= rad * rad for i in idx):
                inside.append((idx, uvs, rgb, code))
        if not inside:
            self.skipped += 1
            return
        self.dropped += len(faces) - len(inside)
        m = Mesh(o, verts, inside)
        m.vbase = vo
        self.meshes.append(m)

    def merged(self, scale=1.0 / 256.0):
        """One vertex/face soup in Godot axes: game Z up becomes Godot Y up."""
        vs, fs, pool = [], [], {}
        for m in self.meshes:
            for idx, uvs, rgb, code in m.faces:
                if max(idx) >= len(m.verts):
                    continue
                out = []
                for i in idx:
                    key = m.vbase + 8 * i     # identity in the shared vertex pool
                    j = pool.get(key)
                    if j is None:
                        x, y, z = m.verts[i]
                        j = pool[key] = len(vs)
                        vs.append((x * scale, z * scale, y * scale))
                    out.append(j)
                fs.append((out, uvs, rgb, code))
        return vs, fs


def write_obj(dpc, path, scale=1.0 / 256.0):
    vs, fs = dpc.merged(scale)
    with open(path, 'w') as f:
        f.write('# Twisted Metal 2 geometry, extracted from the retail disc\n')
        for x, y, z in vs:
            f.write('v %.4f %.4f %.4f\n' % (x, y, z))
        for idx, uvs, rgb, code in fs:
            f.write('f ' + ' '.join(str(i + 1) for i in idx) + '\n')
    return len(vs), len(fs)
