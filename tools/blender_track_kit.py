"""Builds the RRS trackside kit in Blender and exports it as one GLB.

Run inside Blender (Scripting tab, or via the MCP addon):
    exec(open(r"<project>/tools/blender_track_kit.py").read())

Creates a scene "track_kit" with one object per kit piece, low-poly and
flat-coloured (PS2 era). Conventions (design concept §15):
- metres, origin at ground level, centred on the piece
- length along +X, the side that faces the track is -Y (Godot +Z)
Exports assets/track_kit/track_kit.glb and saves source/track_kit.blend.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = r"C:\Projects\Claude Code Projects\RRS - Random Racing Series"
OUT_DIR = os.path.join(PROJECT, "assets", "track_kit")

scn = bpy.data.scenes.get("track_kit") or bpy.data.scenes.new("track_kit")
bpy.context.window.scene = scn
for o in list(scn.objects):
    bpy.data.objects.remove(o, do_unlink=True)


# --- materials ----------------------------------------------------------------

def material(name, color, metal=0.0, rough=0.85, image=None):
    m = bpy.data.materials.get("kit_" + name) or bpy.data.materials.new("kit_" + name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if image is not None:
        tex = next((n for n in nodes if n.type == "TEX_IMAGE"), None) or nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        m.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return m


def chainlink_image():
    size = 32
    img = bpy.data.images.get("kit_chainlink") or bpy.data.images.new("kit_chainlink", size, size, alpha=True)
    px = []
    for y in range(size):
        for x in range(size):
            on = (x + y) % 16 in (0, 1) or (x - y) % 16 in (0, 1)
            px += [0.78, 0.8, 0.82, 1.0] if on else [0.0, 0.0, 0.0, 0.0]
    img.pixels = px
    img.pack()
    return img


M = {
    "steel": material("steel", (0.62, 0.64, 0.67), 0.6, 0.45),
    "post": material("post", (0.45, 0.47, 0.5), 0.4, 0.6),
    "concrete": material("concrete", (0.74, 0.73, 0.7)),
    "red": material("red", (0.78, 0.09, 0.07)),
    "white": material("white", (0.93, 0.93, 0.9)),
    "tire": material("tire", (0.05, 0.05, 0.06), 0.0, 0.95),
    "fence_post": material("fence_post", (0.25, 0.4, 0.3), 0.3, 0.6),
    "chainlink": material("chainlink", (1, 1, 1), 0.5, 0.5, chainlink_image()),
    "bark": material("bark", (0.32, 0.22, 0.14)),
    "leaf_dark": material("leaf_dark", (0.11, 0.3, 0.14)),
    "leaf_light": material("leaf_light", (0.24, 0.45, 0.17)),
    "wall": material("wall", (0.9, 0.9, 0.87)),
    "roof": material("roof", (0.3, 0.32, 0.36)),
    "glass": material("glass", (0.2, 0.32, 0.45), 0.7, 0.15),
    "trim": material("trim", (0.12, 0.28, 0.7)),
    "door": material("door", (0.35, 0.37, 0.4), 0.3, 0.5),
    "seat_red": material("seat_red", (0.75, 0.1, 0.1)),
    "seat_blue": material("seat_blue", (0.1, 0.25, 0.7)),
    "seat_yellow": material("seat_yellow", (0.95, 0.75, 0.1)),
    "orange": material("orange", (1.0, 0.45, 0.05)),
    "skin": material("skin", (0.85, 0.64, 0.5)),
    "hair": material("hair", (0.15, 0.1, 0.07)),
    "shirt": material("shirt", (0.95, 0.95, 0.95)),  # tinted per spectator in Godot
    "pants": material("pants", (0.14, 0.17, 0.28)),
    "barn": material("barn", (0.55, 0.12, 0.09)),
    "house_wall": material("house_wall", (0.92, 0.85, 0.68)),
    "tile": material("tile", (0.5, 0.18, 0.12)),
    "billboard": material("billboard", (1, 1, 1)),  # recoloured per board in Godot
    "wood": material("wood", (0.45, 0.32, 0.2)),
}


# --- mesh builder ----------------------------------------------------------------

class Piece:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _index(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _finish_part(self, verts, m, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=verts)
        idx = self._index(m)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = idx

    def box(self, size, center, m, rot_z=0.0, rot_x=0.0):
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        mat = (Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_z, 4, "Z")
               @ Matrix.Rotation(rot_x, 4, "X") @ Matrix.Diagonal((*size, 1.0)))
        self._finish_part(verts, m, mat)

    def cylinder(self, r1, r2, h, center, m, segs=8, axis="Z"):
        verts = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=h)["verts"]
        rot = Matrix.Identity(4)
        if axis == "X":
            rot = Matrix.Rotation(math.pi / 2, 4, "Y")
        elif axis == "Y":
            rot = Matrix.Rotation(math.pi / 2, 4, "X")
        self._finish_part(verts, m, Matrix.Translation(Vector(center)) @ rot)

    def ico(self, r, center, m, squash=1.0):
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=r)["verts"]
        self._finish_part(verts, m, Matrix.Translation(Vector(center)) @ Matrix.Diagonal((1, 1, squash, 1)))

    def extrude_profile(self, profile_yz, length, m, x0=None):
        """Polygon in the YZ plane, extruded along X (centred)."""
        x0 = -length / 2 if x0 is None else x0
        a = [self.bm.verts.new((x0, y, z)) for y, z in profile_yz]
        b = [self.bm.verts.new((x0 + length, y, z)) for y, z in profile_yz]
        n = len(profile_yz)
        faces = [self.bm.faces.new(a[::-1]), self.bm.faces.new(b)]
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((a[i], a[j], b[j], b[i])))
        idx = self._index(m)
        for f in faces:
            f.material_index = idx

    def quad_uv(self, corners, uvs, m):
        """Single textured quad (used for the chain-link fence)."""
        verts = [self.bm.verts.new(c) for c in corners]
        f = self.bm.faces.new(verts)
        f.material_index = self._index(m)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv

    def build(self, location):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        obj = bpy.data.objects.new(self.name, me)
        obj.location = location
        scn.collection.objects.link(obj)
        return obj


# --- barriers -----------------------------------------------------------------------

def armco(loc):  # 4 m steel guardrail
    p = Piece("armco")
    for x in (-1.0, 1.0):
        p.box((0.1, 0.12, 0.85), (x, 0.12, 0.425), M["post"])
    for z in (0.52, 0.7):
        p.box((4.0, 0.05, 0.14), (0, 0, z), M["steel"])
    p.box((4.0, 0.03, 0.06), (0, 0.02, 0.61), M["steel"])
    return p.build(loc)


def concrete(loc, name="concrete", stripe=None):  # 3 m jersey barrier
    p = Piece(name)
    prof = [(-0.3, 0), (0.3, 0), (0.3, 0.08), (0.12, 0.3), (0.1, 0.85),
            (-0.1, 0.85), (-0.12, 0.3), (-0.3, 0.08)]
    p.extrude_profile(prof, 3.0, M["concrete"])
    if stripe:
        p.box((3.0, 0.01, 0.35), (0, -0.115, 0.55), M[stripe], rot_x=math.radians(-2.5))
    return p.build(loc)


def tirewall(loc):  # 2 m of stacked tyres, 3 rows deep x 4 high
    p = Piece("tirewall")
    for ix in range(3):
        for iy in range(2):
            for iz in range(4):
                m = M["white"] if iz == 2 else M["tire"]
                p.cylinder(0.31, 0.31, 0.22, (-0.66 + ix * 0.66, iy * 0.62, 0.11 + iz * 0.23), m, segs=10)
    p.box((2.0, 0.04, 0.95), (0, -0.33, 0.48), M["red"])  # front belt
    return p.build(loc)


def fence(loc):  # 4 m catch fence panel, 3 m high
    p = Piece("fence")
    p.box((0.08, 0.08, 3.1), (-2.0, 0.0, 1.55), M["fence_post"])
    p.box((4.0, 0.06, 0.06), (0, 0, 3.05), M["fence_post"])
    p.quad_uv([(-2, 0, 0.05), (2, 0, 0.05), (2, 0, 3.0), (-2, 0, 3.0)],
              [(0, 0), (4, 0), (4, 3), (0, 3)], M["chainlink"])
    return p.build(loc)


# --- nature ----------------------------------------------------------------------------

def pine(loc, name="tree_pine"):
    p = Piece(name)
    p.cylinder(0.22, 0.16, 2.0, (0, 0, 1.0), M["bark"], segs=6)
    for i, (r, z) in enumerate([(2.0, 2.6), (1.55, 4.0), (1.0, 5.3)]):
        p.cylinder(r, 0.05, 2.4, (0, 0, z), M["leaf_dark"], segs=7)
    return p.build(loc)


def round_tree(loc):
    p = Piece("tree_round")
    p.cylinder(0.25, 0.18, 2.6, (0, 0, 1.3), M["bark"], segs=6)
    p.ico(1.9, (0, 0, 3.6), M["leaf_light"], 0.85)
    p.ico(1.3, (0.9, 0.4, 4.5), M["leaf_light"], 0.85)
    p.ico(1.2, (-0.8, -0.5, 4.3), M["leaf_light"], 0.85)
    return p.build(loc)


def bush(loc):
    p = Piece("bush")
    p.ico(0.9, (0, 0, 0.55), M["leaf_dark"], 0.7)
    p.ico(0.6, (0.6, 0.2, 0.45), M["leaf_light"], 0.7)
    return p.build(loc)


# --- buildings -------------------------------------------------------------------------

def pit_building(loc):  # 60 x 14 x 6 m, garages facing the track (-Y)
    p = Piece("pit_building")
    p.box((60, 14, 6), (0, 0, 3), M["wall"])
    p.box((62, 16, 0.4), (0, 0, 6.2), M["roof"])
    p.box((60.2, 0.1, 0.5), (0, -7.05, 5.6), M["trim"])
    p.box((58, 0.1, 1.4), (0, -7.05, 4.6), M["glass"])
    for i in range(10):
        p.box((4.2, 0.1, 3.2), (-27 + i * 6, -7.05, 1.6), M["door"])
    return p.build(loc)


def control_tower(loc):
    p = Piece("control_tower")
    p.box((5, 5, 12), (0, 0, 6), M["wall"])
    p.box((5.1, 5.1, 0.4), (0, 0, 9), M["trim"])
    p.box((8, 8, 3.2), (0, 0, 13.6), M["glass"])
    p.box((9, 9, 0.5), (0, 0, 15.45), M["roof"])
    p.box((0.15, 0.15, 3), (0, 0, 17.2), M["post"])
    return p.build(loc)


def grandstand(loc):  # 40 m covered stand, facing -Y
    p = Piece("grandstand")
    seats = [M["seat_red"], M["seat_blue"], M["seat_yellow"]]
    for row in range(8):
        h = 0.6 + row * 0.55
        p.box((40, 1.1, h), (0, -3.85 + row * 1.1, h / 2), M["concrete"])
        p.box((40, 0.5, 0.35), (0, -3.85 + row * 1.1 - 0.15, h + 0.18), seats[row % 3])
    p.box((40, 0.4, 7.5), (0, 4.9, 3.75), M["wall"])
    for x in (-19.5, -6.5, 6.5, 19.5):
        p.box((0.3, 0.3, 8.6), (x, 4.6, 4.3), M["post"])
    p.box((41, 10.5, 0.3), (0, 0.2, 8.7), M["roof"], rot_x=math.radians(-6))
    p.box((41, 0.15, 0.8), (0, -5, 8.3), M["trim"])
    return p.build(loc)


def house(loc):
    p = Piece("house")
    p.box((8, 6, 3), (0, 0, 1.5), M["house_wall"])
    p.extrude_profile([(-3.4, 2.95), (3.4, 2.95), (0, 5.2)], 8.6, M["tile"])
    p.box((1.0, 0.1, 2.0), (0, -3.02, 1.0), M["wood"])
    for x in (-2.6, 2.6):
        p.box((1.2, 0.1, 1.0), (x, -3.02, 1.7), M["glass"])
    return p.build(loc)


def barn(loc):
    p = Piece("barn")
    p.box((12, 8, 5), (0, 0, 2.5), M["barn"])
    p.extrude_profile([(-4.5, 4.95), (4.5, 4.95), (0, 8.0)], 12.6, M["roof"])
    p.box((3.5, 0.1, 4.0), (0, -4.02, 2.0), M["wood"])
    return p.build(loc)


def billboard(loc):  # 8 x 3 m board on two posts, face is the "billboard" material
    p = Piece("billboard")
    for x in (-3, 3):
        p.box((0.2, 0.2, 5.2), (x, 0.15, 2.6), M["post"])
    p.box((8.2, 0.2, 3.2), (0, 0.05, 3.6), M["post"])
    p.box((8.0, 0.05, 3.0), (0, -0.07, 3.6), M["billboard"])
    return p.build(loc)


def marshal_post(loc):
    p = Piece("marshal_post")
    p.box((2.0, 2.0, 2.3), (0, 0, 1.15), M["white"])
    p.box((2.3, 2.3, 0.25), (0, 0, 2.42), M["orange"])
    p.box((1.6, 0.1, 0.8), (0, -1.02, 1.5), M["glass"])
    p.box((0.06, 0.06, 3.2), (0.9, -0.9, 1.6), M["post"])
    p.box((0.7, 0.02, 0.45), (1.25, -0.9, 2.95), M["seat_yellow"])
    return p.build(loc)


def spectator(loc):  # 1.75 m tall, blocky
    p = Piece("spectator")
    for x in (-0.11, 0.11):
        p.box((0.16, 0.2, 0.85), (x, 0, 0.425), M["pants"])
    p.box((0.46, 0.26, 0.62), (0, 0, 1.16), M["shirt"])
    for x in (-0.3, 0.3):
        p.box((0.12, 0.14, 0.6), (x, 0, 1.12), M["shirt"])
    p.box((0.24, 0.24, 0.26), (0, 0, 1.6), M["skin"])
    p.box((0.26, 0.26, 0.08), (0, 0.01, 1.76), M["hair"])
    return p.build(loc)


pieces = [
    armco((0, 0, 0)), concrete((6, 0, 0)), concrete((10, 0, 0), "concrete_red", "red"),
    concrete((14, 0, 0), "concrete_white", "white"), tirewall((18, 0, 0)), fence((24, 0, 0)),
    pine((32, 0, 0)), pine((37, 0, 0), "tree_pine_tall"), round_tree((42, 0, 0)), bush((47, 0, 0)),
    pit_building((0, 40, 0)), control_tower((45, 40, 0)), grandstand((0, 75, 0)),
    house((40, 75, 0)), barn((60, 75, 0)), billboard((80, 0, 0)), marshal_post((90, 0, 0)),
    spectator((95, 0, 0)),
]
# Make the second pine taller and slimmer.
tall = scn.objects["tree_pine_tall"]
tall.data.transform(Matrix.Diagonal((0.8, 0.8, 1.35, 1.0)))

os.makedirs(os.path.join(OUT_DIR, "source"), exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
for o in scn.objects:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "track_kit.glb"), export_format="GLB",
                          use_selection=True, use_active_scene=True, export_apply=True, export_yup=True)
bpy.data.libraries.write(os.path.join(OUT_DIR, "source", "track_kit.blend"), {scn}, fake_user=True, compress=True)
print("track kit:", ", ".join(sorted(o.name for o in scn.objects)))
print("tris:", sum(sum(len(f.vertices) - 2 for f in o.data.polygons) for o in scn.objects))
