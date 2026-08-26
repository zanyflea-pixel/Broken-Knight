extends SceneTree


func _initialize()->void:
    call_deferred("_run")


func _inside_pond(point:Vector2,pond:Dictionary,margin:float=-1.5)->bool:
    var center:Vector2=pond.get("position",Vector2.ZERO)
    var delta:=point-center
    var angle:=atan2(delta.y,delta.x)
    var base_radius:float=float(pond.get("radius",70.0))*1.18
    var irregularity:=1.0+sin(angle*3.0+center.x*.0017)*.11+sin(angle*7.0+center.y*.0011)*.055
    return delta.length()<base_radius*irregularity+margin


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var profile:Dictionary=main.get("_active_profile")
    var props:=main.get_node("WorldRoot/PropsRoot")
    var total:=0
    for node in props.find_children("*","MultiMeshInstance3D",true,false):
        var instance:=node as MultiMeshInstance3D
        var multimesh:=instance.multimesh
        if multimesh==null:continue
        var buffer:=multimesh.buffer
        var overlap:=0
        var samples:Array[String]=[]
        for index in range(multimesh.instance_count):
            var offset:=index*12
            var local_origin:=Vector3(buffer[offset+3],buffer[offset+7],buffer[offset+11])
            var origin:Vector3=instance.global_transform*local_origin
            for pond_value in profile.get("pond_sites",[]):
                if _inside_pond(Vector2(origin.x,origin.z),pond_value):
                    overlap+=1
                    if samples.size()<2:samples.append("%s@%.1f,%.1f(local %.1f,%.1f)"%[str(pond_value.get("name","Pond")),origin.x,origin.z,local_origin.x,local_origin.z])
                    break
        if overlap<=0:continue
        total+=overlap
        var mesh_name:=multimesh.mesh.get_class() if multimesh.mesh!=null else "none"
        var color:="shader"
        if instance.material_override is StandardMaterial3D:
            color=(instance.material_override as StandardMaterial3D).albedo_color.to_html(false)
        print("POND_DRESSING_OVERLAP|count=%d|mesh=%s|color=%s|samples=%s|aabb=%s"%[overlap,mesh_name,color,str(samples),str(multimesh.mesh.get_aabb() if multimesh.mesh!=null else AABB())])
    print("POND_DRESSING_AUDIT|overlaps=%d|failures=%d"%[total,1 if total>0 else 0])
    # Also report authored ribbons touching Glassmere so visual regressions at
    # the lake mouth can be traced to a named mesh instead of guessed from a
    # screenshot.
    await main._ensure_east_region_loaded()
    var east_context:Dictionary=main.get("_region_contexts").get("east_marches",{})
    var east_root:Node3D=east_context.get("root")
    var glassmere_global:=Vector2(8980.0,2460.0)
    if is_instance_valid(east_root):
        for root_name in ["RiverRoot","RoadRoot"]:
            var authored_root:=east_root.get_node_or_null(root_name)
            if authored_root==null:continue
            for node in authored_root.find_children("*","MeshInstance3D",true,false):
                var mesh_instance:=node as MeshInstance3D
                if mesh_instance.mesh==null:continue
                var world_bounds:AABB=mesh_instance.global_transform*mesh_instance.mesh.get_aabb()
                var bounds_point:=Vector2(world_bounds.get_center().x,world_bounds.get_center().z)
                if bounds_point.distance_to(glassmere_global)>420.0:continue
                print("GLASSMERE_GEOMETRY|root=%s|name=%s|center=%.1f,%.1f|size=%.1f,%.1f"%[
                    root_name,mesh_instance.name,bounds_point.x,bounds_point.y,world_bounds.size.x,world_bounds.size.z,
                ])
    main.free()
    quit(1 if total>0 else 0)
