extends SceneTree

const KIT:PackedScene=preload("res://assets/world/glacial_environment_kit_v1.glb")


func _initialize()->void:
    var source:=KIT.instantiate()
    root.add_child(source)
    for child in source.get_children():
        if child is MeshInstance3D:
            var mesh_instance:=child as MeshInstance3D
            print("GLACIAL_ASSET|name=%s|position=%s|aabb=%s"%[
                mesh_instance.name,mesh_instance.position,mesh_instance.mesh.get_aabb(),
            ])
            for surface_index in range(mesh_instance.mesh.get_surface_count()):
                var material:=mesh_instance.mesh.surface_get_material(surface_index)
                print("GLACIAL_SURFACE|mesh=%s|surface=%d|material=%s"%[
                    mesh_instance.name,surface_index,material.resource_name if material!=null else "none",
                ])
    quit()
