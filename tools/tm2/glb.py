"""Minimal glTF 2.0 binary writer: positions, vertex colours, triangles."""
import json, struct


def write_glb(path, verts, colors, tris, name='Mesh'):
    pos = b''.join(struct.pack('<3f', *v) for v in verts)
    col = b''.join(struct.pack('<4f', *c) for c in colors)
    idx = b''.join(struct.pack('<I', i) for t in tris for i in t)

    def pad(b):
        return b + b'\0' * (-len(b) % 4)

    pos, col, idx = pad(pos), pad(col), pad(idx)
    blob = pos + col + idx
    mn = [min(v[i] for v in verts) for i in range(3)]
    mx = [max(v[i] for v in verts) for i in range(3)]
    gl = {
        'asset': {'version': '2.0', 'generator': 'tm2 dpc extractor'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'mesh': 0, 'name': name}],
        'meshes': [{'name': name, 'primitives': [
            {'attributes': {'POSITION': 0, 'COLOR_0': 1}, 'indices': 2, 'mode': 4}]}],
        'buffers': [{'byteLength': len(blob)}],
        'bufferViews': [
            {'buffer': 0, 'byteOffset': 0, 'byteLength': len(pos), 'target': 34962},
            {'buffer': 0, 'byteOffset': len(pos), 'byteLength': len(col), 'target': 34962},
            {'buffer': 0, 'byteOffset': len(pos) + len(col), 'byteLength': len(idx), 'target': 34963},
        ],
        'accessors': [
            {'bufferView': 0, 'componentType': 5126, 'count': len(verts), 'type': 'VEC3',
             'min': mn, 'max': mx},
            {'bufferView': 1, 'componentType': 5126, 'count': len(colors), 'type': 'VEC4'},
            {'bufferView': 2, 'componentType': 5125, 'count': len(tris) * 3, 'type': 'SCALAR'},
        ],
    }
    js = pad(json.dumps(gl, separators=(',', ':')).encode())
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js
    out += struct.pack('<II', len(blob), 0x004E4942) + blob
    open(path, 'wb').write(out)
    return len(verts), len(tris)
