extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _make_environment(world:Node3D)->void:
    var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-34,0);sun.light_energy=1.22;sun.shadow_enabled=true;world.add_child(sun)
    var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.38,.62,.78);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.63,.67,.68);environment.ambient_light_energy=.92
    var world_environment:=WorldEnvironment.new();world_environment.environment=environment;world.add_child(world_environment)


func _find_wall(props:Node,kind:String)->Dictionary:
    var stack:Array[Node]=[props]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if not node is MultiMeshInstance3D or str(node.get_meta("mountain_cliff_wall_kind",""))!=kind:continue
        var instance:=node as MultiMeshInstance3D
        if instance.multimesh==null or instance.multimesh.instance_count<1:continue
        var local_transform:=instance.multimesh.get_instance_transform(0)
        var world_transform:=instance.global_transform*local_transform
        return {"position":world_transform.origin,"basis":world_transform.basis}
    return {}


func _run()->void:
    var shots:=[
        {"zone":"starting_realm","kind":"StratifiedMountainWall","file":"mountain_cliff_wall_in_world_v1.png"},
        {"zone":"glacial_range","kind":"GlacialCirqueWall","file":"glacial_cirque_wall_in_world_v1.png"},
    ]
    var failures:=0
    for shot in shots:
        var world:=Node3D.new();root.add_child(world);_make_environment(world)
        for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
            var child:=Node3D.new();child.name=child_name;world.add_child(child)
        var profile:Dictionary=WorldProfile.new().make_zone_profile(str(shot.zone))
        var terrain:Dictionary=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
        var preview:=WorldPreviewBuilder.new();preview.begin_population(world,profile);preview.call("_build_mountain_cliff_walls",world.get_node("PropsRoot"),profile,terrain)
        var wall:=_find_wall(world.get_node("PropsRoot"),str(shot.kind))
        if wall.is_empty():failures+=1;world.free();continue
        var position:Vector3=wall.position
        var basis:Basis=wall.basis
        var front:Vector3=basis.z.normalized()
        var along:Vector3=basis.x.normalized()
        var target:=position+Vector3.UP*10.5
        var camera:=Camera3D.new();camera.current=true;camera.fov=56.0;world.add_child(camera)
        camera.global_position=target+front*112.0+along*18.0+Vector3.UP*27.0
        camera.look_at(target,Vector3.UP)
        var ground:Vector3=(terrain.terrain_height_sampler as Callable).call(position.x,position.z)
        print("MOUNTAIN_CLIFF_CAPTURE_TARGET|zone=%s|kind=%s|placed_y=%.2f|terrain_y=%.2f|delta=%.2f"%[str(shot.zone),str(shot.kind),position.y,ground.y,position.y-ground.y])
        await _settle()
        if await _capture("res://artifacts/%s"%str(shot.file))!=OK:failures+=1
        world.free();await process_frame
    print("MOUNTAIN_CLIFF_CAPTURE|shots=%d|failures=%d"%[shots.size(),failures])
    quit(0 if failures==0 else 1)
