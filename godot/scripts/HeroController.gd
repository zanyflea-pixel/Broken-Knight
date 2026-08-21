extends CharacterBody3D

signal environment_damage_requested(amount: float, source: String)

@export var walk_speed := 5.2
@export var sprint_speed := 8.5
@export var mounted_walk_speed := 14.0
@export var mounted_sprint_speed := 21.0
@export var mounted_acceleration := 24.0
@export var mounted_deceleration := 28.0
@export var roll_speed := 10.8
@export var roll_duration := 0.75
@export var roll_recovery := 0.28
@export var acceleration := 15.0
@export var deceleration := 19.0
@export var jump_velocity := 6.2
@export var gravity := 17.0
@export var safe_fall_distance := 5.0
@export var fatal_fall_distance := 30.0
@export var mouse_sensitivity := 0.0035
@export var camera_pitch_min := -1.1
@export var camera_pitch_max := 0.45
@export var camera_zoom_min := 2.2
@export var camera_zoom_max := 9.0
@export var camera_zoom_step := 0.6
@export var turn_lerp := 10.0
@export var hover_height := 0.06
@export var hero_level := 1
@export var hero_gold := 4
@export var hero_name := "Knight"
@export var hero_title := "Penniless Sellsword"
@export var max_hp := 112.0
@export var hp := 112.0
@export var max_mana := 34.0
@export var mana := 34.0
@export var max_stamina := 100.0
@export var stamina := 100.0
@export var relic_shards := 0
@export var relic_target := 3
@export var hero_xp := 0
@export var next_xp := 25
@export var health_potions := 2
@export var mana_potions := 1
@export var herbs := 0
@export var scrap := 0
@export var ore := 0
@export var essence := 0
@export var logs := 0
@export var leather := 0
@export var cloth := 0
@export var stone := 0
@export var resin := 0
@export var mushrooms := 0
@export var crystal := 0
@export var grave_tokens := 0
@export var plague_samples := 0
@export var enemies_defeated := 0
@export var elites_defeated := 0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _visual: Node3D = $Visual

var _yaw := 0.0
var _pitch := -0.35
var _height_sampler: Callable
var _walkable_sampler: Callable
var _structure_height_sampler: Callable
var _spawn_position := Vector3.ZERO
var _input_enabled := true
var _current_move_speed := 0.0
var _last_move_dir := Vector3.FORWARD
var _vertical_velocity := 0.0
var _is_airborne := false
var _fall_peak_y := 0.0
var _jump_was_down := false
var _roll_was_down := false
var _roll_time := 0.0
var _roll_cooldown := 0.0
var _roll_dir := Vector3.FORWARD
var _interior_mode := false
var _active_ladder:Node3D
var _climbable_ladders:Array[Node3D]=[]
var _ladder_release_time:=0.0
var _released_ladder:Node3D
var _released_ladder_at_top:=false
var active_class := "Warrior"
var bag_slots: Array = []
var equipped_armor: Dictionary = {}
var equipment_slots := {"head":{},"chest":{},"shoulders":{},"hands":{},"feet":{},"pants":{},"mainhand":{},"offhand":{}}
var base_max_hp := 112.0
var base_max_mana := 34.0
var _dead:=false
var _death_time:=0.0
var food_buff_name:=""
var food_buff_time:=0.0
var food_power_bonus:=0
var food_health_regen:=0.0
var food_stamina_regen:=0.0
var _mounted:=false
var _mount_node:Node3D
var _mount_original_parent:Node
var _camera_pivot_base_position:=Vector3.ZERO
var _spring_arm_base_length:=0.0
var _visual_base_position:=Vector3.ZERO


func _ready() -> void:
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    _yaw = rotation.y
    _camera_pivot.rotation.x = _pitch
    _camera_pivot.rotation.y = _yaw
    _camera_pivot_base_position=_camera_pivot.position
    _spring_arm_base_length=_spring_arm.spring_length
    _visual_base_position=_visual.position
    base_max_hp = max_hp
    base_max_mana = max_mana
    give_knight_armor()
    give_royal_staff()
    give_travel_torch()
    give_royal_warrior_weapons()
    give_starter_axe()
    give_starter_pickaxe()
    give_starter_fishing_pole()
    # New heroes begin as a combat-ready Warrior. Keep the shield in the
    # offhand because the Warrior's defensive abilities require it, while the
    # sword remains the visible/default main-hand weapon.
    _equip_loadout_item("royal_vanguard_sword", "mainhand")
    _equip_loadout_item("royal_vanguard_shield", "offhand")


func configure_world(height_sampler: Callable, spawn_position: Vector3, walkable_sampler: Callable = Callable(), structure_height_sampler: Callable = Callable()) -> void:
    _height_sampler = height_sampler
    _walkable_sampler = walkable_sampler
    _structure_height_sampler = structure_height_sampler
    _spawn_position = spawn_position
    _climbable_ladders.clear()
    _active_ladder=null
    global_position = _resolve_ground_position(spawn_position)


func set_input_enabled(enabled: bool) -> void:
    _input_enabled = enabled
    if not enabled:
        _roll_time = 0.0
        _roll_was_down = false
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func set_interior_mode(enabled: bool) -> void:
    if enabled and _mounted:
        dismount_horse()
    _interior_mode = enabled
    _vertical_velocity = 0.0
    _is_airborne = false
    _fall_peak_y = global_position.y


func is_interior_mode()->bool:return _interior_mode


func is_mounted()->bool:return _mounted and is_instance_valid(_mount_node)


