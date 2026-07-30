import bpy
import json
import os


def round_vec(vec):
    return [round(float(v), 4) for v in vec]


def get_obj(name):
    obj = bpy.data.objects.get(name)
    if not obj:
        return None
    return {
        "location": round_vec(obj.location),
        "dimensions": round_vec(obj.dimensions),
        "rotation": round_vec(obj.rotation_euler),
    }


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    blend_dir = os.path.abspath(os.path.join(script_dir, ".."))
    preview_dir = os.path.join(blend_dir, "preview")
    os.makedirs(preview_dir, exist_ok=True)
    output_path = os.path.join(preview_dir, "hero_metrics.json")

    names = [
        "SkinBody",
        "ShirtShell",
        "Arm.L",
        "Arm.R",
        "Leg.L",
        "Leg.R",
        "Eye.L",
        "Eye.R",
        "HairCap",
    ]
    objects = {name: get_obj(name) for name in names}

    summary = {}
    skin = bpy.data.objects.get("SkinBody")
    shirt = bpy.data.objects.get("ShirtShell")
    arm_l = bpy.data.objects.get("Arm.L")
    arm_r = bpy.data.objects.get("Arm.R")
    eye_l = bpy.data.objects.get("Eye.L")
    eye_r = bpy.data.objects.get("Eye.R")

    if skin:
        summary["body_height"] = round(float(skin.dimensions.z), 4)
        summary["body_width"] = round(float(skin.dimensions.x), 4)
        summary["body_depth"] = round(float(skin.dimensions.y), 4)
    if shirt:
        summary["shirt_height"] = round(float(shirt.dimensions.z), 4)
        summary["shirt_width"] = round(float(shirt.dimensions.x), 4)
        summary["shirt_depth"] = round(float(shirt.dimensions.y), 4)
    if arm_l and arm_r:
        summary["arm_span"] = round(float(abs(arm_l.location.x - arm_r.location.x) + max(arm_l.dimensions.x, arm_r.dimensions.x)), 4)
        summary["arm_mount_y"] = round(float((arm_l.location.y + arm_r.location.y) * 0.5), 4)
        summary["arm_mount_z"] = round(float((arm_l.location.z + arm_r.location.z) * 0.5), 4)
    if eye_l and eye_r:
        summary["eye_spacing"] = round(float(abs(eye_l.location.x - eye_r.location.x)), 4)
        summary["eye_line_z"] = round(float((eye_l.location.z + eye_r.location.z) * 0.5), 4)

    payload = {
        "blend_file": bpy.data.filepath,
        "objects": objects,
        "summary": summary,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    print(f"Wrote hero metrics to: {output_path}")


if __name__ == "__main__":
    main()
