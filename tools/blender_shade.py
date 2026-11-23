"""Baked shading for the generated cars (used by blender_cars.py).

Gives each car body a small, pixelly shade texture like a hand-painted PS1
car: ambient occlusion against the ground and itself (dark sills, wheel
arches, panel gaps, under the bumpers, round the lamps and grille), a soft
top-to-bottom falloff, posterized into a few steps with ordered dithering.
The game multiplies the body colours by it (second UV set, nearest filter),
so repainting a car keeps its shading.
"""
import os

import bpy
import numpy as np

SIZE = 256
UV_NAME = "shade"
# 4x4 Bayer matrix for the ordered dither (values 0..1).
_BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0


def _unwrap(body):
    me = body.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    layer = me.uv_layers.get(UV_NAME) or me.uv_layers.new(name=UV_NAME)
    me.uv_layers.active = layer
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.012, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    return layer


def _bake_ao(scn, body, image):
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = 96
    if scn.world is None:
        scn.world = bpy.data.worlds.new("bake_world")
    scn.world.light_settings.distance = 1.0
    # Ground under the car so the lower body darkens like it sits on the road.
    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(body.matrix_world.translation.x, 0.0, 0.0))
    ground = bpy.context.active_object
    added = []
    for mat in body.data.materials:
        if mat is None or not mat.use_nodes:
            continue
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.nodes.active = node
        added.append((mat, node))
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type="AO", margin=3, use_clear=True, target="IMAGE_TEXTURES")
    for mat, node in added:
        mat.node_tree.nodes.remove(node)
    bpy.data.objects.remove(ground, do_unlink=True)


def _height_map(body, layer, size):
    """Per texel: height of that bit of the body (0 = ground, 1 = roof),
    rasterised from the shade UVs (texels outside islands grow from their
    neighbours so the bake margin gets a height too)."""
    me = body.data
    layer = me.uv_layers[UV_NAME]  # (re-fetched: references go stale after the bake)
    zs = np.full((size, size), -1.0, dtype=np.float32)
    zmax = max((v.co.z for v in me.vertices), default=1.0) or 1.0
    for poly in me.polygons:
        loops = list(poly.loop_indices)
        uv = np.array([layer.data[i].uv[:] for i in loops], dtype=np.float32) * size
        h = np.array([me.vertices[me.loops[i].vertex_index].co.z / zmax for i in loops], dtype=np.float32)
        for k in range(1, len(loops) - 1):
            tri = uv[[0, k, k + 1]]
            th = h[[0, k, k + 1]]
            x0, y0 = np.floor(tri.min(axis=0)).astype(int)
            x1, y1 = np.ceil(tri.max(axis=0)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1 + 1, size), min(y1 + 1, size)
            if x1 <= x0 or y1 <= y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = tri
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-9:
                continue
            l0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / det
            l1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / det
            l2 = 1.0 - l0 - l1
            inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
            val = l0 * th[0] + l1 * th[1] + l2 * th[2]
            block = zs[y0:y1, x0:x1]
            block[inside] = val[inside]
    # Grow into the gaps.
    for _ in range(4):
        empty = zs < 0.0
        if not empty.any():
            break
        grown = zs.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(np.roll(zs, dy, axis=0), dx, axis=1)
            take = empty & (shifted >= 0.0) & (grown < 0.0)
            grown[take] = shifted[take]
        zs = grown
    zs[zs < 0.0] = 0.5
    return zs


def bake_shade(cid, body, out_dir):
    """Unwraps the body, bakes and stylises its shade texture, saves
    <out_dir>/<cid>_shade.png. Leaves the "shade" UV set on the body."""
    scn = bpy.context.scene
    layer = _unwrap(body)
    name = f"{cid}_shade"
    image = bpy.data.images.get(name)
    if image:
        bpy.data.images.remove(image)
    image = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=False)
    image.colorspace_settings.name = "Non-Color"
    _bake_ao(scn, body, image)
    px = np.array(image.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
    ao = px[:, :, 0]
    height = _height_map(body, layer, SIZE)
    # Deep creases very dark, open panels near full; the lower body a bit darker.
    shade = 0.3 + 0.7 * np.power(np.clip(ao, 0.0, 1.0), 1.6)
    shade *= 0.62 + 0.38 * np.clip(height * 1.5, 0.0, 1.0)
    # Posterize into steps with an ordered dither: the hand-painted pixel look.
    steps = 8.0
    bayer = np.tile(_BAYER, (SIZE // 4, SIZE // 4))
    shade = np.floor(shade * steps + bayer) / steps
    shade = np.clip(shade, 0.22, 1.0)
    out = np.dstack([shade, shade, shade, np.ones_like(shade)]).astype(np.float32)
    image.pixels[:] = out.ravel()
    image.filepath_raw = os.path.join(out_dir, name + ".png")
    image.file_format = "PNG"
    image.save()
    me = body.data
    me.uv_layers.active = me.uv_layers[0]
    return image.filepath_raw
