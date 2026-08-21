extends SceneTree

const CANDIDATE := preload("res://assets/hero/hero_full_continuous_correction_candidate.glb")


func _initialize() -> void:
    call_deferred("run_capture")


func run_capture() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(.018, .022, .032)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(.54, .57, .66)
    env.ambient_light_energy = .76
    environment.environment = env
    stage.add_child(environment)
    var key := DirectionalLight3D.new()
    key.rotation = Vector3(-.72, -.58, 0)
    key.light_color = Color(1.0, .84, .72)
    key.light_energy = 1.65
    stage.add_child(key)
    var hero := CANDIDATE.instantiate() as Node3D
    stage.add_child(hero)
    apply_runtime_materials(hero)
    var player := find_animation_player(hero)
    if player == null:
        push_error("Candidate has no AnimationPlayer")
        quit(2)
        return
    var camera := Camera3D.new()
    camera.current = true
    camera.fov = 42
    stage.add_child(camera)
    var reviews := [
        [&"Idle", 0.5, "full_continuous_correction_godot_idle.png", Vector3(2.25, 1.58, 3.40), Vector3(0, .98, 0)],
        [&"Walk", 0.0, "full_continuous_correction_godot_walk_contact.png", Vector3(2.25, 1.58, 3.40), Vector3(0, .98, 0)],
        [&"Walk", 0.24, "full_continuous_correction_godot_walk_passing.png", Vector3(2.25, 1.58, 3.40), Vector3(0, .98, 0)],
        [&"Idle", 0.5, "full_continuous_correction_godot_face.png", Vector3(.62, 1.72, 1.05), Vector3(0, 1.66, 0)],
    ]
    for review in reviews:
        player.play(review[0])
        player.seek(review[1], true)
        camera.position = review[3]
        camera.fov = 34 if String(review[2]).contains("face") else 42
        camera.look_at(review[4], Vector3.UP)
        for index in range(4):
            await process_frame
        await RenderingServer.frame_post_draw
        var output := ProjectSettings.globalize_path("res://artifacts/%s" % review[2])
        var error := root.get_texture().get_image().save_png(output)
        print("CORRECTION_CAPTURE|%s|error=%d" % [output, error])
    quit(0)


func apply_runtime_materials(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        var node_name := String(mesh_node.name)
        var material := StandardMaterial3D.new()
        material.roughness = .84
        if node_name == "ConnectedBody":
            material.albedo_color = Color(.64, .40, .30, 1)
            mesh_node.set_surface_override_material(0, material)
        elif node_name.begins_with("HeroHair") or node_name == "ProfessionalBrows":
            material.albedo_color = Color(.11, .09, .08, 1)
            material.roughness = .78
            mesh_node.set_surface_override_material(0, material)
    for child in node.get_children():
        apply_runtime_materials(child)


func find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := find_animation_player(child)
        if found != null:
            return found
    return null
