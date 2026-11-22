"""Builds the RRS car roster in Blender: original low-poly (PS2-era) cars.

Run inside Blender (Scripting tab, or via the MCP addon):
    exec(open(r"<project>/tools/blender_cars.py").read())
Optional: set CARS_ONLY = ["kartal"] before exec() to rebuild only some cars.

Each car is lofted from cross-sections along its length, driven by a few
measurements (length, width, roof line, hood/deck heights, wheelbase...)
plus style choices for the grille, lights and wheels. The cars are inspired
by real models but are original designs with fictional names.

Conventions (design concept §15): metres, +Y forward, +X right, origin on the
ground between the axles. Each car exports to assets/cars/<id>/<id>.glb with
nodes body + wheel_FL/FR/RL/RR (wheel origin at the hub, axle along X).
Paint uses a material whose name contains "paint" (recoloured in Godot).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = r"C:\Projects\Claude Code Projects\RRS - Random Racing Series"

# --- the roster -------------------------------------------------------------------
# L/W/H: length, width, roof height. wb: wheelbase. r: wheel radius. fo: front overhang.
# y positions are measured from the FRONT bumper backwards (metres).
CARS = {
    "kartal": dict(  # 1977 Turkish 4-door classic (Anadol A2 SL inspired)
        L=4.20, W=1.62, H=1.38, wb=2.47, r=0.30, tw=0.17, fo=0.80, rocker=0.24,
        belt=0.88, nose=0.80, cowl=0.86, deck=0.92, tail=0.88,
        windshield=1.62, roof_front=1.98, roof_rear=3.05, deck_start=3.32,
        tumble=0.86, nose_round=0.10, tail_round=0.06, crown=0.03, tail_drop=0.06,
        paint=(0.22, 0.62, 0.10), roof_color="vinyl",
        grille="mesh_rect", headlight="square", taillight="pair_wide",
        wheel="hubcap", whitewall=True, bumpers="chrome", exhaust=1, mirrors="chrome"),
    "ashford": dict(  # British V12 grand tourer (Aston Martin DB11 inspired)
        L=4.74, W=1.95, H=1.28, wb=2.80, r=0.35, tw=0.25, fo=0.95, rocker=0.18,
        belt=0.82, nose=0.66, cowl=0.92, deck=0.95, tail=0.98,
        windshield=1.95, roof_front=2.55, roof_rear=3.30, deck_start=4.30,
        tumble=0.72, nose_round=0.22, tail_round=0.14, crown=0.05, tail_drop=0.16,
        paint=(0.30, 0.32, 0.35), grille="wide_bars", headlight="slim_swept",
        taillight="blade", wheel="spokes_dark", bumpers="body", exhaust=2, mirrors="black"),
    "quadra": dict(  # compact diesel sedan (Audi A3 Sedan inspired)
        L=4.46, W=1.80, H=1.42, wb=2.64, r=0.32, tw=0.22, fo=0.88, rocker=0.20,
        belt=0.98, nose=0.76, cowl=1.00, deck=1.03, tail=1.00,
        windshield=1.45, roof_front=2.10, roof_rear=3.05, deck_start=3.62,
        tumble=0.78, nose_round=0.15, tail_round=0.10, crown=0.04,
        paint=(0.05, 0.11, 0.36), grille="single_frame", headlight="angular",
        taillight="pair_angular", wheel="spokes_silver", bumpers="body", exhaust=1, mirrors="body"),
    "bellmont": dict(  # V8 luxury limousine (Bentley Flying Spur inspired)
        L=5.32, W=1.98, H=1.48, wb=3.19, r=0.37, tw=0.26, fo=1.00, rocker=0.22,
        belt=1.05, nose=0.92, cowl=1.06, deck=1.09, tail=1.04,
        windshield=1.80, roof_front=2.50, roof_rear=3.85, deck_start=4.35,
        tumble=0.80, nose_round=0.14, tail_round=0.10, crown=0.04,
        paint=(0.03, 0.03, 0.04), grille="matrix", headlight="round_twin",
        taillight="oval_pair", wheel="spokes_chrome", bumpers="chrome_trim", exhaust=4, mirrors="body"),
    "romola": dict(  # Italian diesel hatchback (Alfa Romeo Giulietta inspired)
        L=4.35, W=1.80, H=1.46, wb=2.63, r=0.32, tw=0.23, fo=0.88, rocker=0.20,
        belt=0.98, nose=0.74, cowl=1.00, deck=1.10, tail=1.02,
        windshield=1.40, roof_front=2.05, roof_rear=3.85, deck_start=4.18,
        tumble=0.78, nose_round=0.20, tail_round=0.10, crown=0.05,
        paint=(0.92, 0.92, 0.91), grille="shield", headlight="almond",
        taillight="pair_round", wheel="spokes_black", bumpers="body", exhaust=1, mirrors="body"),
    "bavaro": dict(  # 4-door fastback coupe (BMW 4 Series Gran Coupe inspired)
        L=4.78, W=1.85, H=1.44, wb=2.86, r=0.34, tw=0.24, fo=0.88, rocker=0.20,
        belt=0.98, nose=0.78, cowl=1.00, deck=1.03, tail=1.02,
        windshield=1.55, roof_front=2.25, roof_rear=3.05, deck_start=4.25,
        tumble=0.76, nose_round=0.16, tail_round=0.10, crown=0.04,
        paint=(0.07, 0.19, 0.62), grille="twin_tall", headlight="slim",
        taillight="blade", wheel="spokes_dark", bumpers="body", exhaust=2, mirrors="black"),
    "hanlong": dict(  # electric fastback sedan (BYD Han inspired)
        L=4.99, W=1.91, H=1.50, wb=2.92, r=0.35, tw=0.25, fo=0.95, rocker=0.20,
        belt=0.98, nose=0.72, cowl=0.98, deck=1.0, tail=0.98,
        windshield=1.55, roof_front=2.30, roof_rear=3.25, deck_start=4.45,
        tumble=0.77, nose_round=0.22, tail_round=0.14, crown=0.05, tail_drop=0.2,
        paint=(0.44, 0.46, 0.49), grille="closed", headlight="led_bar",
        taillight="full_bar", wheel="spokes_dark", bumpers="body", exhaust=0, mirrors="black"),
}

SHARED = {
    "glass": ((0.06, 0.08, 0.11), 0.6, 0.12),
    "chrome": ((0.85, 0.86, 0.88), 0.95, 0.12),
    "black": ((0.03, 0.03, 0.035), 0.1, 0.6),
    "trim": ((0.09, 0.09, 0.1), 0.2, 0.5),
    "tire": ((0.05, 0.05, 0.055), 0.0, 0.92),
    "whitewall": ((0.9, 0.9, 0.88), 0.0, 0.8),
    "rim_silver": ((0.7, 0.72, 0.74), 0.8, 0.3),
    "rim_dark": ((0.16, 0.17, 0.19), 0.6, 0.35),
    "rim_black": ((0.04, 0.04, 0.045), 0.3, 0.4),
    "caliper": ((0.75, 0.08, 0.06), 0.2, 0.5),
    "vinyl": ((0.04, 0.04, 0.045), 0.0, 0.85),
    "headlight": ((1.0, 0.97, 0.88), 0.2, 0.15),
    "headlight_amber": ((1.0, 0.72, 0.3), 0.2, 0.2),
    "drl": ((1.0, 0.8, 0.25), 0.1, 0.2),
    "taillight": ((0.85, 0.04, 0.04), 0.1, 0.25),
    "indicator": ((1.0, 0.45, 0.05), 0.1, 0.3),
    "mesh": ((0.55, 0.57, 0.6), 0.7, 0.4),
}

EMISSIVE = {"headlight": 2.0, "headlight_amber": 1.5, "drl": 2.5, "taillight": 1.2}


def material(name, color, metal, rough, emission=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return m


def shared_mats():
    return {k: material("car_" + k, *v, EMISSIVE.get(k, 0.0)) for k, v in SHARED.items()}


# --- mesh helpers ------------------------------------------------------------------

class Mesh:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _assign(self, verts, m, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=verts)
        idx = self.mi(m)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = idx

    def box(self, size, center, m, rx=0.0, rz=0.0):
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        mat = (Matrix.Translation(Vector(center)) @ Matrix.Rotation(rz, 4, "Z")
               @ Matrix.Rotation(rx, 4, "X") @ Matrix.Diagonal((*size, 1.0)))
        self._assign(verts, m, mat)

    def cyl(self, r, depth, center, m, axis="Y", segs=12, r2=None):
        verts = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r,
                                      radius2=r if r2 is None else r2, depth=depth)["verts"]
        rot = {"Z": Matrix.Identity(4), "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
               "Y": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
        self._assign(verts, m, Matrix.Translation(Vector(center)) @ rot)

    def prism(self, pts_xz, y, depth, m):
        """Flat polygon (in XZ) extruded along Y, for shaped grilles."""
        a = [self.bm.verts.new((x, y, z)) for x, z in pts_xz]
        b = [self.bm.verts.new((x, y + depth, z)) for x, z in pts_xz]
        n = len(a)
        faces = [self.bm.faces.new(a), self.bm.faces.new(b[::-1])]
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((a[i], b[i], b[j], a[j])))
        idx = self.mi(m)
        for f in faces:
            f.material_index = idx

    def build(self, collection, location=(0, 0, 0)):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        obj = bpy.data.objects.new(self.name, me)
        obj.location = location
        collection.objects.link(obj)
        return obj


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# --- body loft ---------------------------------------------------------------------

def body_profile(c, y_from_front):
    """Returns (half_width, z_bottom, z_belt, z_top, roof_half, zone)."""
    L, W = c["L"], c["W"]
    s = y_from_front
    w = W / 2
    # Rounded nose and tail in plan view.
    nr, tr = c["nose_round"], c["tail_round"]
    if s < 0.35:
        w *= 1.0 - nr * (1.0 - smooth(s / 0.35)) ** 1.5
    if s > L - 0.3:
        w *= 1.0 - tr * smooth((s - (L - 0.3)) / 0.3) ** 1.5
    # Top line.
    ws, rf, rr, ds = c["windshield"], c["roof_front"], c["roof_rear"], c["deck_start"]
    if s <= ws:
        t = s / ws
        z_top = c["nose"] + (c["cowl"] - c["nose"]) * (1 - (1 - t) ** 2)
        if s < 0.18:  # bumper face slopes back a little
            z_top -= (0.18 - s) * 0.5
        zone = "hood"
    elif s <= rf:
        t = (s - ws) / (rf - ws)
        z_top = c["cowl"] + (c["H"] - c["cowl"]) * math.sin(t * math.pi / 2) ** 1.2
        zone = "windshield"
    elif s <= rr:
        t = (s - rf) / (rr - rf)
        z_top = c["H"] + c["crown"] * math.sin(t * math.pi)
        zone = "roof"
    elif s <= ds:
        t = (s - rr) / (ds - rr)
        z_top = c["H"] + (c["deck"] - c["H"]) * smooth(t) ** 0.9
        zone = "rear_glass"
    else:
        t = (s - ds) / max(L - ds, 0.01)
        z_top = c["deck"] + (c["tail"] - c["deck"]) * t
        zone = "deck"
    # The tail rounds off and tucks under over the last few decimetres.
    tail_len = 0.35
    if s > L - tail_len:
        k = smooth((s - (L - tail_len)) / tail_len)
        z_top -= c.get("tail_drop", 0.12) * k ** 1.6
    cabin = zone in ("windshield", "roof", "rear_glass")
    if cabin:
        k = 1.0
        if zone == "windshield":
            k = smooth((s - ws) / (rf - ws))
        elif zone == "rear_glass":
            k = 1.0 - smooth((s - rr) / (ds - rr))
        roof_half = w * (0.9 + (c["tumble"] - 0.9) * k)
    else:
        roof_half = w * 0.72
    # Wheel arches: the lower edge lifts over each wheel.
    fa = c["fo"]
    ra = c["fo"] + c["wb"]
    z_bottom = c["rocker"]
    arch = c["r"] + 0.07
    for axle in (fa, ra):
        d = abs(s - axle)
        if d < arch:
            z_bottom = max(z_bottom, c["r"] + math.sqrt(arch * arch - d * d) * 0.98)
    # Bumpers sit a bit lower than the sills; chin and diffuser tuck up.
    if s < 0.25 or s > L - 0.25:
        z_bottom = min(z_bottom, c["rocker"] + 0.04)
    if s < 0.12:
        z_bottom += (0.12 - s) * 0.6
    if s > L - 0.3:
        z_bottom += smooth((s - (L - 0.3)) / 0.3) * 0.1
    z_belt = min(c["belt"], z_top - 0.05)
    return w, z_bottom, z_belt, z_top, roof_half, zone


def half_ring(w, zb, zbelt, ztop, rh):
    """8 points from bottom centre, up the right side, to top centre."""
    zbelt = max(zbelt, zb + 0.06)
    ztop = max(ztop, zbelt + 0.03)
    mid = zb + (zbelt - zb) * 0.55
    return [
        (0.0, zb),
        (w * 0.9, zb),
        (w, min(zb + 0.08, mid)),
        (w * 1.0, mid),
        (w * 0.985, zbelt),
        (w * 0.94, zbelt + min(0.04, (ztop - zbelt) * 0.3)),
        (rh, ztop - min(0.05, (ztop - zbelt) * 0.4)),
        (0.0, ztop),
    ]


def build_body(cid, c, M, coll):
    L = c["L"]
    front_y = c["fo"] + c["wb"] / 2  # body origin is mid-wheelbase
    # Stations along the car: fine near the arches and the glass.
    stations = set()
    s = 0.0
    while s <= L + 1e-6:
        stations.add(round(s, 3))
        s += 0.12
    for axle in (c["fo"], c["fo"] + c["wb"]):
        for k in range(-7, 8):
            stations.add(round(axle + k * (c["r"] + 0.07) / 7.0, 3))
    for key in ("windshield", "roof_front", "roof_rear", "deck_start"):
        stations.add(round(c[key], 3))
    stations = sorted(x for x in stations if 0.0 <= x <= L)

    m = Mesh("body")
    bm = m.bm
    rings, zones = [], []
    for s in stations:
        w, zb, zbelt, ztop, rh, zone = body_profile(c, s)
        hp = half_ring(w, zb, zbelt, ztop, rh)
        y = front_y - s
        right = [(x, z) for x, z in hp]
        left = [(-x, z) for x, z in reversed(hp[1:-1])]
        ring = [bm.verts.new((x, y, z)) for x, z in right + left]
        rings.append(ring)
        zones.append(zone)
    n = len(rings[0])
    paint = M["paint"]
    roof_mat = M["vinyl"] if c.get("roof_color") == "vinyl" else paint
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        za, zb_ = zones[i], zones[i + 1]
        cabin = za in ("windshield", "roof", "rear_glass") and zb_ in ("windshield", "roof", "rear_glass")
        for k in range(n):
            j = (k + 1) % n
            f = bm.faces.new((a[k], a[j], b[j], b[k]))
            mat = paint
            seg = k if k < 7 else n - 1 - k  # mirror index for the left side
            if cabin:
                if seg == 5:  # side window band
                    mat = M["glass"]
                elif seg == 6:
                    if za == "windshield" or za == "rear_glass":
                        mat = M["glass"]
                    else:
                        mat = roof_mat
            f.material_index = m.mi(mat)
    # End caps (nose and tail).
    f = bm.faces.new(rings[0][::-1])
    f.material_index = m.mi(paint)
    f = bm.faces.new(rings[-1])
    f.material_index = m.mi(paint)
    return m, front_y


def add_front(m, c, M, front_y):
    W = c["W"]
    y = front_y + 0.005
    nose = body_profile(c, 0.04)[3]
    hl_z = nose - 0.12
    g = c["grille"]
    # Grilles.
    if g == "mesh_rect":
        m.box((W * 0.5, 0.05, 0.2), (0, y, hl_z), M["mesh"])
        m.box((W * 0.52, 0.04, 0.025), (0, y + 0.01, hl_z + 0.11), M["chrome"])
    elif g == "wide_bars":
        m.prism([(-0.48, nose - 0.38), (0.48, nose - 0.38), (0.42, nose - 0.08), (-0.42, nose - 0.08)], y - 0.03, 0.04, M["black"])
        for k in range(4):
            m.box((0.86 - k * 0.03, 0.05, 0.015), (0, y + 0.02, nose - 0.13 - k * 0.065), M["chrome"])
    elif g == "single_frame":
        m.prism([(-0.3, nose - 0.47), (0.3, nose - 0.47), (0.36, nose - 0.22), (0.26, nose - 0.08), (-0.26, nose - 0.08), (-0.36, nose - 0.22)], y - 0.03, 0.04, M["black"])
        m.box((0.6, 0.05, 0.02), (0, y + 0.02, nose - 0.08), M["chrome"])
    elif g == "matrix":
        m.box((0.78, 0.06, 0.42), (0, y, nose - 0.22), M["chrome"])
        for k in range(7):
            m.box((0.012, 0.07, 0.38), (-0.33 + k * 0.11, y + 0.01, nose - 0.22), M["black"])
        m.box((W * 0.75, 0.05, 0.08), (0, y, c["rocker"] + 0.12), M["chrome"])
    elif g == "shield":
        m.prism([(0.0, nose - 0.5), (0.16, nose - 0.08), (-0.16, nose - 0.08)], y - 0.02, 0.04, M["black"])
        m.box((0.03, 0.05, 0.42), (0, y + 0.02, nose - 0.29), M["chrome"])
        for side in (-1, 1):
            m.box((0.42, 0.05, 0.1), (side * 0.48, y, c["rocker"] + 0.2), M["black"])
    elif g == "twin_tall":
        for side in (-1, 1):
            m.prism([(side * 0.03, nose - 0.5), (side * 0.27, nose - 0.5), (side * 0.25, nose - 0.04), (side * 0.06, nose - 0.04)], y - 0.03, 0.05, M["black"])
            m.box((0.025, 0.06, 0.46), (side * 0.15, y + 0.02, nose - 0.27), M["chrome"])
        m.box((W * 0.7, 0.05, 0.1), (0, y, c["rocker"] + 0.14), M["black"])
    elif g == "closed":
        m.box((W * 0.55, 0.04, 0.025), (0, y + 0.01, nose - 0.16), M["chrome"])
        m.box((W * 0.62, 0.05, 0.16), (0, y, c["rocker"] + 0.18), M["black"])
    # Headlights.
    hl = c["headlight"]
    lx = W / 2 - 0.22
    for side in (-1, 1):
        x = side * lx
        if hl == "square":
            m.box((0.2, 0.05, 0.16), (x, y, hl_z), M["headlight"])
            m.box((0.08, 0.05, 0.08), (side * (W / 2 - 0.06), y - 0.02, hl_z), M["headlight_amber"])
        elif hl == "slim_swept":
            m.box((0.34, 0.05, 0.07), (x, y - 0.08, nose - 0.08), M["headlight"], rz=side * 0.35)
        elif hl == "angular":
            m.prism([(x - side * 0.17, nose - 0.17), (x + side * 0.15, nose - 0.13), (x + side * 0.16, nose - 0.05), (x - side * 0.12, nose - 0.08)], y - 0.04, 0.04, M["headlight"])
        elif hl == "round_twin":
            m.cyl(0.095, 0.05, (side * (W / 2 - 0.2), y, hl_z), M["headlight"])
            m.cyl(0.07, 0.05, (side * (W / 2 - 0.4), y, hl_z), M["headlight"])
        elif hl == "almond":
            m.prism([(x - side * 0.16, nose - 0.13), (x + side * 0.14, nose - 0.06), (x + side * 0.1, nose - 0.02), (x - side * 0.1, nose - 0.07)], y - 0.06, 0.04, M["headlight"])
        elif hl == "slim":
            m.box((0.3, 0.05, 0.06), (x, y - 0.03, nose - 0.07), M["headlight"])
            m.box((0.24, 0.05, 0.015), (x, y - 0.02, nose - 0.11), M["drl"])
        elif hl == "led_bar":
            m.box((0.3, 0.05, 0.05), (x, y - 0.05, nose - 0.07), M["headlight"])
            m.box((0.36, 0.05, 0.015), (x - side * 0.02, y - 0.04, nose - 0.025), M["drl"])
    # Bumpers.
    if c["bumpers"] == "chrome":
        m.box((W * 1.02, 0.1, 0.07), (0, y + 0.03, c["rocker"] + 0.1), M["chrome"])
    elif c["bumpers"] == "chrome_trim":
        m.box((W * 0.9, 0.04, 0.025), (0, y + 0.01, c["rocker"] + 0.3), M["chrome"])
    # Mirrors.
    mz = c["belt"] + 0.12
    my = front_y - c["windshield"] - 0.15
    mm = {"chrome": M["chrome"], "black": M["black"]}.get(c["mirrors"], M["paint"])
    for side in (-1, 1):
        m.box((0.18, 0.1, 0.1), (side * (c["W"] / 2 + 0.06), my, mz), mm)


def add_rear(m, c, M, front_y):
    W = c["W"]
    y = front_y - c["L"] - 0.005
    tz = body_profile(c, c["L"] - 0.03)[3] - 0.14
    t = c["taillight"]
    for side in (-1, 1):
        x = side * (W / 2 - 0.2)
        if t == "pair_wide":
            m.box((0.34, 0.05, 0.14), (x, y, tz - 0.02), M["taillight"])
            m.box((0.1, 0.05, 0.14), (side * (W / 2 - 0.06), y, tz - 0.02), M["indicator"])
        elif t == "blade":
            m.box((0.5, 0.05, 0.035), (side * (W / 2 - 0.3), y, tz + 0.06), M["taillight"], rz=-side * 0.12)
        elif t == "pair_angular":
            m.prism([(x - side * 0.2, tz), (x + side * 0.16, tz + 0.02), (x + side * 0.14, tz + 0.1), (x - side * 0.18, tz + 0.06)], y - 0.035, 0.04, M["taillight"])
        elif t == "oval_pair":
            m.cyl(0.11, 0.05, (x, y, tz), M["taillight"], segs=10)
            m.box((0.24, 0.05, 0.12), (x - side * 0.06, y, tz), M["taillight"])
        elif t == "pair_round":
            m.cyl(0.09, 0.05, (x, y, tz + 0.04), M["taillight"], segs=10)
            m.box((0.22, 0.05, 0.06), (x - side * 0.14, y, tz + 0.06), M["taillight"])
    if t == "full_bar":
        m.box((W * 0.9, 0.05, 0.035), (0, y, tz + 0.06), M["taillight"])
    if c["bumpers"] == "chrome":
        m.box((W * 1.02, 0.1, 0.07), (0, y - 0.03, c["rocker"] + 0.12), M["chrome"])
    m.box((0.5, 0.03, 0.12), (0, y, c["rocker"] + 0.32), M["trim"])  # plate recess
    ex = c["exhaust"]
    xs = {1: [W / 2 - 0.35], 2: [-(W / 2 - 0.35), W / 2 - 0.35],
          4: [-(W / 2 - 0.3), -(W / 2 - 0.42), W / 2 - 0.42, W / 2 - 0.3]}.get(ex, [])
    for x in xs:
        m.cyl(0.045, 0.14, (x, y + 0.04, c["rocker"] + 0.04), M["chrome"], segs=8)


def build_wheel(name, c, M, coll, location, side):
    r, tw = c["r"], c["tw"]
    m = Mesh(name)
    m.cyl(r, tw, (0, 0, 0), M["tire"], axis="X", segs=14)
    out = side * (tw / 2 + 0.002)
    style = c["wheel"]
    rim = {"hubcap": M["chrome"], "spokes_dark": M["rim_dark"], "spokes_silver": M["rim_silver"],
           "spokes_chrome": M["chrome"], "spokes_black": M["rim_black"]}[style]
    if c.get("whitewall"):
        m.cyl(r * 0.82, 0.01, (out, 0, 0), M["whitewall"], axis="X", segs=14)
    m.cyl(r * 0.68, 0.012, (out * 1.01, 0, 0), M["rim_dark"] if style != "hubcap" else rim, axis="X", segs=14)
    if style == "hubcap":
        m.cyl(r * 0.6, 0.02, (out * 1.02, 0, 0), M["chrome"], axis="X", segs=12, r2=r * 0.45)
    else:
        for k in range(5):
            a = k * math.tau / 5
            m.box((0.02, r * 1.25, 0.05), (out * 1.03, 0, 0), rim, rx=a)
        m.cyl(r * 0.16, 0.03, (out * 1.04, 0, 0), rim, axis="X", segs=8)
        if c.get("calipers", style == "spokes_dark"):
            m.box((0.05, 0.12, 0.16), (side * (tw / 2 - 0.06), -0.05, 0.12), M["caliper"])
    return m.build(coll, location)


def build_car(cid, c):
    coll = bpy.data.collections.get("car_" + cid)
    if coll:
        for o in list(coll.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        coll = bpy.data.collections.new("car_" + cid)
        scn.collection.children.link(coll)
    M = dict(MATS)
    M["paint"] = material(f"{cid}_paint", c["paint"], 0.55, 0.3)
    m, front_y = build_body(cid, c, M, coll)
    add_front(m, c, M, front_y)
    add_rear(m, c, M, front_y)
    body = m.build(coll)
    half = c["wb"] / 2
    tx = c["W"] / 2 - c["tw"] / 2 - 0.035
    wheels = []
    for name, x, y, side in (("wheel_FL", -tx, half, -1), ("wheel_FR", tx, half, 1),
                             ("wheel_RL", -tx, -half, -1), ("wheel_RR", tx, -half, 1)):
        wheels.append(build_wheel(name, c, M, coll, (x, y, c["r"]), side))
    root = bpy.data.objects.new("car_" + cid, None)
    coll.objects.link(root)
    for o in [body] + wheels:
        o.parent = root
    return coll, root


scn = bpy.data.scenes.get("cars") or bpy.data.scenes.new("cars")
bpy.context.window.scene = scn
MATS = shared_mats()
only = globals().get("CARS_ONLY")
report = []
for i, (cid, c) in enumerate(CARS.items()):
    if only and cid not in only:
        continue
    coll, root = build_car(cid, c)
    root.location = (i * 3.0, 0, 0)
    out_dir = os.path.join(PROJECT, "assets", "cars", cid)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.objects:
        o.select_set(True)
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, cid + ".glb"), export_format="GLB",
                              use_selection=True, use_active_scene=True, export_apply=True, export_yup=True)
    root.location = (i * 3.0, 0, 0)
    tris = sum(sum(len(f.vertices) - 2 for f in o.data.polygons) for o in coll.objects if o.type == "MESH")
    report.append(f"{cid}: {tris} tris")
src = os.path.join(PROJECT, "assets", "cars", "_source")
os.makedirs(src, exist_ok=True)
open(os.path.join(src, ".gdignore"), "w").close()
bpy.data.libraries.write(os.path.join(src, "cars.blend"), {scn}, fake_user=True, compress=True)
print("\n".join(report))
