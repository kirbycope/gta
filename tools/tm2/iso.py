"""Read files out of a Twisted Metal 2 (PC) disc image.

Accepts either a 2048-byte-per-sector .iso or a raw MODE1/2352 .bin track,
which is what a Redump dump of the disc is; the track is converted in memory.
"""
import os
import struct


class Iso:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.raw = os.path.getsize(path) % 2352 == 0 and not self._is_iso()
        self.files = {}
        self._read_tree()

    def _is_iso(self):
        self.f.seek(16 * 2048)
        return self.f.read(6)[1:6] == b'CD001'

    def sector(self, n, count=1):
        out = b''
        for k in range(count):
            if self.raw:
                self.f.seek((n + k) * 2352 + 16)
                out += self.f.read(2048)
            else:
                self.f.seek((n + k) * 2048)
                out += self.f.read(2048)
        return out

    def _read_tree(self):
        pvd = self.sector(16)
        if pvd[1:6] != b'CD001':
            raise ValueError('no ISO9660 volume descriptor')
        root = pvd[156:190]
        lba = struct.unpack('<I', root[2:6])[0]
        size = struct.unpack('<I', root[10:14])[0]
        self._walk(lba, size, '')

    def _walk(self, lba, length, path):
        data = self.sector(lba, (length + 2047) // 2048)
        i = 0
        while i < len(data):
            rec_len = data[i]
            if rec_len == 0:
                i = (i // 2048 + 1) * 2048
                if i >= len(data):
                    break
                continue
            rec = data[i:i + rec_len]
            ext = struct.unpack('<I', rec[2:6])[0]
            size = struct.unpack('<I', rec[10:14])[0]
            flags, nlen = rec[25], rec[32]
            name = rec[33:33 + nlen]
            if not (nlen == 1 and name in (b'\x00', b'\x01')):
                p = path + '/' + name.decode('ascii', 'replace').split(';')[0]
                if flags & 2:
                    self._walk(ext, size, p)
                else:
                    self.files[p] = (ext, size)
            i += rec_len

    def read(self, path):
        lba, size = self.files[path]
        return self.sector(lba, (size + 2047) // 2048)[:size]

    def extract(self, path, dest):
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, 'wb').write(self.read(path))
