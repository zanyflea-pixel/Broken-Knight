extends SceneTree


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var stage:=Node3D.new();root.add_child(stage)
    var world_environment:=WorldEnvironment.new();var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.40,.60,.74)
    environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(.73,.78,.82);environment.ambient_light_energy=.68
    world_environment.environment=environment;stage.add_child(world_environment)
    var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(16,12);floor.mesh=plane
    var ground:=StandardMaterial3D.new();ground.albedo_color=Color(.22,.31,.16);ground.roughness=.96;floor.material_override=ground;stage.add_child(floor)
    var placements:=[
        ["res://assets/animals/highland_deer_v1.glb",Vector3(-2.45,0,.25),.82],
        ["res://assets/animals/highland_hare_v1.glb",Vector3(.65,0,-.10),.70],
        ["res://assets/animals/highland_grouse_v1.glb",Vector3(2.45,0,-.12),.76],
    ]
    for placement in placements:
        var animal:Node3D=(load(placement[0]) as PackedScene).instantiate();animal.position=placement[1];animal.scale=Vector3.ONE*float(placement[2]);stage.add_child(animal)
    var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-28,0);sun.light_energy=1.12;sun.shadow_enabled=true;stage.add_child(sun)
    var fill:=OmniLight3D.new();fill.position=Vector3(-3,3,-4);fill.light_energy=1.4;fill.omni_range=14;fill.shadow_enabled=false;stage.add_child(fill)
    var camera:=Camera3D.new();camera.position=Vector3(7.8,3.7,-9.2);camera.fov=43;camera.current=true;stage.add_child(camera);camera.look_at(Vector3(-.1,1.25,0),Vector3.UP)
    for frame in range(12):await process_frame
    await RenderingServer.frame_post_draw
    var output:="res://artifacts/wildlife_expansion_v1.png"
    root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
    print("WILDLIFE_CAPTURE|%s"%output)
    quit(0)
