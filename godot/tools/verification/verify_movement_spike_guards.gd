extends SceneTree


func _initialize()->void:
    call_deferred("_verify")


func _verify()->void:
    var failures:=PackedStringArray()
    var director:Node3D=(load("res://scripts/GameplayDirector.gd") as GDScript).new()
    director.process_mode=Node.PROCESS_MODE_DISABLED
    var player:=CharacterBody3D.new()
    root.add_child(player)
    root.add_child(director)
    director.set("player",player)

    var collision_body:=StaticBody3D.new()
    director.add_child(collision_body)
    var shapes:Array[CollisionShape3D]=[]
    for i in range(4):
        var collision:=CollisionShape3D.new()
        collision.disabled=true
        collision_body.add_child(collision)
        shapes.append(collision)
    director.set("_local_prop_collision_body",collision_body)
    director.set("_local_prop_collision_shapes",shapes)
    var tree:Dictionary={"active":true,"position":Vector3(1.0,0.0,1.0),"scale":1.0}
    director.set("_tree_buckets",{Vector2i.ZERO:[tree]})
    director.set("_prop_collision_buckets",{})
    director.call("_refresh_local_prop_collisions",true)
    var original_shape:Shape3D=shapes[0].shape
    if original_shape==null or shapes[0].disabled:
        failures.append("initial collision pool did not activate")

    for step in range(20):
        player.position.x+=.1
        director.call("_refresh_local_prop_collisions")
    if shapes[0].shape!=original_shape:
        failures.append("static movement recreated a collision shape")
    tree.active=false
    director.call("_refresh_local_prop_collisions",true)
    if not shapes[0].disabled:
        failures.append("forced harvest refresh did not remove collision")

    var minimap:Control=(load("res://scripts/Minimap.gd") as GDScript).new()
    minimap.process_mode=Node.PROCESS_MODE_DISABLED
    root.add_child(minimap)
    minimap.call("configure",{},player,null,Callable(self,"_flat_height"))
    for i in range(64):minimap.call("_advance_terrain_refresh",1)
    for i in range(32):minimap.call("_advance_terrain_color_refresh",2)
    var first_texture:ImageTexture=minimap.get("_terrain_texture")
    if first_texture==null:
        failures.append("first minimap texture was not created")
    else:
        minimap.call("_begin_terrain_refresh",Vector2(80.0,0.0))
        for i in range(64):minimap.call("_advance_terrain_refresh",1)
        for i in range(32):minimap.call("_advance_terrain_color_refresh",2)
        if minimap.get("_terrain_texture")!=first_texture:
            failures.append("minimap allocated a replacement texture")

    var world_map:Control=(load("res://scripts/WorldMap.gd") as GDScript).new()
    root.add_child(world_map)
    world_map.visible=false
    world_map.set("_terrain_sample_row",0)
    world_map.call("_process",1.0)
    if int(world_map.get("_terrain_sample_row"))!=0:
        failures.append("hidden world map performed terrain work")

    if failures.is_empty():
        print("MOVEMENT_SPIKE_GUARDS|PASS|collision_shape_reused=true|minimap_texture_reused=true|hidden_world_map_idle=true")
        quit()
    else:
        for failure in failures:push_error(failure)
        print("MOVEMENT_SPIKE_GUARDS|FAIL|%s"%"; ".join(failures))
        quit(1)


func _flat_height(x:float,z:float)->Vector3:
    return Vector3(x,0.0,z)
