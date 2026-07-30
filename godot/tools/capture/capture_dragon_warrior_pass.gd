extends SceneTree

var stage:Node3D
var camera:Camera3D

func _initialize()->void:call_deferred("run_capture")

func _light_scene()->void:
    var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.018,.022,.030);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.42,.48,.58);env.ambient_light_energy=.72;environment.environment=env;stage.add_child(environment)
    var sun:=DirectionalLight3D.new();sun.rotation=Vector3(-.75,-.55,0);sun.light_energy=1.3;sun.shadow_enabled=true;stage.add_child(sun)
    camera=Camera3D.new();camera.current=true;camera.fov=52;stage.add_child(camera)

func _save(path:String)->void:
    await RenderingServer.frame_post_draw
    await process_frame
    var image:=root.get_texture().get_image();image.save_png(ProjectSettings.globalize_path(path));print("CAPTURE|%s"%path)

func _make_hero()->CharacterBody3D:
    var hero:=CharacterBody3D.new();hero.name="Player"
    var visual:=Node3D.new();visual.name="Visual";visual.position=Vector3(0,.5,0);visual.set_script(load("res://scripts/HeroVisual.gd"));hero.add_child(visual)
    var pivot:=Node3D.new();pivot.name="CameraPivot";hero.add_child(pivot)
    var spring:=SpringArm3D.new();spring.name="SpringArm3D";pivot.add_child(spring)
    var cam:=Camera3D.new();cam.name="Camera3D";spring.add_child(cam)
    hero.set_script(load("res://scripts/HeroController.gd"));return hero

func run_capture()->void:
    stage=Node3D.new();root.add_child(stage);_light_scene()
    var hero:=_make_hero();hero.position=Vector3(120,0,120);stage.add_child(hero)
    var director:=Node3D.new();director.set_script(load("res://scripts/GameplayDirector.gd"));stage.add_child(director);director.player=hero;director.height_sampler=func(x:float,z:float):return Vector3(x,0,z);director.walkable_sampler=func(_x:float,_z:float):return true
    director._build_cavern_dungeon(Vector3.ZERO,4,"DRAGON CAVERN")
    director.set_process(false)
    hero.position=Vector3(15,0,-45)
    for enemy in director.minions:
        if enemy.get("kind","")=="dragon":
            enemy.node.visible=true
            director._tick_dragon(enemy,0.0,false)
    camera.position=Vector3(15,5.8,-45);camera.look_at(Vector3(0,4.0,-62),Vector3.UP)
    for i in range(8):await process_frame
    await _save("res://artifacts/dragon_boss_room.png")
    director.queue_free();hero.position=Vector3.ZERO
    if hero.active_class!="Warrior":hero.switch_hero_class()
    camera.position=Vector3(1.85,1.75,2.55);camera.look_at(Vector3(0,1.35,0),Vector3.UP)
    var floor:=MeshInstance3D.new();var floor_mesh:=PlaneMesh.new();floor_mesh.size=Vector2(8,8);floor.mesh=floor_mesh;var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.11,.115,.12);floor.material_override=mat;stage.add_child(floor)
    for i in range(8):await process_frame
    await _save("res://artifacts/warrior_class.png")
    quit(0)
