"""Refit the loincloth for full rear coverage without changing anatomy."""

import os
import sys

import bpy


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import refine_accepted_hero_layers as layers


ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUTPUT_BLEND = os.environ.get(
    "BK_CLOTH_OUTPUT_BLEND",
    os.path.join(ROOT, "blender", "BrokenKnight_Hero_RearCoverageCandidate.blend"),
)
OUTPUT_GLB = os.environ.get(
    "BK_CLOTH_OUTPUT_GLB",
    os.path.join(ROOT, "godot", "assets", "hero", "hero_full_continuous_rear_coverage_candidate.glb"),
)


def main():
    body = bpy.data.objects["ConnectedBody"]
    rig = bpy.data.objects["HeroRig"]
    body_vertex_snapshot = tuple(tuple(vertex.co) for vertex in body.data.vertices)
    layers.rebuild_loincloth(body, rig)
    if body_vertex_snapshot != tuple(tuple(vertex.co) for vertex in body.data.vertices):
        raise RuntimeError("Rear coverage pass changed the accepted body")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    layers.OUTPUT_GLB = OUTPUT_GLB
    layers.export(rig)
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND, copy=False)
    print(f"REAR_COVERAGE_DONE|blend={OUTPUT_BLEND}|glb={OUTPUT_GLB}")


if __name__ == "__main__":
    main()
