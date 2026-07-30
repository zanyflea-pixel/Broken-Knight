extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await physics_frame
    var profile:Dictionary=main.get("_active_profile")
    var world_result:Dictionary=main.get("_world_result")
    var capital:Dictionary={}
    for site in profile.get("town_sites",[]):
        if site.get("capital",false):capital=site;break
    var center:Vector2=capital.get("position",Vector2.ZERO)
    var gate:=center+Vector2(0,190)

    var highway:Dictionary={}
    for road in profile.get("road_corridors",[]):
        if road.get("name","")=="Crownspire Highway":highway=road;break
    var highway_points:Array=highway.get("points",[])
    if highway_points.size()<2 or Vector2(highway_points[-2]).distance_to(gate)>.01:
        failures.append("Crownspire Highway does not enter through the south gate")

    var gate_ground:Vector3=world_result.terrain_height_sampler.call(gate.x,gate.y)
    var query:=PhysicsRayQueryParameters3D.create(
        gate_ground+Vector3(0,2.2,18),
        gate_ground+Vector3(0,2.2,-18),
        1
    )
    var gate_hit:=main.get_world_3d().direct_space_state.intersect_ray(query)
    if not gate_hit.is_empty():failures.append("capital gate is still physically blocked")
    var player:=main.get_node("Player") as CharacterBody3D
    if not await _walk_surface(player,world_result,center+Vector2(0,252),center+Vector2(0,145),90):
        failures.append("hero-sized probe cannot walk through the capital gate")

    if not main.find_children("CastleGalleryRamp","MeshInstance3D",true,false).is_empty():
        failures.append("legacy exterior castle stairs remain")

    var ladders:=get_nodes_in_group("climbable_ladder")
    if ladders.is_empty():
        failures.append("castle roof ladder missing")
    else:
        var ladder:=ladders[0] as Node3D
        var bottom:Vector3=ladder.get_meta("climb_bottom",Vector3.ZERO)
        var top:Vector3=ladder.get_meta("climb_top",Vector3.ZERO)
        player.global_position=bottom+Vector3.UP*.06
        for step in range(4):
            player.call("_try_climb_ladder",.75,Vector2(0,-1))
        if player.global_position.y<top.y-.35:
            failures.append("castle roof ladder cannot carry the hero to the roof")
        var top_dismount:Vector3=ladder.get_meta("climb_top_dismount",top)
        if player.global_position.distance_to(top_dismount)>.25:
            failures.append("castle roof ladder did not dismount onto supported roof")
        var ladder_track_distance:=Vector2(player.global_position.x-top.x,player.global_position.z-top.z).length()
        if ladder_track_distance<2.5:
            failures.append("roof dismount remains inside the ladder recapture zone")
        player.call("_process",.20)
        if bool(player.get("_is_airborne")):
            failures.append("hero falls immediately after the roof ladder dismount")
        player.set("_ladder_release_time",0.0)
        for step in range(4):
            player.call("_try_climb_ladder",.75,Vector2(0,1))
        if player.global_position.y>bottom.y+.35:
            failures.append("castle roof ladder cannot carry the hero back down")

    if get_nodes_in_group("castle_roof_lookout").size()!=4:
        failures.append("four accessible roof lookout rooms were not built")
    if get_nodes_in_group("castle_roof_gallery").size()!=4:
        failures.append("connected roof gallery is incomplete")
    if get_nodes_in_group("castle_central_watch").size()!=1:
        failures.append("central roof watch room is missing")
    var roof_doors:=get_nodes_in_group("castle_roof_door")
    if roof_doors.size()!=5:
        failures.append("roof lookout door count is not five")
    else:
        for door_value in roof_doors:
            var door:=door_value as Node3D
            door.rotation.y=-1.62
        await physics_frame
        for door_value in roof_doors:
            var door:=door_value as Node3D
            var building:=door.get_parent() as Node3D
            var center_x:float=door.get_meta("door_center_x",0.0)
            var depth:float=door.get_meta("door_depth",8.5)
            var doorway_start:=building.to_global(Vector3(center_x,1.35,depth*.5+1.15))
            var doorway_end:=building.to_global(Vector3(center_x,1.35,depth*.5-1.15))
            var doorway_query:=PhysicsRayQueryParameters3D.create(doorway_start,doorway_end,1)
            var doorway_hit:=main.get_world_3d().direct_space_state.intersect_ray(doorway_query)
            if not doorway_hit.is_empty():
                failures.append("opened rooftop doorway remains physically blocked")
                break
    var stair_assemblies:=get_nodes_in_group("castle_stair_assembly")
    if stair_assemblies.is_empty() or int(stair_assemblies[0].get_meta("castle_stair_riser_count",0))!=78:
        failures.append("castle stair risers do not close all three flights")

    player.hp=player.max_hp
    player.call("_apply_fall_damage",3.0)
    if player.hp<player.max_hp-.01:failures.append("safe fall caused damage")
    player.call("_apply_fall_damage",8.0)
    if player.hp>=player.max_hp:failures.append("medium fall caused no damage")
    if player.hp<player.max_hp-8.0:failures.append("medium fall damage remains excessive")
    player.hp=player.max_hp
    player.call("_apply_fall_damage",30.0)
    if player.hp>0.0:failures.append("fatal fall did not kill the hero")
    player.hp=player.max_hp

    # Stepping beyond the keep footprint must enter airborne motion at roof
    # height rather than assigning the courtyard height in a single frame.
    var capital_ground_y:float=float(capital.get("ground_height",12.0))
    player.global_position=Vector3(center.x+35.0,capital_ground_y+33.14,center.y-100.0)
    player.set("_is_airborne",false)
    player.call("_process",.10)
    if not bool(player.get("_is_airborne")):
        failures.append("roof edge did not begin a real fall")
    if player.global_position.y<capital_ground_y+24.0:
        failures.append("roof edge still teleported the hero downward")
    for fall_step in range(30):
        player.call("_process",.10)
        if player.hp<=0.0:break
    if player.hp>0.0:failures.append("full castle-roof fall was not fatal")
    player.hp=player.max_hp
    player.set("_dead",false)

    var castle_ground:Vector3=world_result.terrain_height_sampler.call(center.x,center.y-92.0)
    var keep_center:=Vector2(castle_ground.x,castle_ground.z-8.0)
    var stairs_clear:=true
    for floor_index in range(3):
        var reverse:=floor_index%2==1
        var stair_x:=10.0 if not reverse else 18.0
        var start_z:=-8.2 if reverse else 16.2
        var end_z:=16.2 if reverse else -8.2
        var stair_start:=keep_center+Vector2(stair_x,start_z)
        # Walk beyond the final tread onto the actual storey. Stopping the
        # probe on the ramp endpoint missed the former unsupported floor gap.
        var landing_z:=20.5 if reverse else -12.5
        var stair_end:=keep_center+Vector2(stair_x,landing_z)
        var base_y:=castle_ground.y+float(floor_index)*8.0+(.21 if floor_index>0 else 0.0)
        player.global_position=Vector3(stair_start.x,base_y+.06,stair_start.y)
        if not await _walk_surface(player,world_result,stair_start,stair_end,112):
            stairs_clear=false
            failures.append("castle stair flight %d cannot reach its floor landing"%(floor_index+1))
        var target_y:=castle_ground.y+float(floor_index+1)*8.0+.21
        if absf(player.global_position.y-(target_y+float(player.get("hover_height"))))>.34:
            stairs_clear=false
            failures.append("castle stair flight %d drops or teleports at its landing"%(floor_index+1))
    if not stairs_clear:push_error("CASTLE_STAIR_PROBE|blocked")

    var builder:RefCounted=load("res://scripts/world/WorldPreviewBuilder.gd").new()
    if not builder.call("_is_on_stone_walkway",center+Vector2(0,120),profile):
        failures.append("capital boulevard is not protected from vegetation")
    if not builder.call("_is_on_stone_walkway",center+Vector2(0,-92),profile):
        failures.append("castle courtyard is not protected from vegetation")

    var tree_meshes:Dictionary=builder.call("_get_realistic_tree_meshes")
    for species in ["oak","birch","maple","pine"]:
        var species_meshes:Dictionary=builder.call("_get_tree_species_meshes",species)
        for key in ["trunk","branches","leaves"]:
            if species_meshes.get(key)==null:
                failures.append("Blender %s %s mesh missing"%[species,key])
    var leaf_mesh:=tree_meshes.get("leaves") as Mesh
    var leaf_vertices:=0
    if leaf_mesh:
        for surface in range(leaf_mesh.get_surface_count()):
            leaf_vertices+=(leaf_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    if leaf_vertices<3000:failures.append("realistic tree leaf model is too sparse")

    var props:=main.get_node("WorldRoot/PropsRoot")
    var realistic_tree_found:=false
    var species_counts:Dictionary={"oak":0,"birch":0,"maple":0,"pine":0}
    var site_overlap_count:=0
    for tree in props.get_meta("harvestable_tree_registry",[]):
        var species:String=tree.get("species","")
        if species_counts.has(species):
            species_counts[species]+=1
        if species!="" and tree.get("batched_parts",[]).size()==3:
            realistic_tree_found=true
        var tree_position:Vector3=tree.get("position",Vector3.ZERO)
        if builder.call("_tree_overlaps_authored_site",Vector2(tree_position.x,tree_position.z),profile,7.5):
            site_overlap_count+=1
    if not realistic_tree_found:failures.append("Blender tree is not registered for chopping")
    for species in species_counts:
        if species_counts[species]<=0:
            failures.append("Blender %s trees are not distributed in the world"%species)
    if site_overlap_count>0:
        failures.append("%d trees overlap town, camp, or spawn structures"%site_overlap_count)

    print("CASTLE_TREE_PASS|highway_gate=%s|gate_clear=%s|exterior_ramps=%d|ladders=%d|leaf_vertices=%d|species=%s|site_overlaps=%d|choppable=%s|failures=%d"%[
        highway_points.size()>=2 and Vector2(highway_points[-2]).distance_to(gate)<=.01,
        gate_hit.is_empty(),
        main.find_children("CastleGalleryRamp","MeshInstance3D",true,false).size(),
        ladders.size(),
        leaf_vertices,
        str(species_counts),
        site_overlap_count,
        realistic_tree_found,
        failures.size(),
    ])
    for failure in failures:push_error("CASTLE_TREE_FAILURE|%s"%failure)
    main.free()
    quit(1 if not failures.is_empty() else 0)


func _walk_surface(player:CharacterBody3D,world_result:Dictionary,start:Vector2,finish:Vector2,steps:int)->bool:
    var start_ground:Vector3=world_result.height_sampler.call(start.x,start.y)
    if player.global_position.distance_to(Vector3(start.x,player.global_position.y,start.y))>1.0:
        player.global_position=start_ground+Vector3.UP*.06
    await physics_frame
    for index in range(1,steps+1):
        var point:=start.lerp(finish,float(index)/float(steps))
        var next:=Vector3(point.x,player.global_position.y,point.y)
        var motion:=Vector3(next.x-player.global_position.x,0,next.z-player.global_position.z)
        var current_ground:float=player.call("_authored_step_height",player.global_position)
        var next_ground:float=player.call("_authored_step_height",next)
        var rise:=next_ground-current_ground
        var test_transform:=player.global_transform
        var blocked:=player.test_move(test_transform,motion)
        if blocked and rise>.025 and rise<=.46:
            test_transform=test_transform.translated(Vector3.UP*(rise+.08))
            blocked=player.test_move(test_transform,motion)
            if not blocked:player.global_position.y+=rise+.08
        if blocked:
            var collision:=player.move_and_collide(motion,true)
            print("CASTLE_WALK_BLOCK|step=%d|point=%s|rise=%.3f|y=%.3f|collider=%s"%[
                index,point,rise,player.global_position.y,
                str(collision.get_collider().name) if collision and collision.get_collider() else "unknown",
            ])
            return false
        player.global_position.x=next.x
        player.global_position.z=next.z
        player.global_position=player.call("_resolve_ground_position",player.global_position)
        await physics_frame
    return true
