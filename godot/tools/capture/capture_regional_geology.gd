extends SceneTree

const TerrainBuilder=preload("res://scripts/world/TerrainBuilder.gd")
const WorldPreviewBuilder=preload("res://scripts/world/WorldPreviewBuilder.gd")
const WorldProfile=preload("res://scripts/world/WorldProfile.gd")
const GEOLOGY_KIT=preload("res://assets/world/regional_geology_kit_v1.glb")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=18)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _find_formation(props:Node,kind:String)->Dictionary:
    var stack:Array[Node]=[props]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if not node is MultiMeshInstance3D or str(node.get_meta("regional_geology_kind",""))!=kind:continue
        var instance:=node as MultiMeshInstance3D
        if instance.multimesh==null or instance.multimesh.instance_count<1:continue
        var transform:=instance.multimesh.get_instance_transform(0)
        return {"node":instance,"position":instance.global_transform*transform.origin,"scale":transform.basis.get_scale()}
    return {}


func _make_review_environment(world:Node3D)->void:
    var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-28,0);sun.light_energy=1.35;sun.shadow_enabled=true;world.add_child(sun)
    var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.43,.66,.79);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.62,.69,.73);environment.ambient_light_energy=1.0
    var world_environment:=WorldEnvironment.new();world_environment.environment=environment;world.add_child(world_environment)


func _run()->void:
    var shots:=[
        {"kind":"LayeredCliffFace","file":"geology_layered_cliff_v1.png"},
        {"kind":"BasaltColumnEscarpment","file":"geology_basalt_columns_v1.png"},
        {"kind":"GlacialCrownCrag","file":"geology_glacial_crag_v1.png"},
        {"kind":"CoastalSeaStack","file":"geology_coastal_stack_v1.png"},
        {"kind":"StratifiedMountainWall","file":"geology_stratified_mountain_wall_v1.png"},
        {"kind":"GlacialCirqueWall","file":"geology_glacial_cirque_wall_v1.png"},
    ]
    var failures:=0
    for shot in shots:
        var world:=Node3D.new();root.add_child(world);_make_review_environment(world)
        var kit:=GEOLOGY_KIT.instantiate()
        var source:=kit.find_child(str(shot.kind),true,false) as MeshInstance3D
        if source==null or source.mesh==null:
            failures+=1;world.free();continue
        var display:=MeshInstance3D.new();display.mesh=source.mesh;display.transform=source.transform;world.add_child(display)
        kit.free()
        var bounds:=display.mesh.get_aabb()
        var target:=display.global_transform*(bounds.position+bounds.size*.5)
        var extent:=maxf(8.0,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)))
        var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(maxf(70.0,extent*2.4),maxf(70.0,extent*2.4));ground.mesh=plane
        var ground_material:=StandardMaterial3D.new();ground_material.albedo_color=Color(.24,.31,.18);ground_material.roughness=1.0;ground.material_override=ground_material;world.add_child(ground)
        var camera:=Camera3D.new();camera.current=true;camera.fov=55.0;world.add_child(camera)
        camera.global_position=target+Vector3(extent*.78,extent*.62,extent*1.18)
        camera.look_at(target,Vector3.UP)
        await _settle(20)
        if await _capture("res://artifacts/%s"%str(shot.file))!=OK:failures+=1
        world.free();await process_frame
    print("REGIONAL_GEOLOGY_CAPTURE|shots=%d|failures=%d"%[shots.size(),failures])
    quit(0 if failures==0 else 1)
