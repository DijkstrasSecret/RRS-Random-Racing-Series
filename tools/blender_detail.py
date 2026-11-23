"""Pixel-art detail for the generated cars' lamps and grille mesh (used by
blender_cars.py), like the hand-drawn lamps on a PS1 car texture.

attach_textures(MATS) gives the shared lamp / grille materials small pixel
textures (lens with a chrome rim and reflector, segmented tail lights,
diamond grille mesh). project_detail_uvs(body) maps every lamp / grille
piece's own UVs onto them: each piece is projected along the way it faces
and fitted to its outline, so a round lamp gets the whole lens, a wide one
gets two or three reflectors side by side.
"""
import bmesh
import bpy
import numpy as np
from mathutils import Vector

TEX = 32


def _image(name, rgb):
    """rgb: (h, w, 3) float array, row 0 = top."""
    h, w, _ = rgb.shape
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), dtype=np.float32)
    px[:, :, :3] = np.clip(rgb[::-1], 0.0, 1.0)  # Blender rows go bottom-up
    img.pixels[:] = px.ravel()
    img.pack()
    return img


def _lens(lens, rim=(0.6, 0.62, 0.66), inner=(0.22, 0.22, 0.25), reflector=True):
    n = TEX
    y, x = np.mgrid[0:n, 0:n] + 0.5
    rgb = np.empty((n, n, 3), dtype=np.float32)
    rgb[:] = lens
    if reflector:
        # Bowl reflector: bright middle, a darker ring, a hot spot.
        r = np.hypot((x - n / 2) / (n / 2), (y - n / 2) / (n / 2))
        rgb *= np.where(r < 0.42, 1.08, np.where(r < 0.62, 0.86, 0.95))[..., None]
        rgb[(r < 0.16)] = (1.0, 1.0, 1.0)
    # Lens flutes: every 4th column a touch darker.
    rgb[:, 3::4] *= 0.9
    # Glint top left.
    rgb[4:6, 5:9] = (1.0, 1.0, 1.0)
    # Inner shadow line and chrome rim.
    rgb[2:-2, 2] = inner
    rgb[2:-2, -3] = inner
    rgb[2, 2:-2] = inner
    rgb[-3, 2:-2] = inner
    rgb[:2, :] = rim
    rgb[-2:, :] = rim
    rgb[:, :2] = rim
    rgb[:, -2:] = rim
    rgb[-2:, :] *= 0.7  # rim darker underneath
    return rgb


def _tail(lens):
    n = TEX
    rgb = np.empty((n, n, 3), dtype=np.float32)
    rgb[:] = lens
    lens = np.array(lens, dtype=np.float32)
    rgb[3:11] = lens * 1.25      # upper band brighter
    rgb[11:12] = lens * 0.45     # divider
    rgb[22:23] = lens * 0.45
    rgb[23:-2] = lens * 0.8      # lower band deeper
    rgb[:, 7::8] *= 0.55         # vertical segments
    rgb[2, 3:12] = np.minimum(lens * 2.2, 1.0)  # glint
    rgb[:1, :] = (0.12, 0.12, 0.13)
    rgb[-1:, :] = (0.12, 0.12, 0.13)
    rgb[:, :1] = (0.12, 0.12, 0.13)
    rgb[:, -1:] = (0.12, 0.12, 0.13)
    return rgb


def _mesh_grille():
    n = 16
    y, x = np.mgrid[0:n, 0:n]
    rgb = np.empty((n, n, 3), dtype=np.float32)
    rgb[:] = (0.05, 0.05, 0.06)
    wire = ((x + y) % 8 == 0) | ((x - y) % 8 == 0)
    rgb[wire] = (0.48, 0.5, 0.53)
    rgb[wire & (y % 8 < 2)] = (0.62, 0.64, 0.68)  # lit tops of the wires
    return rgb


# Material key -> (texture, how many texture widths per piece height for tiling,
# or a fixed tile size in metres for patterns).
SPECS = {
    "headlight": dict(tex=lambda: _lens((0.93, 0.93, 0.88)), aspect=1.0),
    "headlight_amber": dict(tex=lambda: _lens((1.0, 0.74, 0.34)), aspect=1.0),
    "drl": dict(tex=lambda: _lens((1.0, 0.84, 0.36), reflector=False), aspect=3.0),
    "taillight": dict(tex=lambda: _tail((0.82, 0.05, 0.05)), aspect=1.6),
    "indicator": dict(tex=lambda: _tail((1.0, 0.48, 0.06)), aspect=1.6),
    "mesh": dict(tex=_mesh_grille, tile=0.09),
}


def attach_textures(mats):
    """Puts the pixel textures on the shared materials (in place)."""
    for key, spec in SPECS.items():
        mat = mats.get(key)
        if mat is None:
            continue
        img = _image("detail_" + key, spec["tex"]())
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        tex = next((n for n in nodes if n.type == "TEX_IMAGE" and n.image and n.image.name.startswith("detail_")), None)
        tex = tex or nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = "Closest"
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])


def project_detail_uvs(obj):
    """UVs for every lamp / grille piece of `obj` (first UV set)."""
    me = obj.data
    wanted = {}
    for i, mat in enumerate(me.materials):
        if mat is None:
            continue
        for key, spec in SPECS.items():
            if mat.name == "car_" + key:
                wanted[i] = spec
    if not wanted:
        return
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    seen = set()
    for f in bm.faces:
        if f.index in seen or f.material_index not in wanted:
            continue
        # The piece: faces of the same material connected to this one.
        island, stack = [], [f]
        seen.add(f.index)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen and h.material_index == f.material_index:
                        seen.add(h.index)
                        stack.append(h)
        spec = wanted[f.material_index]
        # Facing: the area-weighted normal of the piece.
        n = Vector((0, 0, 0))
        for g in island:
            n += g.normal * g.calc_area()
        n = n.normalized() if n.length > 1e-6 else Vector((0, 1, 0))
        up = Vector((0, 0, 1)) if abs(n.z) < 0.8 else Vector((0, 1, 0))
        u_axis = up.cross(n).normalized()
        v_axis = n.cross(u_axis).normalized()
        pts = [(v.co.dot(u_axis), v.co.dot(v_axis)) for g in island for v in g.verts]
        u0, u1 = min(p[0] for p in pts), max(p[0] for p in pts)
        v0, v1 = min(p[1] for p in pts), max(p[1] for p in pts)
        du, dv = max(u1 - u0, 1e-4), max(v1 - v0, 1e-4)
        if "tile" in spec:
            su, sv = du / spec["tile"], dv / spec["tile"]
        else:
            su = max(1, min(4, round(du / dv / spec["aspect"])))
            sv = 1.0
        for g in island:
            for loop in g.loops:
                p = loop.vert.co
                loop[uv].uv = ((p.dot(u_axis) - u0) / du * su, (p.dot(v_axis) - v0) / dv * sv)
    bm.to_mesh(me)
    bm.free()
