import os
import sys

import bpy


RATIOS = {
    "ConnectedBody": 0.52,
    "ProfessionalHelmetFace": 0.42,
    "HeroHairFlushFibers.Refined": 0.08,
    "HeroHairFoundation.Refined": 0.28,
    "HeroHairSweptLocks.Refined": 0.20,
    "ProfessionalBrows.Strands": 0.28,
    "RoyalArmor_chest_SovereignConsolidated": 0.42,
    "RoyalArmor_feet_SovereignConsolidated": 0.38,
    "RoyalArmor_hands_SovereignConsolidated": 0.20,
    "RoyalArmor_head_SovereignConsolidated": 0.30,
    "RoyalArmor_pants_SovereignConsolidated": 0.55,
    "RoyalArmor_shoulders_SovereignConsolidated": 0.38,
}


def parse_paths():
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 2:
        raise SystemExit("Expected input.glb and output.glb")
    return os.path.abspath(args[0]), os.path.abspath(args[1])


def apply_decimation(obj, ratio):
    before = len(obj.data.polygons)
    modifier = obj.modifiers.new(name="BrokenKnightRuntimeDecimate", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    obj.modifiers.move(len(obj.modifiers) - 1, 0)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    after = len(obj.data.polygons)
    print(f"RUNTIME_DECIMATE|{obj.name}|before={before}|after={after}|ratio={after / max(1, before):.3f}")


def main():
    source, destination = parse_paths()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source)

    before_total = sum(len(obj.data.polygons) for obj in bpy.data.objects if obj.type == "MESH")
    for name, ratio in RATIOS.items():
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError(f"Required runtime mesh is missing: {name}")
        apply_decimation(obj, ratio)

    after_total = sum(len(obj.data.polygons) for obj in bpy.data.objects if obj.type == "MESH")
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=destination,
        export_format="GLB",
        export_animations=True,
        export_skins=True,
        export_morph=False,
        export_apply=False,
    )
    print(
        f"RUNTIME_OPTIMIZED_HERO|before_triangles={before_total}|after_triangles={after_total}|"
        f"ratio={after_total / max(1, before_total):.3f}|output={destination}"
    )


if __name__ == "__main__":
    main()
