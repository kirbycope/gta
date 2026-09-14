"""Normalise the ripped Twisted Metal 2 car models.

The models on the Models Resource are ripped at wildly different scales, from
about one unit long to a hundred and fifty, so they are rescaled to a common
real world length and sat on the ground with their origin between the wheels.
Everything else about the .obj is left alone, so the .mtl and its textures
still apply and Godot imports them as they are.
"""
import os
import shutil

# A Twisted Metal 2 car is read as a normal road car: 4.5 m nose to tail. The
# rips carry no units of their own, so this is the one assumed number here.
TARGET_LENGTH = 4.5


def normalise(obj_path, out_dir):
    lines = open(obj_path, encoding='utf8', errors='replace').read().splitlines()
    verts = []
    for line in lines:
        if line.startswith('v '):
            verts.append([float(t) for t in line.split()[1:4]])
    if not verts:
        return None
    mn = [min(v[i] for v in verts) for i in range(3)]
    mx = [max(v[i] for v in verts) for i in range(3)]
    size = [mx[i] - mn[i] for i in range(3)]
    # the longest horizontal axis is the length of the car
    length = max(size[0], size[2]) or 1.0
    scale = TARGET_LENGTH / length
    cx = (mn[0] + mx[0]) * 0.5
    cz = (mn[2] + mx[2]) * 0.5
    floor = mn[1]

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, os.path.basename(obj_path))
    with open(out_path, 'w', encoding='utf8') as f:
        for line in lines:
            if line.startswith('v '):
                p = [float(t) for t in line.split()[1:4]]
                f.write('v %.6f %.6f %.6f\n' % ((p[0] - cx) * scale,
                                                (p[1] - floor) * scale,
                                                (p[2] - cz) * scale))
            else:
                f.write(line + '\n')
    # carry the material and its textures across untouched
    src_dir = os.path.dirname(obj_path)
    for name in os.listdir(src_dir):
        if name.lower().endswith(('.mtl', '.png', '.jpg')):
            shutil.copy2(os.path.join(src_dir, name), os.path.join(out_dir, name))
    return {'name': os.path.splitext(os.path.basename(obj_path))[0],
            'scale': scale,
            'size': [s * scale for s in size]}