func mount_horse(horse:Node3D)->bool:
    if _mounted or not is_instance_valid(horse) or bool(horse.get_meta("mounted",false)):
        return false
    _mounted=true
    _mount_node=horse
    _mount_original_parent=horse.get_parent()
    horse.set_meta("mounted",true)
    horse.reparent(self,false)
    horse.position=Vector3.ZERO
    horse.rotation=Vector3(0.0,_visual.rotation.y,0.0)
    if horse.has_method("set_mounted_state"):horse.set_mounted_state(true)
    _visual.position=_visual_base_position+Vector3.UP*.72
    _camera_pivot.position=_camera_pivot_base_position+Vector3.UP*.78
    _spring_arm.spring_length=minf(camera_zoom_max,_spring_arm_base_length+1.25)
    _roll_time=0.0
    _vertical_velocity=0.0
    _is_airborne=false
    if _visual.has_method("set_mounted"):_visual.set_mounted(true)
    return true


func dismount_horse()->bool:
    if not _mounted:
        return false
    var horse:=_mount_node
    _mounted=false
    _mount_node=null
    if is_instance_valid(horse):
        var forward:=get_combat_forward()
        var right:=Vector3.UP.cross(forward).normalized()
        var dismount_position:=_resolve_ground_position(global_position+right*1.85-forward*.35)
        var destination_parent:=_mount_original_parent if is_instance_valid(_mount_original_parent) else get_parent()
        horse.reparent(destination_parent,true)
        horse.global_position=dismount_position
        horse.global_rotation=Vector3(0.0,_visual.global_rotation.y,0.0)
        horse.set_meta("mounted",false)
        if horse.has_method("set_mounted_state"):horse.set_mounted_state(false)
    _mount_original_parent=null
    _camera_pivot.position=_camera_pivot_base_position
    _spring_arm.spring_length=_spring_arm_base_length
    _visual.position=_visual_base_position
    if _visual.has_method("set_mounted"):_visual.set_mounted(false)
    return true


func _input(event: InputEvent) -> void:
    if not _input_enabled:
        return
    if event is InputEventKey and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
        # Arrow keys are movement controls in play mode. Consume their press and
        # repeat events here so Godot's UI focus navigation does not also walk
        # the large HUD/menu control tree while the key is held.
        get_viewport().set_input_as_handled()
        return
    if event is InputEventMouseButton:
        if event.pressed:
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                _spring_arm.spring_length = clampf(
                    _spring_arm.spring_length - camera_zoom_step,
                    camera_zoom_min,
                    camera_zoom_max
                )
                get_viewport().set_input_as_handled()
                return
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                _spring_arm.spring_length = clampf(
                    _spring_arm.spring_length + camera_zoom_step,
                    camera_zoom_min,
                    camera_zoom_max
                )
                get_viewport().set_input_as_handled()
                return
    if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
        _yaw -= event.relative.x * mouse_sensitivity
        _pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, camera_pitch_min, camera_pitch_max)
        _camera_pivot.rotation.x = _pitch
        _camera_pivot.rotation.y = _yaw
        get_viewport().set_input_as_handled()
        return


