extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const BASILISK_SCENE:PackedScene=preload("res://assets/enemies/ashscale_basilisk_v1.glb")


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
    var plane:=PlaneMesh.new();plane.size=Vector2(30,30);plane.subdivide_width=20;plane.subdivide_depth=20
    floor_mesh.mesh=plane
    var earth:=StandardMaterial3D.new();earth.albedo_color=Color(.34,.30,.19);earth.roughness=.96
    floor_mesh.material_override=earth
    main.add_child(floor_mesh)

    var basilisk:=BASILISK_SCENE.instantiate() as Node3D
    basilisk.name="AshscaleBasiliskReview"
    basilisk.position=Vector3(0,.04,0)
    basilisk.rotation.y=PI+.40
    main.add_child(basilisk)
    for side in ["L","R"]:
        for leg_name in ["F","R"]:
            var pivot:=basilisk.find_child("LegPivot_%s%s"%[side,leg_name],true,false) as Node3D
            if pivot:pivot.rotation.x=(.19 if leg_name=="F" else -.17)*(1.0 if side=="L" else -1.0)
    var jaw:=basilisk.find_child("JawPivot",true,false) as Node3D
    if jaw:jaw.rotation.x=.20
    var tail:=basilisk.find_child("TailPivot_1",true,false) as Node3D
    if tail:tail.rotation.y=-.24

    var camera:=Camera3D.new()
    camera.current=true;camera.fov=46.0
    camera.position=Vector3(7.7,3.0,8.6)
    main.add_child(camera)
    camera.look_at(Vector3(0,.76,0),Vector3.UP)
    for _frame in range(36):await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/ashscale_basilisk_review_v1.png"))
    print("ASHSCALE_BASILISK_REVIEW|error=%d"%error)
    quit(0 if error==OK else 1)
