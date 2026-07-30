extends SceneTree


func _init()->void:
    call_deferred("_run")


func _shape_hits(world:World3D,position:Vector3,radius:float=.12)->int:
    var sphere:=SphereShape3D.new()
    sphere.radius=radius
    var query:=PhysicsShapeQueryParameters3D.new()
    query.shape=sphere
    query.transform=Transform3D(Basis.IDENTITY,position)
    query.collision_mask=1
    return world.direct_space_state.intersect_shape(query,16).size()


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await physics_frame
    var props:Node3D=main.get_node("WorldRoot/PropsRoot")
    var town:Node3D=main.get_node("WorldRoot/TownRoot")
    var bush_body:=props.get_node_or_null("BushCollision") as StaticBody3D
    var rock_body:=props.get_node_or_null("MineableRockCollision") as StaticBody3D
    var detail_body:=town.get_node_or_null("TownDetailCollision") as StaticBody3D
    if bush_body==null or bush_body.get_child_count()<1000:failures.append("permanent bush collision body missing")
    if rock_body==null or rock_body.get_child_count()<500:failures.append("permanent rock collision body missing")
    if detail_body==null or int(detail_body.get_meta("detail_shape_count",0))<100:failures.append("town visual detail collision missing")
    var bush_registry:Array=props.get_meta("collision_prop_registry",[])
    var bush:Dictionary={}
    for prop in bush_registry:
        if prop.get("kind","")=="bush":
            bush=prop
            break
    if bush.is_empty() or _shape_hits(main.get_world_3d(),bush.position)<1:failures.append("bush physics query passed through")
    var rock_registry:Array=props.get_meta("mineable_rock_registry",[])
    if rock_registry.is_empty() or _shape_hits(main.get_world_3d(),rock_registry[0].position)<1:failures.append("ore rock physics query passed through")
    var ore_families:Dictionary={}
    for rock in rock_registry:ore_families[str(rock.get("ore_id",""))]=true
    if ore_families.size()!=4:failures.append("four distinct ore-rock families were not built")
    var capital:Dictionary={}
    for site in main.get("_active_profile").get("town_sites",[]):
        if site.get("capital",false):
            capital=site
            break
    var lamp_point:Vector2=capital.get("position",Vector2.ZERO)+Vector2(14.5,82.0)
    var lamp_ground:Vector3=main.get("_world_result").terrain_height_sampler.call(lamp_point.x,lamp_point.y)
    if _shape_hits(main.get_world_3d(),lamp_ground+Vector3.UP*1.8)<1:failures.append("capital boulevard lamp remained non-solid")
    print("SOLID_WORLD|bush_shapes=%d|rock_shapes=%d|ore_families=%d|town_detail_shapes=%d|failures=%d"%[
        bush_body.get_child_count() if bush_body else 0,
        rock_body.get_child_count() if rock_body else 0,
        ore_families.size(),
        int(detail_body.get_meta("detail_shape_count",0)) if detail_body else 0,
        failures.size(),
    ])
    for failure in failures:push_error("SOLID_WORLD_FAILURE|%s"%failure)
    main.free()
    quit(1 if not failures.is_empty() else 0)