func _process(delta: float) -> void:
    if food_buff_time>0.0:
        food_buff_time=maxf(0.0,food_buff_time-delta)
        hp=minf(max_hp,hp+food_health_regen*delta)
        stamina=minf(max_stamina,stamina+food_stamina_regen*delta)
        if food_buff_time<=0.0:
            food_buff_name="";food_power_bonus=0;food_health_regen=0.0;food_stamina_regen=0.0
    if hp<=0.0 and not _dead:_begin_death()
    if _dead:
        _death_time-=delta
        _current_move_speed=0.0
        if _death_time<=0.0:_respawn_after_death()
        return
    if not _input_enabled:
        return
    if is_warrior():
        stamina=minf(max_stamina,stamina+18.0*delta)
    # Surface teleports must never retain dungeon floor mode. A stale interior
    # flag made the current Y position become its own "ground", which explains
    # both falling through Crownspire outskirts and repeated skyward jumping.
    if _interior_mode and global_position.x<7000.0:
        set_interior_mode(false)

    var input_dir := _get_input_vector()
    _ladder_release_time=maxf(0.0,_ladder_release_time-delta)
    if not _mounted and _try_climb_ladder(delta,input_dir):
        return
    var move_basis := Basis(Vector3.UP, _yaw)
    var move_dir: Vector3 = (move_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

    var has_move_input := move_dir.length_squared() > 0.001
    _roll_cooldown=maxf(0.0,_roll_cooldown-delta)
    var jump_down := Input.is_key_pressed(KEY_SPACE)
    if not _mounted and jump_down and not _jump_was_down and not _is_airborne:
        _start_jump()
    _jump_was_down = jump_down
    var roll_down:=Input.is_key_pressed(KEY_CTRL)
    if not _mounted and roll_down and not _roll_was_down and not _is_airborne and _roll_time<=0.0 and _roll_cooldown<=0.0:
        _start_roll(move_dir if has_move_input else _last_move_dir)
    _roll_was_down=roll_down
    var rolling:=_roll_time>0.0
    var roll_phase:=1.0-clampf(_roll_time/maxf(.01,roll_duration),0.0,1.0)
    var roll_travel_speed:=roll_speed*(.72+.28*sin(roll_phase*PI))
    if rolling:
        _roll_time=maxf(0.0,_roll_time-delta)
        _current_move_speed=0.0
    else:
        var active_walk_speed:=mounted_walk_speed if _mounted else walk_speed
        var active_sprint_speed:=mounted_sprint_speed if _mounted else sprint_speed
        var target_speed:float=(active_sprint_speed if Input.is_key_pressed(KEY_SHIFT) else active_walk_speed) if has_move_input else 0.0
        var active_acceleration:=mounted_acceleration if _mounted else acceleration
        var active_deceleration:=mounted_deceleration if _mounted else deceleration
        var speed_change:=active_acceleration if target_speed>_current_move_speed else active_deceleration
        _current_move_speed=move_toward(_current_move_speed,target_speed,speed_change*delta)
        if has_move_input:_last_move_dir=move_dir
    if _visual.has_method("set_move_blend"):
        _visual.set_move_blend(0.0 if _mounted else clampf(_current_move_speed / walk_speed, 0.0, 1.0))
    if _visual.has_method("set_movement_speed"):
        _visual.set_movement_speed(0.0 if _mounted else _current_move_speed)
    if rolling:
        _turn_visual_toward(_roll_dir,delta*2.5)
    elif has_move_input:
        _turn_visual_toward(move_dir, delta)
    if _mounted and is_instance_valid(_mount_node):
        _mount_node.rotation=Vector3(0.0,_visual.rotation.y,0.0)
        if _mount_node.has_method("set_travel_speed"):_mount_node.set_travel_speed(_current_move_speed)

    var travel_speed:=roll_travel_speed if rolling else _current_move_speed
    if travel_speed > 0.001:
        var travel_dir := _roll_dir if rolling else (move_dir if has_move_input else _last_move_dir)
        var next_position: Vector3 = global_position + travel_dir * travel_speed * delta
        var step_motion:=Vector3(next_position.x-global_position.x,0.0,next_position.z-global_position.z)
        var is_walkable: bool = _interior_mode or not _walkable_sampler.is_valid() or bool(_walkable_sampler.call(next_position.x, next_position.z))
        if is_walkable:
            var blocked := test_move(global_transform, step_motion)
            if blocked:
                # Auto-step only when the sampled walking surface rises by a
                # genuine low stair amount. Visual props are not sampled
                # terrain, so boxes and fences require an intentional jump.
                # Exterior auto-step follows authored terrain/road height only;
                # ray hits on crate tops must not masquerade as walkable ground.
                # Interior stairs still use the resolved architectural surface.
                var current_ground:=_authored_step_height(global_position)
                var next_ground:=_authored_step_height(next_position)
                var ground_rise:=next_ground-current_ground
                if ground_rise>.025 and ground_rise<=.46:
                    var raised_transform:=global_transform.translated(Vector3.UP*(ground_rise+.08))
                    blocked=test_move(raised_transform,step_motion)
            if not blocked:
                global_position.x = next_position.x
                global_position.z = next_position.z

    var ground_position := _resolve_ground_position(global_position)
    if not is_finite(global_position.y):
        environment_damage_requested.emit(max_hp, "fall")
        global_position = ground_position
        _vertical_velocity = 0.0
        _is_airborne = false
        return
    # Losing the support beneath the hero now begins a real fall. Previously,
    # the surface sampler immediately assigned the lower ground height, making
    # roof and cliff drops look like downward teleports.
    if not _is_airborne and global_position.y-ground_position.y>.62:
        _is_airborne=true
        _vertical_velocity=minf(_vertical_velocity,0.0)
        _fall_peak_y=global_position.y
    if _is_airborne:
        _vertical_velocity -= gravity * delta
        global_position.y += _vertical_velocity * delta
        _fall_peak_y=maxf(_fall_peak_y,global_position.y)
        if _vertical_velocity <= 0.0 and global_position.y <= ground_position.y:
            var fall_distance:=maxf(0.0,_fall_peak_y-ground_position.y)
            global_position.y = ground_position.y
            _vertical_velocity = 0.0
            _is_airborne = false
            _apply_fall_damage(fall_distance)
            if _visual.has_method("play_land"):
                _visual.play_land()
    else:
        global_position.y = ground_position.y

    if Input.is_key_pressed(KEY_R):
        global_position = _resolve_ground_position(_spawn_position)
        _vertical_velocity = 0.0
        _is_airborne = false


func _start_jump() -> void:
    _is_airborne = true
    _vertical_velocity = jump_velocity
    _fall_peak_y = global_position.y
    if _visual.has_method("play_jump"):
        _visual.play_jump()


func _apply_fall_damage(fall_distance:float)->void:
    if fall_distance<=safe_fall_distance:
        return
    if fall_distance>=fatal_fall_distance:
        environment_damage_requested.emit(max_hp, "fatal_fall")
        return
    # Ordinary ledge and floor-to-floor falls should hurt without erasing most
    # of the health bar. Only a genuinely extreme drop is an instant death.
    var damage:=minf(max_hp*.72,(fall_distance-safe_fall_distance)*2.0)
    environment_damage_requested.emit(damage, "fall")


func _authored_step_height(position:Vector3)->float:
    if not _height_sampler.is_valid():return position.y
    var result:=float(_height_sampler.call(position.x,position.z).y)+hover_height
    # Castle stairs are outside dungeon interior mode but are still authored
    # walking surfaces. Consult only the explicit structure sampler here; ray
    # hits from crates and scenery must never become automatic steps.
    if _structure_height_sampler.is_valid():
        var structure_y:float=_structure_height_sampler.call(position.x,position.z,position.y)
        if structure_y>-INF:result=maxf(result,structure_y+hover_height)
    return result


func _try_climb_ladder(delta:float,input_dir:Vector2)->bool:
    if _ladder_release_time>0.0:
        return false
    if is_instance_valid(_released_ladder):
        var released_mount:Vector3=_released_ladder.get_meta(
            "climb_top_dismount" if _released_ladder_at_top else "climb_bottom_dismount",
            _released_ladder.global_position
        )
        var released_distance:=Vector2(
            global_position.x-released_mount.x,
            global_position.z-released_mount.z
        ).length()
        if released_distance>4.6:
            _released_ladder=null
        else:
            # Continue away from the endpoint without being recaptured. The
            # opposite input deliberately re-engages the same ladder, making
            # descent from the roof available without pixel-perfect approach.
            var moving_away:=input_dir.y<-.1 if _released_ladder_at_top else input_dir.y>.1
            var reversing:=input_dir.y>.1 if _released_ladder_at_top else input_dir.y<-.1
            if reversing:
                _released_ladder=null
            elif moving_away or absf(input_dir.y)<=.1:
                return false
    if not is_instance_valid(_active_ladder):
        _active_ladder=null
        var nearest_distance:=INF
        if _climbable_ladders.is_empty():
            for ladder_value in get_tree().get_nodes_in_group("climbable_ladder"):
                if ladder_value is Node3D:_climbable_ladders.append(ladder_value)
        for ladder in _climbable_ladders:
            if not is_instance_valid(ladder):continue
            var bottom:Vector3=ladder.get_meta("climb_bottom",ladder.global_position)
            var top:Vector3=ladder.get_meta("climb_top",bottom+Vector3.UP*8.0)
            if global_position.y<bottom.y-1.0 or global_position.y>top.y+1.25:continue
            var height_ratio:=clampf((global_position.y-bottom.y)/maxf(.01,top.y-bottom.y),0.0,1.0)
            var track:=bottom.lerp(top,height_ratio)
            var horizontal_distance:=Vector2(global_position.x-track.x,global_position.z-track.z).length()
            # The upper mount sits in a roof hatch. Its wider capture radius
            # lets a player standing on the roof deliberately press backward
            # to descend without being pixel-perfect over a rung.
            var capture_radius:=4.15 if height_ratio>.82 else 1.65
            if horizontal_distance<capture_radius and horizontal_distance<nearest_distance:
                nearest_distance=horizontal_distance
                _active_ladder=ladder
        # Merely walking beside a ladder should not capture movement.
        if _active_ladder==null or absf(input_dir.y)<.1:
            _active_ladder=null
            return false
    var bottom:Vector3=_active_ladder.get_meta("climb_bottom",_active_ladder.global_position)
    var top:Vector3=_active_ladder.get_meta("climb_top",bottom+Vector3.UP*8.0)
    var climb_direction:float=-input_dir.y
    var progress:=clampf((global_position.y-bottom.y)/maxf(.01,top.y-bottom.y),0.0,1.0)
    if absf(climb_direction)>.1:
        progress=clampf(progress+climb_direction*3.6*delta/maxf(.01,top.y-bottom.y),0.0,1.0)
    global_position=bottom.lerp(top,progress)+Vector3.UP*hover_height
    _vertical_velocity=0.0
    _is_airborne=false
    _current_move_speed=walk_speed*.48 if absf(climb_direction)>.1 else 0.0
    _visual.rotation.y=lerp_angle(_visual.rotation.y,PI,clampf(delta*8.0,0.0,1.0))
    if _visual.has_method("set_move_blend"):
        _visual.set_move_blend(.48 if absf(climb_direction)>.1 else 0.0)
    if progress>=.999 and climb_direction>0.0:
        # The ladder itself terminates inside the open hatch. Step across the
        # lip onto the authored roof surface before releasing ladder control;
        # otherwise the ground sampler correctly sees empty space and starts a
        # fall before the player can move.
        global_position=_active_ladder.get_meta("climb_top_dismount",top+Vector3(0,hover_height,-3.4))
        _released_ladder=_active_ladder
        _released_ladder_at_top=true
        _active_ladder=null
        _ladder_release_time=.12
    elif progress<=.001 and climb_direction<0.0:
        global_position=_active_ladder.get_meta("climb_bottom_dismount",bottom+Vector3.UP*hover_height)
        _released_ladder=_active_ladder
        _released_ladder_at_top=false
        _active_ladder=null
        _ladder_release_time=.12
    return true


func _start_roll(direction:Vector3)->void:
    if direction.length_squared()<=.001:direction=_last_move_dir
    _roll_dir=Vector3(direction.x,0.0,direction.z).normalized()
    _last_move_dir=_roll_dir
    _roll_time=roll_duration
    _roll_cooldown=roll_duration+roll_recovery
    if _visual.has_method("play_roll"):_visual.play_roll()


func _begin_death()->void:
    if _mounted:dismount_horse()
    _dead=true;_death_time=2.75;_input_enabled=false;_roll_time=0.0;_vertical_velocity=0.0
    if _visual.has_method("play_death"):_visual.play_death()


func _respawn_after_death()->void:
    hp=max_hp;mana=max_mana;stamina=max_stamina;_dead=false;_input_enabled=true
    set_interior_mode(false);global_position=_resolve_ground_position(_spawn_position)
    _active_ladder=null;_released_ladder=null
    _fall_peak_y=global_position.y
    if _visual.has_method("reset_death"):_visual.reset_death()


func capture_face_inspection_sheet() -> String:
    return await _capture_head_sheet("hero_face_sheet.png", [
        {"yaw": _visual.global_rotation.y + PI, "pitch": -0.05, "zoom": 1.82, "crop": 340},
        {"yaw": _visual.global_rotation.y + PI, "pitch": -0.02, "zoom": 1.32, "crop": 280},
        {"yaw": _visual.global_rotation.y + PI + 0.58, "pitch": -0.05, "zoom": 1.96, "crop": 340},
        {"yaw": _visual.global_rotation.y + PI + 0.58, "pitch": -0.02, "zoom": 1.38, "crop": 280},
        {"yaw": _visual.global_rotation.y + PI + PI * 0.5, "pitch": -0.02, "zoom": 1.84, "crop": 340},
        {"yaw": _visual.global_rotation.y + PI + PI * 0.5, "pitch": -0.01, "zoom": 1.32, "crop": 280}
    ], 340, 340, 3)


func capture_face_focus_sheet() -> String:
    var facing_yaw := _visual.global_rotation.y + PI
    return await _capture_head_sheet("hero_face_focus_sheet.png", [
        {"yaw": facing_yaw, "pitch": -0.03, "zoom": 0.94, "crop": 230},
        {"yaw": facing_yaw + 0.42, "pitch": -0.03, "zoom": 0.98, "crop": 230},
        {"yaw": facing_yaw + PI * 0.5, "pitch": -0.02, "zoom": 1.02, "crop": 230},
        {"yaw": facing_yaw - 0.42, "pitch": -0.03, "zoom": 0.98, "crop": 230}
    ], 240, 240, 2)


func capture_face_profile_lab_sheet() -> String:
    var facing_yaw := _visual.global_rotation.y + PI
    return await _capture_head_sheet("hero_face_profile_lab.png", [
        {"yaw": facing_yaw, "pitch": -0.03, "zoom": 1.18, "crop": 280},
        {"yaw": facing_yaw + PI * 0.5, "pitch": -0.03, "zoom": 1.24, "crop": 280},
        {"yaw": facing_yaw - PI * 0.5, "pitch": -0.03, "zoom": 1.24, "crop": 280},
    ], 260, 260, 3)


func _capture_head_sheet(output_file_name: String, presets: Array, frame_width: int, frame_height: int, columns: int) -> String:
    var capture_dir := ProjectSettings.globalize_path("user://captures")
    DirAccess.make_dir_recursive_absolute(capture_dir)
    var head_anchor := _get_active_head_anchor()
    if head_anchor == null:
        print("Hero face capture: no active head anchor")
        return ""

    var old_yaw := _yaw
    var old_pitch := _pitch
    var old_zoom := _spring_arm.spring_length
    var old_camera_transform := _camera.global_transform
    var head_pos: Vector3 = head_anchor.global_position + Vector3(0.0, 0.03, 0.0)
    var captures: Array[Image] = []

    for preset in presets:
        _yaw = preset["yaw"]
        _pitch = preset["pitch"]
        _spring_arm.spring_length = preset["zoom"]
        _camera_pivot.rotation.x = _pitch
        _camera_pivot.rotation.y = _yaw
        var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
        var capture_offset: Vector3 = basis * Vector3(0.0, 0.0, preset["zoom"])
        _camera.global_position = head_pos - capture_offset
        _camera.look_at(head_pos, Vector3.UP)
        await RenderingServer.frame_post_draw
        await get_tree().process_frame
        var source: Image = get_viewport().get_texture().get_image()
        if source.is_empty():
            print("Hero face capture: empty viewport image")
            return ""
        var crop_size: int = preset["crop"]
        var center_x := source.get_width() / 2
        var center_y := source.get_height() / 2
        var start_x := clampi(center_x - crop_size / 2, 0, max(0, source.get_width() - crop_size))
        var start_y := clampi(center_y - crop_size / 2, 0, max(0, source.get_height() - crop_size))
        var cropped := Image.create(crop_size, crop_size, false, source.get_format())
        cropped.blit_rect(source, Rect2i(start_x, start_y, crop_size, crop_size), Vector2i.ZERO)
        captures.append(cropped)

    _yaw = old_yaw
    _pitch = old_pitch
    _spring_arm.spring_length = old_zoom
    _camera_pivot.rotation.x = _pitch
    _camera_pivot.rotation.y = _yaw
    _camera.global_transform = old_camera_transform

    if captures.is_empty():
        return ""

    var normalized: Array[Image] = []
    for index in range(captures.size()):
        var src := captures[index]
        if src.get_width() == frame_width and src.get_height() == frame_height:
            normalized.append(src)
            continue
        var resized := src.duplicate()
        resized.resize(frame_width, frame_height, Image.INTERPOLATE_BILINEAR)
        normalized.append(resized)

    var rows := int(ceil(float(normalized.size()) / float(columns)))
    var sheet := Image.create(frame_width * columns, frame_height * rows, false, normalized[0].get_format())
    for index in range(normalized.size()):
        var col := index % columns
        var row := index / columns
        sheet.blit_rect(normalized[index], Rect2i(0, 0, frame_width, frame_height), Vector2i(col * frame_width, row * frame_height))

    var output_path := capture_dir.path_join(output_file_name)
    var err := sheet.save_png(output_path)
    if err != OK:
        print("Hero face capture: save failed with error %s" % err)
        return ""
    return output_path


func _get_active_head_anchor() -> Node3D:
    if _visual != null and _visual.has_method("get_active_head_anchor"):
        var anchor = _visual.get_active_head_anchor()
        if anchor != null:
            return anchor
    var poor_head := get_node_or_null("Visual/PoorHero/HeadAnchor") as Node3D
    var armor_head := get_node_or_null("Visual/KnightHero/ArmorHeadAnchor") as Node3D
    if poor_head != null and poor_head.visible:
        return poor_head
    if armor_head != null and armor_head.visible:
        return armor_head
    return poor_head if poor_head != null else armor_head


func get_hud_state() -> Dictionary:
    return {
        "name": hero_name,
        "title": hero_title,
        "level": hero_level,
        "gold": hero_gold,
        "hp": hp,
        "max_hp": max_hp,
        "mana": mana,
        "max_mana": max_mana,
        "stamina":stamina,
        "max_stamina":max_stamina,
        "relic_shards": relic_shards,
        "relic_target": relic_target,
        "xp": hero_xp,
        "next_xp": next_xp,
        "health_potions": health_potions,
        "mana_potions": mana_potions,
        "magic_staff_equipped":has_magic_staff_equipped(),
        "hero_class":active_class,
        "herbs": herbs,
        "scrap": scrap,
        "ore": ore,
        "essence": essence,
        "logs":logs,
        "leather":leather,
        "cloth":cloth,
        "stone":stone,
        "resin":resin,
        "mushrooms":mushrooms,
        "crystal":crystal,
        "grave_tokens":grave_tokens,
        "plague_samples":plague_samples,
        "enemies_defeated": enemies_defeated,
        "elites_defeated": elites_defeated,
    }


func get_material_amount(kind:String)->int:
    if kind in ["herbs","scrap","ore","essence","logs","leather","cloth","stone","resin","mushrooms","crystal","grave_tokens","plague_samples"]:
        return int(get(kind))
    return 0


func add_material(kind:String,amount:int)->void:
    if kind in ["herbs","scrap","ore","essence","logs","leather","cloth","stone","resin","mushrooms","crystal","grave_tokens","plague_samples"]:
        set(kind,maxi(0,int(get(kind))+amount))
        _sync_material_stack(kind)


func can_afford_materials(costs:Dictionary)->bool:
    for kind in costs:
        if get_material_amount(str(kind))<int(costs[kind]):return false
    return true


func spend_materials(costs:Dictionary)->bool:
    if not can_afford_materials(costs):return false
    for kind in costs:add_material(str(kind),-int(costs[kind]))
    return true


func add_bag_item(item:Dictionary)->bool:
    var stored:=item.duplicate(true)
    var quantity:=maxi(1,int(stored.get("quantity",1)))
    stored["quantity"]=quantity
    if _is_stackable_item(stored):
        var stack_key:=_item_stack_key(stored)
        stored["stack_key"]=stack_key
        for existing in bag_slots:
            if _item_stack_key(existing)==stack_key:
                existing["quantity"]=maxi(1,int(existing.get("quantity",1)))+quantity
                return true
    if bag_slots.size()>=80:return false
    bag_slots.append(stored)
    return true


func _is_stackable_item(item:Dictionary)->bool:
    return bool(item.get("stackable",false)) or str(item.get("slot","")) in ["material","consumable"] or str(item.get("use",""))=="food"


func _item_stack_key(item:Dictionary)->String:
    var explicit:=str(item.get("stack_key",""))
    if not explicit.is_empty():return explicit
    var material_kind:=str(item.get("material",""))
    if not material_kind.is_empty():return "material:%s"%material_kind
    if _is_stackable_item(item):return "item:%s"%str(item.get("name",item.get("id","item"))).to_lower().strip_edges()
    return "unique:%s"%str(item.get("id",""))


func consume_bag_item(item_id:String,amount:int=1)->bool:
    for index in range(bag_slots.size()):
        var item:Dictionary=bag_slots[index]
        if item.get("id","")!=item_id and _item_stack_key(item)!=item_id:continue
        var remaining:=maxi(1,int(item.get("quantity",1)))-maxi(1,amount)
        if remaining>0:item["quantity"]=remaining
        else:bag_slots.remove_at(index)
        return true
    return false


func sync_material_inventory()->void:
    for kind in ["herbs","scrap","ore","essence","logs","leather","cloth","stone","resin","mushrooms","crystal","grave_tokens","plague_samples"]:
        _sync_material_stack(kind)


func _sync_material_stack(kind:String)->void:
    var stack_key:="material:%s"%kind
    var amount:=get_material_amount(kind)
    for index in range(bag_slots.size()-1,-1,-1):
        var item:Dictionary=bag_slots[index]
        if _item_stack_key(item)!=stack_key:continue
        if amount<=0:bag_slots.remove_at(index)
        else:
            item["quantity"]=amount
            item["stack_key"]=stack_key
        return
    if amount<=0 or bag_slots.size()>=80:return
    var display_names:={
        "herbs":"Medicinal Herbs","scrap":"Metal Scrap","ore":"Iron Ore",
        "essence":"Arcane Essence","logs":"Wood Logs","leather":"Treated Leather",
        "cloth":"Woven Cloth","stone":"Field Stone","resin":"Tree Resin",
        "mushrooms":"Cave Mushrooms","crystal":"Royal Crystal",
        "grave_tokens":"Grave Tokens","plague_samples":"Plague Samples",
    }
    bag_slots.append({
        "id":"material_%s"%kind,
        "stack_key":stack_key,
        "stackable":true,
        "quantity":amount,
        "slot":"material",
        "material":kind,
        "visual":kind,
        "icon":10,
        "name":display_names.get(kind,kind.capitalize()),
        "description":"A crafting material. Identical pickups share this bag slot.",
    })


func give_xp(amount: int) -> void:
    hero_xp += amount
    while hero_xp >= next_xp:
        hero_xp -= next_xp
        hero_level += 1
        next_xp = roundi(float(next_xp) * 1.32 + 8.0)
        base_max_hp += 9.0
        base_max_mana += 4.0
        max_hp = base_max_hp + float(equipped_armor.get("hp",0))
        max_mana = base_max_mana + float(equipped_armor.get("mana",0))
        hp = max_hp
        mana = max_mana


func use_health_potion() -> bool:
    if health_potions <= 0 or hp >= max_hp: return false
    health_potions -= 1
    hp = minf(max_hp, hp + 38.0)
    return true


func use_mana_potion() -> bool:
    if mana_potions <= 0 or mana >= max_mana: return false
    mana_potions -= 1
    mana = minf(max_mana, mana + 30.0)
    return true


func give_knight_armor() -> void:
    var pieces := [
        {"id":"royal_helm","slot":"head","icon":0,"name":"Royal Vanguard Helm","armor":10,"hp":14,"mana":5,"power":3},
        {"id":"royal_plate","slot":"chest","icon":1,"name":"Royal Vanguard Breastplate","armor":19,"hp":36,"mana":8,"power":7},
        {"id":"royal_shoulders","slot":"shoulders","icon":2,"name":"Royal Vanguard Pauldrons","armor":8,"hp":14,"mana":3,"power":3},
        {"id":"royal_gauntlets","slot":"hands","icon":3,"name":"Royal Vanguard Gauntlets","armor":5,"hp":10,"mana":4,"power":3},
        {"id":"royal_boots","slot":"feet","icon":4,"name":"Royal Vanguard Greaves","armor":6,"hp":14,"mana":4,"power":2},
		{"id":"royal_pants","slot":"pants","icon":7,"name":"Royal Vanguard Trousers","armor":7,"hp":12,"mana":5,"power":2},
    ]
    for piece in pieces:
        var exists:=false
        for item in bag_slots:
            if item.get("id","")==piece.id: exists=true
        for slot_item in equipment_slots.values():
            if slot_item.get("id","")==piece.id: exists=true
        if not exists:
            piece["description"]="Fitted blue-steel plate with restrained sun-gold trim."
            bag_slots.append(piece)


func give_travel_torch() -> void:
    var torch := {"id":"traveler_torch","slot":"offhand","icon":5,"name":"Traveler's Torch","armor":0,"hp":0,"mana":0,"power":0,"description":"A pitch-wrapped hand torch that casts warm light."}
    for item in bag_slots:
        if item.get("id", "") == torch.id:
            return
    if equipment_slots.has("offhand") and equipment_slots.offhand.get("id", "") == torch.id:
        return
    bag_slots.append(torch)


func give_royal_staff() -> void:
    var staff := {"id":"royal_vanguard_staff","slot":"mainhand","icon":6,"name":"Royal Vanguard Staff","armor":2,"hp":0,"mana":18,"power":12,"description":"A ruby-focused royal staff. Must be equipped to cast Spark, Nova, Blink, or Orb."}
    for item in bag_slots:
        if item.get("id","")==staff.id:return
    if equipment_slots.get("mainhand",{}).get("id","")==staff.id:return
    bag_slots.append(staff)


func give_royal_warrior_weapons() -> void:
    var weapons := [
        {"id":"royal_vanguard_sword","slot":"mainhand","icon":8,"name":"Royal Vanguard Sword","armor":0,"hp":8,"mana":0,"power":22,"description":"A balanced blue-steel longsword made for decisive close combat."},
        {"id":"royal_vanguard_shield","slot":"offhand","icon":9,"name":"Royal Vanguard Shield","armor":18,"hp":28,"mana":0,"power":5,"description":"A fitted royal heater shield. Required for Shield Bash and Vanguard Guard."},
    ]
    for weapon in weapons:
        var exists:=false
        for item in bag_slots:
            if item.get("id","")==weapon.id:exists=true
        for equipped in equipment_slots.values():
            if equipped.get("id","")==weapon.id:exists=true
        if not exists:bag_slots.append(weapon)


func give_starter_axe()->void:
    for item in bag_slots:
        if item.get("id","")=="starter_wood_axe":item.name="Axe";item.description="Double-click to equip in Mainhand. Stand near any tree and press E three times; then pick up each fallen log with E.";return
    if equipment_slots.get("mainhand",{}).get("id","")=="starter_wood_axe":equipment_slots.mainhand.name="Axe";return
    bag_slots.append({"id":"starter_wood_axe","slot":"mainhand","icon":8,"name":"Axe","armor":0,"hp":0,"mana":0,"power":8,"description":"Double-click to equip in Mainhand. Stand near any tree and press E three times; then pick up each fallen log with E."})


func give_starter_pickaxe()->void:
    for item in bag_slots:
        if item.get("id","")=="starter_pickaxe":
            item.name="Pickaxe"
            return
    if equipment_slots.get("mainhand",{}).get("id","")=="starter_pickaxe":return
    bag_slots.append({
        "id":"starter_pickaxe",
        "slot":"mainhand",
        "icon":8,
        "visual":"pickaxe",
        "name":"Pickaxe",
        "armor":0,
        "hp":0,
        "mana":0,
        "power":7,
        "description":"Equip in Mainhand, stand beside a large rock and press E three times. Pick up the broken ore manually."
    })


func give_starter_fishing_pole()->void:
    for item in bag_slots:
        if item.get("id","")=="starter_fishing_pole":item.name="Fishing Pole";return
    if equipment_slots.get("mainhand",{}).get("id","")=="starter_fishing_pole":equipment_slots.mainhand.name="Fishing Pole";return
    bag_slots.append({"id":"starter_fishing_pole","slot":"mainhand","icon":10,"name":"Fishing Pole","armor":0,"hp":0,"mana":0,"power":1,"description":"Equip it and press E at a visible fishing spot beside a river or pond."})


func has_axe_equipped()->bool:
    var item_id:=str(equipment_slots.get("mainhand",{}).get("id","")).to_lower()
    return "axe" in item_id and "pickaxe" not in item_id


func has_pickaxe_equipped()->bool:
    return "pickaxe" in str(equipment_slots.get("mainhand",{}).get("id","")).to_lower()


func has_fishing_pole_equipped()->bool:
    return equipment_slots.get("mainhand",{}).get("id","")=="starter_fishing_pole"


func use_bag_item_id(item_id:String)->bool:
    for i in range(bag_slots.size()):
        var item:Dictionary=bag_slots[i]
        if item.get("id","")!=item_id:continue
        if item.get("use","")!="food":
            equip_armor_from_bag(i)
            return true
        food_buff_name=str(item.get("buff_name",item.get("name","Food")))
        food_buff_time=float(item.get("duration",60.0))
        food_power_bonus=int(item.get("buff_power",0))
        food_health_regen=float(item.get("health_regen",0.0))
        food_stamina_regen=float(item.get("stamina_regen",0.0))
        hp=minf(max_hp,hp+float(item.get("heal",0.0)))
        consume_bag_item(item_id,1)
        return true
    return false


func get_food_buff_text()->String:
    if food_buff_time<=0.0:return "No active food buff"
    return "%s  %ds  Power +%d"%[food_buff_name,ceili(food_buff_time),food_power_bonus]


func is_warrior() -> bool:
    return active_class=="Warrior"


func has_warrior_weapons_equipped() -> bool:
    return equipment_slots.get("mainhand",{}).get("id","")=="royal_vanguard_sword" and equipment_slots.get("offhand",{}).get("id","")=="royal_vanguard_shield"


func switch_hero_class() -> String:
    active_class="Warrior" if active_class=="Mage" else "Mage"
    hero_title="Royal Vanguard Warrior" if active_class=="Warrior" else "Royal Vanguard Mage"
    if active_class=="Warrior":stamina=max_stamina
    equip_royal_armor()
    return active_class


func _equip_loadout_item(item_id:String,slot:String)->void:
    if equipment_slots.get(slot,{}).get("id","")==item_id:return
    if not equipment_slots.get(slot,{}).is_empty():bag_slots.append(equipment_slots[slot])
    equipment_slots[slot]={}
    equip_item_id(item_id)


func has_magic_staff_equipped() -> bool:
    return equipment_slots.get("mainhand",{}).get("id","")=="royal_vanguard_staff"


func equip_armor_from_bag(index: int) -> bool:
    if index<0 or index>=bag_slots.size(): return false
    var item:Dictionary=bag_slots[index]
    var slot:String=item.get("slot","chest")
    if not equipment_slots.has(slot):equipment_slots[slot]={}
    if not equipment_slots[slot].is_empty(): bag_slots.append(equipment_slots[slot])
    equipment_slots[slot]=item;bag_slots.remove_at(index);_refresh_equipment_stats();return true


func unequip_armor() -> bool:
    var changed:=false
    for slot in equipment_slots:
        if not equipment_slots[slot].is_empty():bag_slots.append(equipment_slots[slot]);equipment_slots[slot]={};changed=true
    _refresh_equipment_stats();return changed

func unequip_slot(slot:String)->void:
    if equipment_slots.has(slot) and not equipment_slots[slot].is_empty():bag_slots.append(equipment_slots[slot]);equipment_slots[slot]={};_refresh_equipment_stats()

func equip_item_id(item_id:String)->void:
    for i in range(bag_slots.size()):
        if bag_slots[i].get("id","")==item_id:equip_armor_from_bag(i);return


func equip_royal_armor() -> void:
    give_knight_armor()
    give_royal_staff()
    give_travel_torch()
    give_royal_warrior_weapons()
    for id in ["royal_helm","royal_plate","royal_shoulders","royal_gauntlets","royal_boots","royal_pants"]:equip_item_id(id)
    if active_class=="Warrior":
        _equip_loadout_item("royal_vanguard_sword","mainhand")
        _equip_loadout_item("royal_vanguard_shield","offhand")
    else:
        _equip_loadout_item("royal_vanguard_staff","mainhand")
        _equip_loadout_item("traveler_torch","offhand")
    _refresh_equipment_stats()


func _refresh_equipment_stats() -> void:
    var hp_fraction:=hp/maxf(1.0,max_hp); var mana_fraction:=mana/maxf(1.0,max_mana)
    var hp_bonus:=0.0;var mana_bonus:=0.0
    for item in equipment_slots.values():hp_bonus+=float(item.get("hp",0));mana_bonus+=float(item.get("mana",0))
    max_hp=base_max_hp+hp_bonus;max_mana=base_max_mana+mana_bonus
    hp=max_hp*hp_fraction; mana=max_mana*mana_fraction
    if _visual.has_method("set_equipment_pieces"): _visual.set_equipment_pieces(equipment_slots)


func get_equipment_state() -> Dictionary:
    var armor:=0;var power:=8
    for item in equipment_slots.values():armor+=int(item.get("armor",0));power+=int(item.get("power",0))
    power+=food_power_bonus
    return {"equipped":equipped_armor,"slots":equipment_slots,"bag":bag_slots,"armor":armor,"power":power}


func _get_input_vector() -> Vector2:
    var x := 0.0
    var y := 0.0

    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        y += 1.0

    return Vector2(x, y).normalized()


func _turn_visual_toward(move_dir: Vector3, delta: float) -> void:
    var target_yaw := atan2(move_dir.x, move_dir.z)
    _visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(turn_lerp * delta, 0.0, 1.0))


