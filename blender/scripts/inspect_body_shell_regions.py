import bpy

body = bpy.data.objects["ConnectedBody"]
regions = {
    "upper_L": ("upper_arm.L",),
    "fore_L": ("forearm.L",),
    "hand_L": ("hand.L", "thumb_01_r", "index_01_r", "middle_01_r", "ring_01_r", "pinky_01_r"),
    "thigh_L": ("thigh.L",),
    "shin_L": ("shin.L",),
    "foot_L": ("foot.L", "toe.L"),
    "upper_R": ("upper_arm.R",),
    "fore_R": ("forearm.R",),
    "hand_R": ("hand.R", "thumb_01_l", "index_01_l", "middle_01_l", "ring_01_l", "pinky_01_l"),
    "thigh_R": ("thigh.R",),
    "shin_R": ("shin.R",),
    "foot_R": ("foot.R", "toe.R"),
}

for label, names in regions.items():
    indices = {body.vertex_groups[name].index for name in names if body.vertex_groups.get(name)}
    def weight(vertex):
        return sum(a.weight for a in vertex.groups if a.group in indices)
    vertices = [v for v in body.data.vertices if weight(v) > 0.12]
    faces = [p for p in body.data.polygons if sum(weight(body.data.vertices[i]) for i in p.vertices) / len(p.vertices) > 0.12]
    mins = tuple(round(min(v.co[i] for v in vertices), 4) for i in range(3))
    maxs = tuple(round(max(v.co[i] for v in vertices), 4) for i in range(3))
    print("REGION|%s|verts=%d|faces=%d|min=%s|max=%s" % (label, len(vertices), len(faces), mins, maxs))
