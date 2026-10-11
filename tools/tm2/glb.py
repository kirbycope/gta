"""Minimal glTF 2.0 binary writer.

write_glb        positions, vertex colours, triangles: one untextured mesh
write_glb_textured
                 one mesh with one primitive per material; a material is an
                 embedded PNG sampled nearest, or plain vertex colour
"""
import json, struct

GLTF_MAGIC, JSON_CHUNK, BIN_CHUNK = 0x46546C67, 0x4E4F534A, 0x004E4942
FLOAT, UINT = 5126, 5125
ARRAY_BUFFER, ELEMENT_BUFFER = 34962, 34963


def _pad(b, n=4, fill=b'\0'):
    return b + fill * (-len(b) % n)


def _pack(path, gl, blob):
    gl['buffers'] = [{'byteLength': len(blob)}]
    js = _pad(json.dumps(gl, separators=(',', ':')).encode(), fill=b' ')
    out = struct.pack('<III', GLTF_MAGIC, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), JSON_CHUNK) + js
    out += struct.pack('<II', len(blob), BIN_CHUNK) + blob
    open(path, 'wb').write(out)


def write_glb(path, verts, colors, tris, name='Mesh'):
    pos = _pad(b''.join(struct.pack('<3f', *v) for v in verts))
    col = _pad(b''.join(struct.pack('<4f', *c) for c in colors))
    idx = _pad(b''.join(struct.pack('<I', i) for t in tris for i in t))
    blob = pos + col + idx
    mn = [min(v[i] for v in verts) for i in range(3)]
    mx = [max(v[i] for v in verts) for i in range(3)]
    gl = {
        'asset': {'version': '2.0', 'generator': 'tm2 extractor'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [{'mesh': 0, 'name': name}],
        'meshes': [{'name': name, 'primitives': [
            {'attributes': {'POSITION': 0, 'COLOR_0': 1}, 'indices': 2, 'mode': 4}]}],
        'bufferViews': [
            {'buffer': 0, 'byteOffset': 0, 'byteLength': len(pos), 'target': ARRAY_BUFFER},
            {'buffer': 0, 'byteOffset': len(pos), 'byteLength': len(col), 'target': ARRAY_BUFFER},
            {'buffer': 0, 'byteOffset': len(pos) + len(col), 'byteLength': len(idx),
             'target': ELEMENT_BUFFER},
        ],
        'accessors': [
            {'bufferView': 0, 'componentType': FLOAT, 'count': len(verts), 'type': 'VEC3',
             'min': mn, 'max': mx},
            {'bufferView': 1, 'componentType': FLOAT, 'count': len(colors), 'type': 'VEC4'},
            {'bufferView': 2, 'componentType': UINT, 'count': len(tris) * 3, 'type': 'SCALAR'},
        ],
    }
    _pack(path, gl, blob)
    return len(verts), len(tris)


MESH_SURFACE_LIMIT = 200  # under Godot's 256 surfaces per mesh, with room


def write_glb_textured(path, primitives, name='Mesh', colonly=()):
    """[param primitives] is a list of dicts, one per material:
        verts   [(x, y, z)]
        colors  [(r, g, b, a)]  0..1
        uvs     [(u, v)] 0..1, or None for an untextured material
        tris    [(a, b, c)]
        png     PNG bytes, or None
        name    material name
        mask    True when the texture has transparent texels
    [param colonly] is a list of (name, verts, tris): positions-only nodes,
    one mesh each with no material, for Godot's -colonly collision hint.
    Returns (vertex count, triangle count)."""
    blob = b''
    views, accessors, materials, images, textures, prims = [], [], [], [], [], []
    nv = nt = 0

    def view(data, target=None):
        nonlocal blob
        v = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
        if target:
            v['target'] = target
        views.append(v)
        blob += _pad(data)
        return len(views) - 1

    def accessor(data, count, ctype, atype, target, extra=None):
        a = {'bufferView': view(data, target), 'componentType': ctype, 'count': count, 'type': atype}
        if extra:
            a.update(extra)
        accessors.append(a)
        return len(accessors) - 1

    for p in primitives:
        verts, colors, uvs, tris = p['verts'], p['colors'], p.get('uvs'), p['tris']
        if not tris:
            continue
        mn = [min(v[i] for v in verts) for i in range(3)]
        mx = [max(v[i] for v in verts) for i in range(3)]
        attrs = {
            'POSITION': accessor(b''.join(struct.pack('<3f', *v) for v in verts), len(verts),
                                 FLOAT, 'VEC3', ARRAY_BUFFER, {'min': mn, 'max': mx}),
            'COLOR_0': accessor(b''.join(struct.pack('<4f', *c) for c in colors), len(colors),
                                FLOAT, 'VEC4', ARRAY_BUFFER),
        }
        if uvs is not None:
            attrs['TEXCOORD_0'] = accessor(b''.join(struct.pack('<2f', *t) for t in uvs), len(uvs),
                                           FLOAT, 'VEC2', ARRAY_BUFFER)
        indices = accessor(b''.join(struct.pack('<I', i) for t in tris for i in t), len(tris) * 3,
                           UINT, 'SCALAR', ELEMENT_BUFFER)
        mat = {'name': p.get('name', 'material'),
               'doubleSided': True,
               'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1],
                                        'metallicFactor': 0.0, 'roughnessFactor': 1.0}}
        if p.get('png'):
            images.append({'bufferView': view(p['png']), 'mimeType': 'image/png',
                           'name': p.get('name', 'texture')})
            textures.append({'source': len(images) - 1, 'sampler': 0})
            mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': len(textures) - 1}
            if p.get('mask'):
                mat['alphaMode'] = 'MASK'
                mat['alphaCutoff'] = 0.5
        materials.append(mat)
        prims.append({'attributes': attrs, 'indices': indices, 'mode': 4,
                      'material': len(materials) - 1})
        nv += len(verts)
        nt += len(tris)

    # Godot caps a mesh at 256 surfaces (RenderingServer::MAX_MESH_SURFACES) and drops the rest
    # on import, which took 114 of Los Angeles's 370 materials with it, so the primitives are dealt
    # out across as many meshes as it takes
    meshes, nodes = [], []
    for start in range(0, len(prims), MESH_SURFACE_LIMIT):
        chunk = prims[start:start + MESH_SURFACE_LIMIT]
        if start == 0:
            part = name
        elif name.endswith('-col'):
            # Godot's collision hint is the name's last four characters, so the number goes before it
            part = '%s_%d-col' % (name[:-4], len(meshes) + 1)
        else:
            part = '%s_%d' % (name, len(meshes) + 1)
        meshes.append({'name': part, 'primitives': chunk})
        nodes.append({'mesh': len(meshes) - 1, 'name': part})
    for cname, cverts, ctris in colonly:
        if not ctris:
            continue
        mn = [min(v[i] for v in cverts) for i in range(3)]
        mx = [max(v[i] for v in cverts) for i in range(3)]
        pos = accessor(b''.join(struct.pack('<3f', *v) for v in cverts), len(cverts),
                       FLOAT, 'VEC3', ARRAY_BUFFER, {'min': mn, 'max': mx})
        ind = accessor(b''.join(struct.pack('<I', i) for t in ctris for i in t), len(ctris) * 3,
                       UINT, 'SCALAR', ELEMENT_BUFFER)
        meshes.append({'name': cname, 'primitives': [{'attributes': {'POSITION': pos}, 'indices': ind, 'mode': 4}]})
        nodes.append({'mesh': len(meshes) - 1, 'name': cname})
    gl = {
        'asset': {'version': '2.0', 'generator': 'tm2 extractor'},
        'scene': 0,
        'scenes': [{'nodes': list(range(len(nodes)))}],
        'nodes': nodes,
        'meshes': meshes,
        'materials': materials,
        'bufferViews': views,
        'accessors': accessors,
    }
    if images:
        gl['images'] = images
        gl['textures'] = textures
        # nearest filtering and clamping: a PlayStation texel is a hard square
        gl['samplers'] = [{'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071}]
    _pack(path, gl, blob)
    return nv, nt
