"""Read a Twisted Metal 2 .PTS terrain file: the AI driving waypoints.

Each record is 24 bytes. The first two int32s are the point on the ground
plane in game units; the third is not a height but a flag word, so the points
are stored flat and the caller drops them onto the level. The remaining bytes
hold link data that is not decoded, and are exposed as the raw tail.
"""
import struct

RECORD = 24


def read_points(path, scale=1.0 / 64.0):
    d = open(path, 'rb').read()
    out = []
    for i in range(len(d) // RECORD):
        rec = d[i * RECORD:(i + 1) * RECORD]
        x, y, flags = struct.unpack('<3i', rec[:12])
        # the game's ground plane is x/y and Godot's is x/z
        out.append({'index': i,
                    'pos': (x * scale, 0.0, y * scale),
                    'flags': flags,
                    'tail': rec[12:]})
    return out
