extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const EASTERN_KIT:PackedScene=preload("res://assets/world/eastern_marches_environment_kit_v1.glb")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var source:=EASTERN_KIT.instantiate()
    root.add_child(source)
    var required_meshes:={
        "MarchKeepFortification":Vector3(42,14,30),
        "DawnfordCaravanserai":Vector3(34,8,25),
        "AmberfieldWindmill":Vector3(14,15,12),
        "SaltwatchGranary":Vector3(15,10,15),
        "DawnfordArrivalSet":Vector3(13.5,3,12),
        "AmberfieldFieldSet":Vector3(19,3,5),
        "MarchKeepGateApproach":Vector3(25,4,5),
        "SaltwatchWorkYard":Vector3(17,3,10),
        "CinderwatchBeacon":Vector3(10,15,10),
        "CinderwatchSurveySet":Vector3(14,5,7),
        "EmbercragBasaltCrown":Vector3(38,10,38),
    }
    var source_surfaces:=0
    for mesh_name in required_meshes:
        var mesh_node:=source.find_child(mesh_name,true,false) as MeshInstance3D
        if mesh_node==null:
            failures.append("Eastern Blender kit is missing %s"%mesh_name)
            continue
        var size:=mesh_node.get_aabb().size
        var minimum:Vector3=required_meshes[mesh_name]
        if size.x<minimum.x or size.y<minimum.y or size.z<minimum.z:
            failures.append("%s has undersized bounds %s"%[mesh_name,size])
        source_surfaces+=mesh_node.mesh.get_surface_count()

    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_east_region_loaded()
    var context:Dictionary=main.get("_region_contexts").get("east_marches",{})
    var region_root:Node3D=context.get("root")
    var identity_count:=0
    var player_composition_count:=0
    var cinder_overrides:=0
    var cinder_lightest:=0.0
    for identity_name in ["Dawnford Identity","Amberfield Identity","March Keep Identity","Saltwatch Identity","Cinderwatch Beacon","Embercrag Basalt Crown"]:
        var identity:=region_root.find_child(identity_name,true,false) as MeshInstance3D if is_instance_valid(region_root) else null
        if identity==null:
            failures.append("Rendered Eastern identity is missing %s"%identity_name)
            continue
        identity_count+=1
        if identity_name=="Cinderwatch Beacon":
            for surface_index in range(identity.mesh.get_surface_count()):
                var override:=identity.get_surface_override_material(surface_index)
                if override==null:continue
                cinder_overrides+=1
                if override is BaseMaterial3D:
                    var albedo:Color=(override as BaseMaterial3D).albedo_color
                    cinder_lightest=maxf(cinder_lightest,(albedo.r+albedo.g+albedo.b)/3.0)
        if identity.find_child("*col",true,false)==null and identity.find_child("StaticBody3D",true,false)==null:
            failures.append("%s has no imported trimesh collision"%identity_name)

    for composition_name in [
        "Dawnford Arrival Shoulder","Amberfield Working Verge","March Keep Gate Approach",
        "Saltwatch Brine Yard","Cinderwatch Survey Station",
    ]:
        var composition:=region_root.find_child(composition_name,true,false) as MeshInstance3D if is_instance_valid(region_root) else null
        if composition==null:
            failures.append("Rendered Eastern player-height composition is missing %s"%composition_name)
            continue
        player_composition_count+=1
        if composition.find_child("*col",true,false)==null and composition.find_child("StaticBody3D",true,false)==null:
            failures.append("%s has no imported trimesh collision"%composition_name)

    var town_root:=region_root.get_node_or_null("TownRoot") if is_instance_valid(region_root) else null
    var marcher_houses:=0
    var hipped_roofs:=0
    var marcher_boundaries:=0
    if town_root!=null:
        for house in town_root.find_children("House_*","Node3D",true,false):
            if str(house.get_meta("architecture_set","")) not in ["marcher_stone","marcher_timber"]:continue
            marcher_houses+=1
            if house.find_child("MarcherHippedRoof",true,false)!=null:hipped_roofs+=1
        marcher_boundaries=town_root.find_children("Marcher* Town Boundary","Node3D",true,false).size()
    if marcher_houses<60:failures.append("Only %d marcher houses use the regional architecture set"%marcher_houses)
    if hipped_roofs<25:failures.append("Only %d marcher-stone houses use the terracotta hip profile"%hipped_roofs)
    if marcher_boundaries<4:failures.append("Only %d marcher settlement boundaries were built"%marcher_boundaries)

    var glassmere:=region_root.find_child("Glassmere_Water",true,false) as MeshInstance3D if is_instance_valid(region_root) else null
    var glassmere_vertices:=0
    if glassmere==null:
        failures.append("Glassmere water mesh is missing")
    else:
        var arrays:=glassmere.mesh.surface_get_arrays(0)
        glassmere_vertices=(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        if glassmere_vertices<300:failures.append("Glassmere still has only %d shoreline vertices"%glassmere_vertices)
    if cinder_overrides<3:failures.append("Cinderwatch has only %d regional material overrides"%cinder_overrides)
    if cinder_lightest<.45:failures.append("Cinderwatch material palette is still too dark (%.3f)"%cinder_lightest)

    print("EASTERN_MARCHES_VISUAL|kit_surfaces=%d|identities=%d|player_compositions=%d|houses=%d|hipped_roofs=%d|boundaries=%d|glassmere_vertices=%d|cinder_overrides=%d|cinder_lightest=%.3f|failures=%d"%[
        source_surfaces,identity_count,player_composition_count,marcher_houses,hipped_roofs,marcher_boundaries,glassmere_vertices,cinder_overrides,cinder_lightest,failures.size(),
    ])
    for failure in failures:push_error("EASTERN_MARCHES_VISUAL_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
