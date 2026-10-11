"""Decode a Twisted Metal 2 .TMS texture bank into texture pages.

Reverse engineered from the retail data against aybe's TM1 reader
(github.com/aybe/Twisted, Tms.cs and Tim.cs); TM2 adds one table.

File
    +0x00 "TXSP", u32 version 0x43, u32 unix stamp (matches the .DMD's)
    +0x0C u32 count
    +0x10 u32 id[count]        per-TIM tags, not needed to decode
    then count times: u32 length, a standard PlayStation TIM of that length

TIM
    u32 0x10, u32 flags: bits 0-2 = 0 4bpp, 1 8bpp, 2 16bpp, 3 24bpp;
    bit 3 = a CLUT block comes first. Each block is u32 size, i16 x, y, w, h
    then w*h halfwords, where x, y, w are in VRAM halfwords.

Every TIM is a rectangle to upload into the 1024x512 halfword VRAM, and the
polygons address the result the GPU way: a tpage word selects a 256x256
texel page (x = (tpage & 0xF) * 64 halfwords, y = (tpage >> 4 & 1) * 256,
bpp = tpage >> 7 & 3) and a clut word a 16 or 256 colour palette row
(x = (clut & 0x3F) * 16, y = clut >> 6 & 0x1FF). A colour is 15-bit BGR; the
value 0 is fully transparent. A texture window word (GPU E2) wraps texels:
u = (u & ~(maskX * 8)) | ((offsetX & maskX) * 8), same for v.
"""
import struct
import zlib

VRAM_W, VRAM_H = 1024, 512


class Tms:
    def __init__(self, path):
        d = open(path, 'rb').read()
        if d[:4] != b'TXSP':
            raise ValueError('not a PS1 TMS file: %s' % path)
        self.count = struct.unpack_from('<I', d, 0xC)[0]
        self.vram = [[0] * VRAM_W for _ in range(VRAM_H)]
        self.tims = []           # (x, y, w, h, bpp) of every picture block
        p = 0x10 + 4 * self.count
        for _ in range(self.count):
            length = struct.unpack_from('<I', d, p)[0]
            self._tim(d, p + 4, length)
            p += 4 + length
        self._pages = {}

    def _blit(self, d, o):
        size, x, y, w, h = struct.unpack_from('<Ihhhh', d, o)
        row = o + 12
        for j in range(h):
            if 0 <= y + j < VRAM_H:
                vals = struct.unpack_from('<%dH' % w, d, row)
                self.vram[y + j][x:x + w] = vals[:max(0, min(w, VRAM_W - x))]
            row += 2 * w
        return o + size, (x, y, w, h)

    def _tim(self, d, o, length):
        if struct.unpack_from('<I', d, o)[0] != 0x10:
            return
        flags = struct.unpack_from('<I', d, o + 4)[0]
        p = o + 8
        if flags & 8:
            p, _ = self._blit(d, p)
        if p < o + length:
            p, rect = self._blit(d, p)
            self.tims.append(rect + (flags & 7,))

    # -- pages ----------------------------------------------------------
    def indices(self, tpage):
        """The 256x256 texel plane of a page as a list of rows; for a 16-bit
        page the texels are the colours themselves."""
        key = ('i', tpage)
        if key in self._pages:
            return self._pages[key]
        px = (tpage & 0xF) * 64
        py = ((tpage >> 4) & 1) * 256
        bpp = (tpage >> 7) & 3
        rows = []
        for v in range(256):
            y = py + v
            if y >= VRAM_H:
                rows.append([0] * 256)
                continue
            src = self.vram[y]
            if bpp == 0:
                row = []
                for hw in src[px:px + 64]:
                    row += [hw & 15, (hw >> 4) & 15, (hw >> 8) & 15, hw >> 12]
            elif bpp == 1:
                row = []
                for hw in src[px:px + 128]:
                    row += [hw & 255, hw >> 8]
            else:
                row = list(src[px:px + 256])
            row += [0] * (256 - len(row))
            rows.append(row[:256])
        self._pages[key] = rows
        return rows

    def palette(self, tpage, clut):
        bpp = (tpage >> 7) & 3
        if bpp >= 2:
            return None
        cx = (clut & 0x3F) * 16
        cy = (clut >> 6) & 0x1FF
        n = 16 if bpp == 0 else 256
        row = self.vram[cy] if cy < VRAM_H else [0] * VRAM_W
        return [rgba(c) for c in (row[cx:cx + n] + [0] * n)[:n]]

    def page(self, tpage, clut, window=None):
        """A 256x256 RGBA page as a list of rows of (r, g, b, a)."""
        key = (tpage, clut, window)
        if key in self._pages:
            return self._pages[key]
        idx = self.indices(tpage)
        pal = self.palette(tpage, clut)
        if window:
            mx, my = window & 0x1F, (window >> 5) & 0x1F
            ox, oy = (window >> 10) & 0x1F, (window >> 15) & 0x1F
            us = [(u & ~(mx * 8)) | ((ox & mx) * 8) for u in range(256)]
            vs = [(v & ~(my * 8)) | ((oy & my) * 8) for v in range(256)]
            idx = [[idx[vs[v]][us[u]] for u in range(256)] for v in range(256)]
        if pal is None:
            out = [[rgba(c) for c in row] for row in idx]
        else:
            out = [[pal[i] for i in row] for row in idx]
        self._pages[key] = out
        return out


def rgba(c):
    """A PlayStation 15-bit colour to 8-bit RGBA; 0 is the transparent texel."""
    if c == 0:
        return (0, 0, 0, 0)
    r, g, b = c & 31, (c >> 5) & 31, (c >> 10) & 31
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2), 255)


def png(rows, x0=0, y0=0, w=None, h=None):
    """Encode RGBA rows (optionally a crop) as a PNG, standard library only."""
    w = w or len(rows[0])
    h = h or len(rows)
    raw = bytearray()
    for y in range(y0, y0 + h):
        raw.append(0)
        for px in rows[y][x0:x0 + w]:
            raw.extend(px)

    def chunk(tag, body):
        c = tag + body
        return struct.pack('>I', len(body)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + chunk(b'IEND', b''))
