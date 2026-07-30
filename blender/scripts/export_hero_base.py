import bpy
import os


def main():
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    export_dir = os.path.join(project_root, "godot", "assets", "hero")
    os.makedirs(export_dir, exist_ok=True)
    export_path = os.path.join(export_dir, "hero_base_body.glb")

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type in {"MESH", "CURVE"} and obj.name != "Plane":
            obj.select_set(True)

    # glTF cannot reproduce the hero's large procedural material graphs.
    # Flatten each material to its authored viewport color in this temporary
    # background-export session; the source .blend remains unchanged.
    for material in bpy.data.materials:
        if not material.use_nodes:
            continue
        principled = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if principled is None:
            continue
        principled.inputs["Base Color"].default_value = material.diffuse_color
        principled.inputs["Roughness"].default_value = 0.72
        for node in list(material.node_tree.nodes):
            if node != principled and node.type != "OUTPUT_MATERIAL":
                material.node_tree.nodes.remove(node)
        output = next((node for node in material.node_tree.nodes if node.type == "OUTPUT_MATERIAL"), None)
        if output is not None:
            material.node_tree.links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    bpy.ops.export_scene.gltf(
        filepath=export_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"Exported hero body to: {export_path}")


if __name__ == "__main__":
    main()
