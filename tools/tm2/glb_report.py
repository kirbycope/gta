"""Report what is inside a .glb: meshes, vertices, materials, images, UVs, bounds.

    python tools/tm2/glb_report.py addons/gta/tw/assets/los_angeles.glb [more.glb ...]

Standard library only; reads the JSON chunk and the accessor bounds.
"""
import json
import os
import struct
import sys


def report(path):
    d = open(path, 'rb').read()
    magic, version, length = struct.unpack_from('<III', d, 0)
    if magic != 0x46546C67:
        raise ValueError('not a glb: %s' % path)
    js_len, js_type = struct.unpack_from('<II', d, 12)
    gl = json.loads(d[20:20 + js_len])
    acc = gl.get('accessors', [])
    meshes = gl.get('meshes', [])
    prims = [p for m in meshes for p in m['primitives']]
    nverts = sum(acc[p['attributes']['POSITION']]['count'] for p in prims)
    ntris = sum(acc[p['indices']]['count'] // 3 for p in prims if 'indices' in p)
    with_uv = sum(1 for p in prims if 'TEXCOORD_0' in p['attributes'])
    with_col = sum(1 for p in prims if 'COLOR_0' in p['attributes'])
    mn = [min(acc[p['attributes']['POSITION']]['min'][i] for p in prims) for i in range(3)]
    mx = [max(acc[p['attributes']['POSITION']]['max'][i] for p in prims) for i in range(3)]
    mats = gl.get('materials', [])
    textured = sum(1 for m in mats if 'baseColorTexture' in m.get('pbrMetallicRoughness', {}))
    masked = sum(1 for m in mats if m.get('alphaMode') == 'MASK')
    images = gl.get('images', [])
    print('%s (%d bytes)' % (path, os.path.getsize(path)))
    print('   meshes %d, primitives %d, vertices %d, triangles %d'
          % (len(meshes), len(prims), nverts, ntris))
    print('   materials %d (%d textured, %d alpha-masked), images %d, textures %d'
          % (len(mats), textured, masked, len(images), len(gl.get('textures', []))))
    print('   primitives with TEXCOORD_0: %d, with COLOR_0: %d' % (with_uv, with_col))
    print('   bounds m: x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f  (%.1f x %.1f x %.1f)'
          % (mn[0], mx[0], mn[1], mx[1], mn[2], mx[2], mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]))
    if images:
        sizes = [gl['bufferViews'][im['bufferView']]['byteLength'] for im in images]
        print('   image bytes: total %d, largest %d, smallest %d' % (sum(sizes), max(sizes), min(sizes)))
    for node in gl.get('nodes', []):
        print('   node %r -> mesh %s' % (node.get('name'), node.get('mesh')))


if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
