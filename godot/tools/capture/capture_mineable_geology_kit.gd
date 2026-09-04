extends SceneTree

const KIT := preload("res://assets/world/mineable_geology_kit_v1.glb")
const NAMES := [
    "IronOutcropIntact", "CopperOutcropIntact", "SilverOutcropIntact", "GoldOutcropIntact",
    "IronOutcropDepleted", "CopperOutcropDepleted", "SilverOutcropDepleted", "GoldOutcropDepleted",
]


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var source := KIT.instantiate()
    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(16.0, 8.0)
    var floor := MeshInstance3D.new()
    floor.mesh = floor_mesh
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.18, 0.20, 0.16)
    floor_material.roughness = 1.0
    floor.material_override = floor_material
    world.add_child(floor)

    var failures := 0
    for index in range(NAMES.size()):
        var mesh := _find_mesh(source, NAMES[index])
        if mesh == null:
            failures += 1
            continue
        var instance := MeshInstance3D.new()
        instance.name = NAMES[index]
        instance.mesh = mesh
        var column := index % 4
        var row := index / 4
        instance.position = Vector3(-5.1 + float(column) * 3.4, 0.02, -1.3 + float(row) * 3.0)
        instance.rotation.y = -0.38 + float(column) * 0.19
        world.add_child(instance)
    source.free()

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    world.add_child(sun)
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.34, 0.46, 0.54)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.60, 0.64, 0.67)
    environment.ambient_light_energy = 0.68
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    world.add_child(world_environment)
    var camera := Camera3D.new()
    camera.current = true
    camera.fov = 49.0
    camera.position = Vector3(0.0, 8.3, 12.2)
    world.add_child(camera)
    camera.look_at(Vector3(0.0, 0.35, 0.45), Vector3.UP)
    for _frame in range(18):
        await process_frame
    await RenderingServer.frame_post_draw
    var output := "res://artifacts/mineable_geology_kit_v1.png"
    var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
    print("MINEABLE_GEOLOGY_CAPTURE|meshes=%d|missing=%d|save_error=%d" % [NAMES.size(), failures, error])
    world.free()
    await process_frame
    quit(0 if failures == 0 and error == OK else 1)


func _find_mesh(node: Node, target: String) -> Mesh:
    if node is MeshInstance3D and str(node.name) == target:
        return (node as MeshInstance3D).mesh
    for child in node.get_children():
        var found := _find_mesh(child, target)
        if found != null:
            return found
    return null
