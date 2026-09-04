extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=18)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _make_environment(world:Node3D)->void:
    var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.light_energy=1.25;sun.shadow_enabled=true;world.add_child(sun)
    var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.39,.62,.76);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.66,.66,.62);environment.ambient_light_energy=.90
    var world_environment:=WorldEnvironment.new();world_environment.environment=environment;world.add_child(world_environment)


func _find_kind(root_node:Node,kind:String)->Dictionary:
    var stack:Array[Node]=[root_node]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if not node is MultiMeshInstance3D or str(node.get_meta("volcanic_ecology_kind",""))!=kind:continue
        var instance:=node as MultiMeshInstance3D
        if instance.multimesh==null or instance.multimesh.instance_count<1:continue
        var transform:=instance.multimesh.get_instance_transform(0)
        var world_basis:=instance.global_transform.basis*transform.basis
        return {
            "instance":instance,"position":instance.global_transform*transform.origin,
            "normal":world_basis.y.normalized(),"tangent":world_basis.z.normalized(),
        }
    return {}


func _run()->void:
    var world:=Node3D.new();root.add_child(world);_make_environment(world)
    for child_name in ["TerrainRoot","RiverRoot","RoadRoot","BridgeRoot","TownRoot","PropsRoot"]:
        var child:=Node3D.new();child.name=child_name;world.add_child(child)
    var profile:Dictionary=WorldProfile.new().make_zone_profile("east_marches")
    var terrain:Dictionary=TerrainBuilder.new().generate_world(world.get_node("TerrainRoot"),profile)
    var preview:=WorldPreviewBuilder.new();preview.begin_population(world,profile);preview.call("_build_regional_geology",world.get_node("PropsRoot"),profile,terrain)
    var shots:=[
        {"kind":"RopeyLavaShelf","file":"volcanic_lava_shelf_v1.png","lift":.4},
        {"kind":"ObsidianShardCluster","file":"volcanic_obsidian_cluster_v1.png","lift":3.0},
        {"kind":"FumaroleVentCluster","file":"volcanic_vent_cluster_v1.png","lift":1.4},
        {"kind":"CharredVolcanicSnag","file":"volcanic_charred_snag_v1.png","lift":4.8},
        {"kind":"AshScrubCluster","file":"volcanic_ash_scrub_v1.png","lift":1.2},
        {"kind":"FireweedPatch","file":"volcanic_fireweed_patch_v1.png","lift":.65},
    ]
    var failures:=0
    var camera:=Camera3D.new();camera.current=true;camera.fov=52.0;world.add_child(camera)
    for shot in shots:
        var formation:=_find_kind(world.get_node("PropsRoot"),str(shot.kind))
        if formation.is_empty():failures+=1;continue
        var target:Vector3=formation.position+Vector3.UP*float(shot.lift)
        var target_ground:Vector3=(terrain.terrain_height_sampler as Callable).call(formation.position.x,formation.position.z)
        print("VOLCANIC_CAPTURE_TARGET|kind=%s|placed_y=%.2f|terrain_y=%.2f|delta=%.2f"%[str(shot.kind),formation.position.y,target_ground.y,formation.position.y-target_ground.y])
        var camera_offset:=Vector3(22,20,28)
        if str(shot.kind) in ["CharredVolcanicSnag","AshScrubCluster","FireweedPatch"]:camera_offset=Vector3(9,7,12)
        var camera_up:=Vector3.UP
        if str(shot.kind)=="FireweedPatch":
            camera.global_position=target+(formation.normal as Vector3)*12.0+(formation.tangent as Vector3)*10.0
            camera_up=formation.normal as Vector3
        else:camera.global_position=target+camera_offset
        camera.look_at(target,camera_up)
        await _settle(18)
        if await _capture("res://artifacts/%s"%str(shot.file))!=OK:failures+=1
    var apron_point:=Vector2(2680.0,-2380.0)
    var apron_ground:Vector3=(terrain.terrain_height_sampler as Callable).call(apron_point.x,apron_point.y)
    var apron_probe:=36.0
    var apron_left:Vector3=(terrain.terrain_height_sampler as Callable).call(apron_point.x-apron_probe,apron_point.y)
    var apron_right:Vector3=(terrain.terrain_height_sampler as Callable).call(apron_point.x+apron_probe,apron_point.y)
    var apron_near:Vector3=(terrain.terrain_height_sampler as Callable).call(apron_point.x,apron_point.y-apron_probe)
    var apron_far:Vector3=(terrain.terrain_height_sampler as Callable).call(apron_point.x,apron_point.y+apron_probe)
    var apron_normal:=Vector3(apron_left.y-apron_right.y,apron_probe*2.0,apron_near.y-apron_far.y).normalized()
    var apron_tangent:=Vector3(-apron_normal.z,0.0,apron_normal.x).normalized()
    var apron_target:=apron_ground+apron_normal*2.0
    camera.global_position=apron_target+apron_normal*58.0+apron_tangent*105.0
    camera.look_at(apron_target,apron_normal)
    await _settle(18)
    if await _capture("res://artifacts/volcanic_terrain_apron_v1.png")!=OK:failures+=1
    print("VOLCANIC_ECOLOGY_CAPTURE|shots=%d|failures=%d"%[shots.size()+1,failures])
    world.free();await process_frame;quit(0 if failures==0 else 1)
