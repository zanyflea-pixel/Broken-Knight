extends SceneTree


func _initialize()->void:
    var scene:=load("res://assets/vegetation/highland_outcrop_v1.glb") as PackedScene
    var root_node:=scene.instantiate()
    _inspect(root_node)
    root_node.free()
    quit()


func _inspect(node:Node)->void:
    if node is MeshInstance3D:
        var mesh:Mesh=(node as MeshInstance3D).mesh
        for surface in range(mesh.get_surface_count()):
            var material:=mesh.surface_get_material(surface)
            var color:=Color.WHITE
            if material is BaseMaterial3D:color=(material as BaseMaterial3D).albedo_color
            print("OUTCROP_SURFACE|index=%d|material=%s|color=%s"%[surface,str(material),str(color)])
    for child in node.get_children():_inspect(child)