func get_combat_forward() -> Vector3:
    # The imported Blender hero faces local +Z. Keep every combat ability on
    # the same convention used by movement instead of Godot's camera -Z axis.
    var forward := _visual.global_basis.z
    forward.y = 0.0
    if forward.length_squared() <= 0.0001:
        forward = _last_move_dir
    return forward.normalized()


func get_cast_origin() -> Vector3:
    if _visual.has_method("get_staff_cast_origin") and has_magic_staff_equipped():
        return _visual.get_staff_cast_origin()
    var forward := get_combat_forward()
    return global_position + Vector3.UP * 1.38 + forward * 0.72


func get_fishing_line_origin()->Vector3:
    if is_instance_valid(_visual) and _visual.has_method("get_fishing_line_origin"):
        return _visual.get_fishing_line_origin()
    return global_position+Vector3.UP*1.15+get_combat_forward()*.45


func _resolve_ground_position(next_position: Vector3) -> Vector3:
    if not _height_sampler.is_valid():
        return next_position
    var sampled: Vector3 = _height_sampler.call(next_position.x, next_position.z)
    var resolved_y := next_position.y - hover_height if _interior_mode else sampled.y
    if not _interior_mode and _structure_height_sampler.is_valid():
        var structure_y: float = _structure_height_sampler.call(next_position.x, next_position.z, next_position.y)
        if structure_y > -INF:
            resolved_y = maxf(resolved_y, structure_y)
    # Terrain remains the baseline, while a short downward probe allows real
    # architectural surfaces such as castle floors and stairs to carry the
    # hero. Starting just above the current feet prevents ceilings overhead
    # from pulling the player upward from a lower storey.
    if is_inside_tree() and get_world_3d() != null:
        var from := Vector3(next_position.x, next_position.y + 2.35, next_position.z)
        var probe_bottom := next_position.y - 6.0 if _interior_mode else minf(sampled.y - 2.0, next_position.y - 6.0)
        var to := Vector3(next_position.x, probe_bottom, next_position.z)
        var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        # Never snap upward to the top of a bridge arch, ceiling or upper floor
        # merely because it is inside the downward probe. Only genuine walkable
        # steps immediately above the current feet may raise the grounded hero.
        if not hit.is_empty() and float(hit.normal.y) > 0.28 and float(hit.position.y)<=next_position.y+.76:
            resolved_y = float(hit.position.y) if _interior_mode else maxf(resolved_y, float(hit.position.y))
    return Vector3(next_position.x, resolved_y + hover_height, next_position.z)
