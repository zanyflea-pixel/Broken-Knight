extends SceneTree

func _initialize()->void:call_deferred("_verify")

func _verify()->void:
    var visual:=Node3D.new()
    visual.set_script(load("res://scripts/HeroVisual.gd"))
    root.add_child(visual)
    for i in range(10):await process_frame
    var counts:={"armor_surfaces":0,"stable_cobalt":0,"white_cobalt":0}
    _inspect(visual,counts)
    var armor_surfaces:int=counts.armor_surfaces
    var stable_cobalt:int=counts.stable_cobalt
    var white_cobalt:int=counts.white_cobalt
    print("ROYAL_ARMOR_RUNTIME_MATERIALS|surfaces=%d|stable_cobalt=%d|white_cobalt=%d"%[armor_surfaces,stable_cobalt,white_cobalt])
    if armor_surfaces>=6 and stable_cobalt>=6 and white_cobalt==0:
        print("ROYAL_ARMOR_RUNTIME_MATERIALS|PASS")
        quit()
        return
    push_error("Royal armor runtime palette is incomplete")
    quit(1)

func _inspect(node:Node,counts:Dictionary)->void:
    if node is MeshInstance3D and String(node.name).begins_with("RoyalArmor_"):
        var mesh_node:=node as MeshInstance3D
        for surface in range(mesh_node.mesh.get_surface_count()):
            counts.armor_surfaces+=1
            var source:=mesh_node.mesh.surface_get_material(surface)
            if source!=null and String(source.resource_name)=="Royal Cobalt Filigree Plate":
                var active:=mesh_node.get_surface_override_material(surface) as BaseMaterial3D
                if active==null or active.albedo_color.is_equal_approx(Color.WHITE):
                    counts.white_cobalt+=1
                elif active.albedo_color.b>active.albedo_color.r*2.0 and active.metallic>=.60 and active.roughness>=.40:
                    # The world-readable blued metal remains clearly metallic
                    # while avoiding both the old shimmer and near-black loss
                    # of form under the outdoor reflection environment.
                    counts.stable_cobalt+=1
    for child in node.get_children():_inspect(child,counts)
