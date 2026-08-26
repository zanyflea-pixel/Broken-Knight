extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const RIMECRAWLER_SCENE:PackedScene=preload("res://assets/enemies/rimecrawler_v1.glb")
const RIME_CHITIN_SCENE:PackedScene=preload("res://assets/items/rime_chitin_pickup_v1.glb")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    main.process_mode=Node.PROCESS_MODE_ALWAYS
    main._configure_world_lighting()
    main.get_node("UI").visible=false
    main.get_node("WorldRoot").visible=false
    main.get_node("Player").visible=false

    var floor_mesh:=MeshInstance3D.new()
    var plane:=PlaneMesh.new();plane.size=Vector2(28,28);plane.subdivide_width=18;plane.subdivide_depth=18
    floor_mesh.mesh=plane
    var snow:=StandardMaterial3D.new();snow.albedo_color=Color(.54,.60,.59);snow.roughness=.94
    floor_mesh.material_override=snow
    main.add_child(floor_mesh)

    var crawler:=RIMECRAWLER_SCENE.instantiate() as Node3D
    crawler.name="RimecrawlerReview"
    crawler.position=Vector3(0,.04,0)
    crawler.rotation.y=PI+.38
    main.add_child(crawler)
    # Freeze one side of the gait forward so the six independent legs are
    # visible in a still image instead of visually collapsing into three pairs.
    for side in ["L","R"]:
        for leg_index in range(3):
            var pivot:=crawler.find_child("LegPivot_%s%d"%[side,leg_index],true,false) as Node3D
            if pivot:pivot.rotation.x=sin(float(leg_index)*1.72+(0.0 if side=="L" else PI))*.24

    for index in range(3):
        var pickup:=RIME_CHITIN_SCENE.instantiate() as Node3D
        pickup.scale=Vector3.ONE*.82
        pickup.position=Vector3(-2.4+index*.72,.025,1.25+sin(float(index))*0.28)
        pickup.rotation.y=-.35+float(index)*.58
        main.add_child(pickup)

    var camera:=Camera3D.new()
    camera.current=true;camera.fov=48.0
    camera.position=Vector3(7.4,3.15,7.8)
    main.add_child(camera)
    camera.look_at(Vector3(0,.78,0),Vector3.UP)
    for _frame in range(32):await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/rimecrawler_review_v1.png"))
    print("RIMECRAWLER_REVIEW|error=%d"%error)
    quit(0 if error==OK else 1)
