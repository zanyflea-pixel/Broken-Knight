extends Node3D

const IMPORTED_HERO_PATH := "res://assets/hero/hero_runtime_optimized_v1.glb"
const ROYAL_STAFF_SCENE := preload("res://assets/equipment/royal_vanguard_staff.glb")
const AXE_SCENE:=preload("res://assets/items/axe_v2.glb")
const PICKAXE_SCENE:=preload("res://assets/items/pickaxe.glb")
const FISHING_POLE_SCENE:=preload("res://assets/items/fishing_pole.glb")
const ROYAL_SWORD_SCENE:=preload("res://assets/equipment/royal_vanguard_sword.glb")
const ROYAL_SHIELD_SCENE:=preload("res://assets/equipment/royal_vanguard_shield.glb")
const SWORD_GRIP_LOCAL_POSITION:=Vector3(0.0,.072,0.0)

const DEFAULT_FACE_PROFILE := {
	"eye_spacing": 0.030,
	"eye_depth": 0.094,
	"eye_socket_depth": 0.091,
	"eye_y": -0.002,
	"brow_outer": 0.034,
	"nose_depth": 0.098,
	"nose_y": -0.012,
	"philtrum_depth": 0.094,
	"mouth_depth": 0.089,
	"mouth_y": -0.040,
	"chin_depth": 0.076,
	"chin_y": -0.060,
	"jaw_depth": 0.074,
	"jaw_width": 0.025,
	"cheek_depth": 0.090,
	"hair_side": 0.070,
	"hair_front": 0.026,
	"head_anchor_y": 1.58,
}

var _is_armored: bool = false
var _move_blend: float = 0.0
var _movement_speed: float = 0.0
var _time: float = 0.0
var _walk_cycle: float = 0.0
var _face_profile: Dictionary = DEFAULT_FACE_PROFILE.duplicate(true)

var _poor_root: Node3D
var _armor_root: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _head_anchor: Node3D
var _cape: Node3D
var _armor_left_arm: Node3D
var _armor_right_arm: Node3D
var _armor_left_leg: Node3D
var _armor_right_leg: Node3D
var _armor_head_anchor: Node3D
var _armor_cape: Node3D
var _imported_hero: Node3D
var _continuous_body_geometry: Array[GeometryInstance3D] = []
var _equipment_armor_root: Node3D
var _equipment_piece_roots: Dictionary = {}
var _base_loin_nodes: Array[Node] = []
var _torch_root: Node3D
var _torch_hand_attachment: BoneAttachment3D
var _torch_light: OmniLight3D
var _torch_flame_outer: MeshInstance3D
var _torch_flame_inner: MeshInstance3D
var _torch_flame_tip: MeshInstance3D
var _staff_nodes: Array[Node] = []
var _staff_equipped := false
var _staff_hand_attachment: BoneAttachment3D
var _staff_focus_marker: Node3D
var _staff_focus_light: OmniLight3D
var _staff_focus_aura: MeshInstance3D
var _sword_root: Node3D
var _sword_attachment: BoneAttachment3D
var _sword_action_grip_basis := Basis.IDENTITY
var _sword_action_grip_ready := false
var _axe_root:Node3D
var _pickaxe_root:Node3D
var _fishing_pole_root:Node3D
var _fishing_pole_tip:Node3D
var _shield_root: Node3D
var _shield_attachment: BoneAttachment3D
var _warrior_equipped := false
var _imported_animation_player: AnimationPlayer
var _imported_skeleton: Skeleton3D
var _leg_scale_bones := PackedInt32Array()
var _sword_forearm_bone := -1
var _sword_forearm_base_rotation := Quaternion.IDENTITY
var _sword_forearm_base_ready := false
var _sword_pose_base: Dictionary = {}
var _sword_pose_ready := false
var _current_imported_animation: StringName = &""
var _air_animation_state: StringName = &""
var _action_animation_state: StringName = &""
var _action_time := 0.0
var _action_kind := ""
var _death_active := false
var _diagnostic_hero_mode := ""
var _mounted := false
var _mounted_pose_base:Dictionary={}

var _skin_mat: StandardMaterial3D
var _face_mat: StandardMaterial3D
var _hair_mat: StandardMaterial3D
var _cloth_mat: StandardMaterial3D
var _cloth_dark_mat: StandardMaterial3D
var _linen_mat: StandardMaterial3D
var _belt_mat: StandardMaterial3D
var _boot_mat: StandardMaterial3D
var _steel_mat: StandardMaterial3D
var _iron_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _royal_cobalt_mat:StandardMaterial3D
var _royal_dark_mat:StandardMaterial3D
var _helmet_interior_mat:StandardMaterial3D
var _royal_blued_mat:StandardMaterial3D
var _royal_bright_mat:StandardMaterial3D
var _royal_mail_mat:StandardMaterial3D
var _royal_crimson_mat:StandardMaterial3D
var _royal_crimson_dark_mat:StandardMaterial3D
var _tabard_mat: StandardMaterial3D
var _cape_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _eye_white_mat: StandardMaterial3D
var _iris_mat: StandardMaterial3D
var _face_decal_mat: StandardMaterial3D


func _ready() -> void:
	# Run after the imported AnimationPlayer so procedural held-item bone
	# adjustments are not overwritten later in the same frame.
	process_priority=100
	_build_materials()
	_build_visuals()
	set_armored(false)
	_diagnostic_hero_mode = OS.get_environment("BROKEN_KNIGHT_HERO_DIAGNOSTIC").strip_edges().to_lower()
	if _diagnostic_hero_mode == "hidden":
		_imported_hero.visible = false
		_imported_hero.process_mode = Node.PROCESS_MODE_DISABLED
	elif _diagnostic_hero_mode == "static":
		_imported_hero.process_mode = Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	if _diagnostic_hero_mode == "hidden" or _diagnostic_hero_mode == "static":
		return
	_time += delta
	_walk_cycle += delta * lerpf(1.6, 7.2, _move_blend)
	_action_time = maxf(0.0, _action_time - delta)
	_apply_animation()
	_update_imported_animation()
	_apply_leg_proportion_correction()
	_apply_mounted_pose()
	_update_hand_torch_transform()
	_update_torch_effects()
	_update_staff_effects()
	_update_warrior_weapon_action()


func set_armored(enabled: bool) -> void:
	_is_armored = enabled
	if is_instance_valid(_poor_root):
		_poor_root.visible = not enabled and not is_instance_valid(_imported_hero)
	if is_instance_valid(_armor_root):
		_armor_root.visible = enabled and not is_instance_valid(_imported_hero)
	if is_instance_valid(_imported_hero):
		_imported_hero.visible = true


func set_equipment_armor(enabled: bool) -> void:
	for slot in _equipment_piece_roots:
		for armor_node in _equipment_piece_roots[slot]:
			if is_instance_valid(armor_node): armor_node.visible=enabled
	if is_instance_valid(_equipment_armor_root): _equipment_armor_root.visible=enabled

func set_equipment_pieces(slots:Dictionary)->void:
	if not is_instance_valid(_equipment_armor_root):return
	var any:=false
	for slot in _equipment_piece_roots:
		var shown: bool = not slots.get(slot,{}).is_empty()
		for armor_node in _equipment_piece_roots[slot]:
			if is_instance_valid(armor_node): armor_node.visible=shown
		any=any or shown
	_equipment_armor_root.visible=any
	var lower_armor_shown:bool=not slots.get("pants",{}).is_empty()
	var head_armor_shown:bool=not slots.get("head",{}).is_empty()
	var full_plate: bool = not slots.get("head",{}).is_empty() and not slots.get("chest",{}).is_empty() and not slots.get("shoulders",{}).is_empty() and not slots.get("hands",{}).is_empty() and not slots.get("feet",{}).is_empty() and lower_armor_shown
	for geometry in _continuous_body_geometry:
		if not is_instance_valid(geometry):continue
		var geometry_name:=String(geometry.name)
		if geometry_name.begins_with("RoyalArmor_"):continue
		if geometry_name=="ProfessionalHelmetFace":
			geometry.visible=false
		elif geometry_name.begins_with("ProfessionalEyes") or geometry_name.begins_with("ProfessionalBrows"):
			geometry.visible=not head_armor_shown
		elif geometry_name.begins_with("HeroHair"):
			geometry.visible=not head_armor_shown
		else:
			geometry.visible=not full_plate
	for loin_node in _base_loin_nodes:
		if is_instance_valid(loin_node):loin_node.visible=not lower_armor_shown
	if is_instance_valid(_torch_root):
		var torch_visible: bool = slots.get("offhand", {}).get("id", "") == "traveler_torch"
		if _torch_root.visible != torch_visible:
			_torch_root.visible = torch_visible
			_current_imported_animation = &""
			_update_imported_animation(true)
	var staff_visible:bool=slots.get("mainhand",{}).get("id","")=="royal_vanguard_staff"
	var sword_visible:bool=slots.get("mainhand",{}).get("id","")=="royal_vanguard_sword"
	var axe_visible:bool="axe" in str(slots.get("mainhand",{}).get("id","")).to_lower()
	var pickaxe_visible:bool="pickaxe" in str(slots.get("mainhand",{}).get("id","")).to_lower()
	axe_visible=axe_visible and not pickaxe_visible
	var fishing_visible:bool=slots.get("mainhand",{}).get("id","")=="starter_fishing_pole"
	var shield_visible:bool=slots.get("offhand",{}).get("id","")=="royal_vanguard_shield"
	if is_instance_valid(_sword_root):_sword_root.visible=sword_visible
	if is_instance_valid(_axe_root):_axe_root.visible=axe_visible
	if is_instance_valid(_pickaxe_root):_pickaxe_root.visible=pickaxe_visible
	if is_instance_valid(_fishing_pole_root):_fishing_pole_root.visible=fishing_visible
	if is_instance_valid(_shield_root):_shield_root.visible=shield_visible
	_warrior_equipped=sword_visible and shield_visible
	for staff_node in _staff_nodes:
		if is_instance_valid(staff_node):staff_node.visible=staff_visible
	if _staff_equipped!=staff_visible:
		_staff_equipped=staff_visible
		if is_instance_valid(_staff_focus_marker):_staff_focus_marker.visible=staff_visible
		_current_imported_animation=&""
		_update_imported_animation(true)


func toggle_armored() -> void:
	set_armored(not _is_armored)


func apply_face_profile(profile: Dictionary) -> void:
	_face_profile = DEFAULT_FACE_PROFILE.duplicate(true)
	for key in profile.keys():
		_face_profile[key] = profile[key]
	_build_visuals()
	set_armored(_is_armored)


func get_face_profile() -> Dictionary:
	return _face_profile.duplicate(true)


func get_active_head_anchor() -> Node3D:
	if _is_armored and is_instance_valid(_armor_head_anchor):
		return _armor_head_anchor
	if is_instance_valid(_head_anchor):
		return _head_anchor
	if is_instance_valid(_armor_head_anchor):
		return _armor_head_anchor
	return null


func set_move_blend(blend: float) -> void:
	_move_blend = clampf(blend, 0.0, 1.0)


func set_movement_speed(speed: float) -> void:
	_movement_speed = maxf(speed, 0.0)


func set_mounted(enabled:bool)->void:
	if _mounted==enabled:return
	if not enabled:_restore_mounted_pose()
	_mounted=enabled
	_air_animation_state=&""
	_action_animation_state=&""
	_action_kind=""
	_action_time=0.0
	_current_imported_animation=&""
	_update_imported_animation(true)


func _play_synced_equipment(animation: StringName, blend := 0.0, speed := 1.0) -> void:
	# Armor is consolidated onto the hero's own armature, so one AnimationPlayer
	# now drives both body and equipment without a second per-frame seek.
	pass


func play_jump() -> void:
	if not is_instance_valid(_imported_animation_player):
		return
	_air_animation_state = &"Jump"
	_current_imported_animation = &"Jump"
	_imported_animation_player.speed_scale = 1.0
	_imported_animation_player.play(&"Jump", 0.10)
	_play_synced_equipment(&"Jump", 0.10, 1.0)


func play_land() -> void:
	if not is_instance_valid(_imported_animation_player):
		return
	_air_animation_state = &"Land"
	_current_imported_animation = &"Land"
	# Preserve the authored compression and recoil while completing the longer
	# polished clip before the controller's locomotion handoff.
	_imported_animation_player.speed_scale = 1.12
	_imported_animation_player.play(&"Land", 0.08)
	_play_synced_equipment(&"Land", 0.08, 1.12)


func play_roll() -> void:
	if not is_instance_valid(_imported_animation_player) or not _imported_animation_player.has_animation(&"Roll"):
		return
	_air_animation_state = &""
	_action_animation_state = &"Roll"
	_current_imported_animation = &"Roll"
	_imported_animation_player.speed_scale = 1.0
	_imported_animation_player.play(&"Roll", 0.04)
	_play_synced_equipment(&"Roll", 0.04, 1.0)
	_action_time = _imported_animation_player.get_animation(&"Roll").length


func play_death() -> void:
	_death_active=true
	_air_animation_state=&""
	_action_animation_state=&"Death"
	_current_imported_animation=&"Death"
	if is_instance_valid(_imported_animation_player) and _imported_animation_player.has_animation(&"Death"):
		_imported_animation_player.speed_scale=1.0
		_imported_animation_player.play(&"Death",.06)
		_play_synced_equipment(&"Death", .06, 1.0)


func reset_death() -> void:
	_death_active=false
	_action_animation_state=&""
	_current_imported_animation=&""
	_update_imported_animation(true)


func play_action(kind: String) -> void:
	_action_kind = kind
	if kind.to_lower()=="sword":
		# Keep the working colored hero model and create the whole slash
		# directly on its skeleton. No Blender or GLB export is needed.
		_action_animation_state=&""
		_sword_action_grip_ready=false
		_sword_forearm_base_ready=false
		_sword_pose_base.clear()
		_sword_pose_ready=false
		_action_time=.62
		return
	var action_names := {
		"spark": &"Spark",
		"nova": &"Nova",
		"blink": &"Blink",
		"orb": &"Orb",
		"sword": &"SwordSlash",
		"shield": &"ShieldBash",
		"charge": &"Blink",
		"warcry": &"Orb",
		"chop": &"SwordSlash",
		"fish": &"FishCast",
	}
	var target: StringName = action_names.get(kind.to_lower(), &"")
	if _staff_equipped and target!=&"":target=StringName("Staff"+String(target))
	if is_instance_valid(_imported_animation_player) and target != &"" and _imported_animation_player.has_animation(target):
		_action_animation_state = target
		_current_imported_animation = target
		_imported_animation_player.speed_scale = 1.0
		_imported_animation_player.play(target,0.08)
		_play_synced_equipment(target, 0.08, 1.0)
		_action_time = _imported_animation_player.get_animation(target).length
	else:
		_action_time = 0.32 if kind != "orb" else 0.48


func _sword_pose_ease(value: float) -> float:
	var t:=clampf(value,0.0,1.0)
	return t*t*(3.0-2.0*t)


func _sword_pose_rotation(
	phase: float,
	outboard: Vector3,
	guard: Vector3,
	chop: Vector3,
	finish: Vector3
) -> Quaternion:
	var ready:=Quaternion(0.0,0.0,0.0,1.0)
	var outboard_q:=Basis.from_euler(outboard).get_rotation_quaternion()
	var guard_q:=Basis.from_euler(guard).get_rotation_quaternion()
	var chop_q:=Basis.from_euler(chop).get_rotation_quaternion()
	var finish_q:=Basis.from_euler(finish).get_rotation_quaternion()

	if phase<.08:
		return ready.slerp(outboard_q,_sword_pose_ease(phase/.08))
	if phase<.24:
		return outboard_q.slerp(guard_q,_sword_pose_ease((phase-.08)/.16))
	if phase<.29:
		return guard_q
	if phase<.44:
		var strike_t:=_sword_pose_ease((phase-.29)/.15)
		strike_t=pow(strike_t,2.2)
		return guard_q.slerp(chop_q,strike_t)
	if phase<.47:
		return chop_q
	if phase<.61:
		var inward_t:=_sword_pose_ease((phase-.47)/.14)
		return chop_q.slerp(finish_q,inward_t)
	if phase<.66:
		return finish_q

	# Return directly from the low finish to idle. Do not lift back through
	# the high outside guard, which looked like a second upward swing.
	return finish_q.slerp(ready,_sword_pose_ease((phase-.66)/.34))

func _capture_sword_pose() -> void:
	_sword_pose_base.clear()
	if not is_instance_valid(_imported_skeleton):
		return
	for bone_name in ["chest","clavicle.L","upper_arm.L","forearm.L","hand.L"]:
		var bone:=_imported_skeleton.find_bone(bone_name)
		if bone>=0:
			_sword_pose_base[bone_name]=_imported_skeleton.get_bone_pose_rotation(bone)
	_sword_pose_ready=not _sword_pose_base.is_empty()


func _set_sword_pose_bone(bone_name: String, offset: Quaternion) -> void:
	if not is_instance_valid(_imported_skeleton) or not _sword_pose_base.has(bone_name):
		return
	var bone:=_imported_skeleton.find_bone(bone_name)
	if bone>=0:
		var base:Quaternion=_sword_pose_base[bone_name]
		_imported_skeleton.set_bone_pose_rotation(bone,base*offset)


func _apply_procedural_sword_swing(phase: float) -> void:
	if not _sword_pose_ready:
		_capture_sword_pose()
	if not _sword_pose_ready:
		return

	_set_sword_pose_bone(
		"chest",
		_sword_pose_rotation(
			phase,
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3.ZERO
		)
	)

	# Keep the proven outward shoulder path during the high wind-up.
	# The shoulder comes inward only during the low finishing portion.
	_set_sword_pose_bone(
		"clavicle.L",
		_sword_pose_rotation(
			phase,
			Vector3(0.0,0.0,deg_to_rad(8.0)),
			Vector3(0.0,0.0,deg_to_rad(14.0)),
			Vector3(0.0,0.0,deg_to_rad(2.0)),
			Vector3(0.0,0.0,deg_to_rad(-2.0))
		)
	)

	# Wind up high and outside, descend outside the head, then drive the
	# low finish inward toward the center without crossing the torso.
	_set_sword_pose_bone(
		"upper_arm.L",
		_sword_pose_rotation(
			phase,
			Vector3(deg_to_rad(-30.0),0.0,deg_to_rad(56.0)),
			Vector3(deg_to_rad(-68.0),0.0,deg_to_rad(72.0)),
			Vector3(deg_to_rad(12.0),0.0,deg_to_rad(-6.0)),
			Vector3(deg_to_rad(24.0),0.0,deg_to_rad(-12.0))
		)
	)

	# Keep the blade rolled away from the face while high. Relax that roll
	# only after the sword is low so the edge can travel inward.
	_set_sword_pose_bone(
		"forearm.L",
		_sword_pose_rotation(
			phase,
			Vector3(deg_to_rad(46.0),deg_to_rad(38.0),0.0),
			Vector3(deg_to_rad(72.0),deg_to_rad(52.0),0.0),
			Vector3(deg_to_rad(30.0),deg_to_rad(22.0),deg_to_rad(3.0)),
			Vector3(deg_to_rad(20.0),deg_to_rad(12.0),deg_to_rad(5.0))
		)
	)

	_set_sword_pose_bone(
		"hand.L",
		_sword_pose_rotation(
			phase,
			Vector3(0.0,deg_to_rad(5.0),deg_to_rad(-4.0)),
			Vector3(0.0,deg_to_rad(8.0),deg_to_rad(-6.0)),
			Vector3(0.0,deg_to_rad(2.0),deg_to_rad(2.0)),
			Vector3(0.0,deg_to_rad(-3.0),deg_to_rad(4.0))
		)
	)

	_imported_skeleton.force_update_all_bone_transforms()

func _restore_procedural_sword_swing() -> void:
	if not _sword_pose_ready or not is_instance_valid(_imported_skeleton):
		_sword_pose_base.clear()
		_sword_pose_ready=false
		return
	for bone_name in _sword_pose_base:
		var bone:=_imported_skeleton.find_bone(String(bone_name))
		if bone>=0:
			var base:Quaternion=_sword_pose_base[bone_name]
			_imported_skeleton.set_bone_pose_rotation(bone,base)
	_imported_skeleton.force_update_all_bone_transforms()
	_sword_pose_base.clear()
	_sword_pose_ready=false

func _build_materials() -> void:
	_skin_mat = _make_lit_material(Color(0.64, 0.40, 0.30, 1.0), 0.84, 0.0)
	_face_mat = _make_lit_material(Color(0.71, 0.57, 0.47, 1.0), 0.92, 0.0)
	_hair_mat = _make_lit_material(Color(0.11, 0.09, 0.08, 1.0), 0.78, 0.0)
	_cloth_mat = _make_lit_material(Color(0.46, 0.34, 0.24, 1.0), 0.92, 0.0)
	_cloth_dark_mat = _make_lit_material(Color(0.22, 0.19, 0.17, 1.0), 0.96, 0.0)
	_linen_mat = _make_lit_material(Color(0.73, 0.68, 0.56, 1.0), 0.94, 0.0)
	_belt_mat = _make_lit_material(Color(0.31, 0.18, 0.09, 1.0), 0.84, 0.0)
	_boot_mat = _make_lit_material(Color(0.13, 0.09, 0.08, 1.0), 0.88, 0.0)
	_steel_mat = _make_metal_material(Color(0.72, 0.77, 0.83, 1.0), 0.18, 0.95)
	_iron_mat = _make_metal_material(Color(0.52, 0.57, 0.63, 1.0), 0.28, 0.82)
	_trim_mat = _make_metal_material(Color(0.70, 0.46, 0.15, 1.0), 0.42, 0.72)
	# Stable authored metals replace the old filigree texture override. The
	# texture produced purple highlights/shimmer and added needless texture work
	# to every cobalt surface while moving.
	# The world has a restrained reflection environment.  Very dark, highly
	# metallic values read as a black hole in play even when the Blender preview
	# looks correct, so these remain metal while retaining readable blue forms.
	_royal_cobalt_mat=_make_metal_material(Color(.07,.14,.28,1),.46,.65)
	_royal_dark_mat=_make_metal_material(Color(.065,.085,.13,1),.58,.52)
	_helmet_interior_mat=_make_metal_material(Color(.003,.005,.009,1),.90,.04)
	_royal_blued_mat=_make_metal_material(Color(.08,.16,.30,1),.44,.68)
	_royal_bright_mat=_make_metal_material(Color(.16,.21,.30,1),.42,.68)
	_royal_mail_mat=_make_metal_material(Color(.12,.16,.22,1),.58,.58)
	_royal_crimson_mat=_make_lit_material(Color(.42,.045,.065,1),.74,.06)
	_royal_crimson_dark_mat=_make_lit_material(Color(.16,.018,.03,1),.82,.02)
	_tabard_mat = _make_lit_material(Color(0.15, 0.25, 0.52, 1.0), 0.92, 0.0)
	_cape_mat = _make_lit_material(Color(0.41, 0.09, 0.08, 1.0), 0.90, 0.0)
	_eye_mat = _make_lit_material(Color(0.06, 0.05, 0.05, 1.0), 0.50, 0.0)
	_eye_white_mat = _make_lit_material(Color(0.88, 0.87, 0.84, 1.0), 0.72, 0.0)
	_iris_mat = _make_lit_material(Color(0.28, 0.35, 0.18, 1.0), 0.65, 0.0)
	_face_decal_mat = _make_face_decal_material()


func _build_visuals() -> void:
	for child in get_children():
		child.queue_free()

	_poor_root = Node3D.new()
	_poor_root.name = "PoorHero"
	add_child(_poor_root)
	_build_poor_hero(_poor_root)

	_armor_root = Node3D.new()
	_armor_root.name = "KnightHero"
	add_child(_armor_root)
	_build_armored_hero(_armor_root)

	var imported_path := OS.get_environment("BROKEN_KNIGHT_HERO_SCENE").strip_edges()
	if imported_path.is_empty():
		imported_path = IMPORTED_HERO_PATH
	var imported_scene := load(imported_path) as PackedScene
	_imported_hero = imported_scene.instantiate()
	_imported_hero.name = "ImportedBlenderHero"
	add_child(_imported_hero)
	_apply_continuous_runtime_materials(_imported_hero)
	_collect_geometry(_imported_hero, _continuous_body_geometry)
	_build_equipment_armor()
	_build_staff_focus()
	_build_warrior_weapons()
	_build_hand_torch()
	_imported_animation_player = _find_animation_player(_imported_hero)
	_configure_locomotion_loops(_imported_animation_player)
	_imported_skeleton = _find_skeleton(_imported_hero)
	if is_instance_valid(_imported_skeleton):
		_sword_forearm_bone=_imported_skeleton.find_bone("forearm.L")
		_leg_scale_bones = PackedInt32Array([
			_imported_skeleton.find_bone("thigh.L"),
			_imported_skeleton.find_bone("thigh.R"),
			_imported_skeleton.find_bone("shin.L"),
			_imported_skeleton.find_bone("shin.R"),
		])
	_current_imported_animation = &""
	_air_animation_state = &""
	_action_animation_state = &""
	_update_imported_animation(true)
	_poor_root.visible = false
	_armor_root.visible = false
	_equipment_armor_root.visible = false
	_torch_root.visible = false


func _configure_locomotion_loops(player:AnimationPlayer)->void:
	if not is_instance_valid(player):return
	# glTF does not reliably carry Blender's cyclic-action flag into Godot.
	# Locomotion must loop in engine or the character freezes on the final pose
	# while the controller continues moving.
	for animation_name in [&"Idle",&"Walk",&"TorchIdle",&"TorchWalk",&"StaffIdle",&"StaffWalk",&"WarriorIdle",&"WarriorWalk"]:
		if player.has_animation(animation_name):
			player.get_animation(animation_name).loop_mode=Animation.LOOP_LINEAR


func _build_equipment_armor() -> void:
	# The former equipment was a static collection of boxes that could not follow
	# the hero's skeleton. Royal armor is now authored and skinned in Blender;
	# slot prefixes let Godot reveal only the pieces the player has equipped.
	_equipment_armor_root=Node3D.new();_equipment_armor_root.name="RoyalVanguardPlate";add_child(_equipment_armor_root)
	_equipment_piece_roots={"head":[],"chest":[],"shoulders":[],"hands":[],"feet":[],"pants":[]}
	_base_loin_nodes=[]
	_staff_nodes=[]
	_collect_imported_armor(_imported_hero)
	_build_standalone_staff()
	for slot in _equipment_piece_roots:
		for armor_node in _equipment_piece_roots[slot]:
			armor_node.visible=false


func _collect_geometry(node: Node, output: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D: output.append(node as GeometryInstance3D)
	for child in node.get_children(): _collect_geometry(child, output)


func _apply_continuous_runtime_materials(node:Node)->void:
	# Blender procedural nodes do not survive glTF. Assign explicit Godot
	# materials to the imported runtime surfaces so the hero can never turn
	# white and the groom retains a consistent dark-brown finish.
	if node is MeshInstance3D:
		var mesh_node:=node as MeshInstance3D
		var node_name:=String(mesh_node.name)
		if node_name.begins_with("RoyalArmor_"):
			_apply_royal_armor_materials(mesh_node)
		elif node_name=="ConnectedBody" or node_name=="ProfessionalHelmetFace":
			mesh_node.set_surface_override_material(0,_skin_mat)
		elif node_name=="ProfessionalBrows":
			# The rebuilt brows carry a high-roughness matte Blender material.
			# Preserve it so they remain solid instead of shimmering like fibers.
			pass
		elif node_name.begins_with("HeroHair"):
			# Keep Blender's embedded directional albedo/normal maps on the new
			# groom.  Fall back to the flat material only for legacy untextured
			# hair assets.
			var imported:=mesh_node.mesh.surface_get_material(0) as BaseMaterial3D if mesh_node.mesh.get_surface_count()>0 else null
			if imported==null or (imported.albedo_texture==null and imported.normal_texture==null):
				mesh_node.set_surface_override_material(0,_hair_mat)
	for child in node.get_children():_apply_continuous_runtime_materials(child)


func _apply_royal_armor_materials(mesh_node:MeshInstance3D)->void:
	if mesh_node.mesh==null:return
	for surface in range(mesh_node.mesh.get_surface_count()):
		var imported:=mesh_node.mesh.surface_get_material(surface)
		var material_name:=String(imported.resource_name) if imported!=null else ""
		var replacement:Material
		match material_name:
			"Royal Cobalt Filigree Plate":replacement=_royal_cobalt_mat
			"Royal Gilt Brass":replacement=_trim_mat
			"Royal Blackened Steel":replacement=_royal_dark_mat
			"Helmet Interior":replacement=_helmet_interior_mat
			"Royal Blued Steel":replacement=_royal_blued_mat
			"Royal Planished Edge Steel":replacement=_royal_bright_mat
			"Riveted Mail":replacement=_royal_mail_mat
			"Harness Leather":replacement=_belt_mat
			"Ducal Crimson Horsehair":replacement=_royal_crimson_mat
			"Ducal Horsehair Shadow":replacement=_royal_crimson_dark_mat
			_:replacement=imported
		if replacement!=null:mesh_node.set_surface_override_material(surface,replacement)


func _collect_imported_armor(node:Node)->void:
	var node_name:=String(node.name)
	if node_name.begins_with("Loincloth") or node_name.begins_with("LoinTie") or node_name.begins_with("LoinKnot") or node_name.begins_with("LoinTail"):
		_base_loin_nodes.append(node)
	if node_name.begins_with("RoyalArmor_"):
		for slot in _equipment_piece_roots:
			if node_name.begins_with("RoyalArmor_%s_"%slot):
				_equipment_piece_roots[slot].append(node)
				break
	elif node_name.begins_with("RoyalStaff_"):
		_staff_nodes.append(node)
		node.visible=false
	for child in node.get_children():_collect_imported_armor(child)


func _build_standalone_staff()->void:
	var staff:=ROYAL_STAFF_SCENE.instantiate() as Node3D
	staff.name="RoyalStaff_Runtime"
	var skeleton:=_find_skeleton(_imported_hero)
	if skeleton!=null and skeleton.find_bone("hand.R")>=0:
		if not is_instance_valid(_staff_hand_attachment):
			_staff_hand_attachment=BoneAttachment3D.new()
			_staff_hand_attachment.name="RoyalStaffGrip"
			_staff_hand_attachment.bone_name="hand.R"
			skeleton.add_child(_staff_hand_attachment)
		_staff_hand_attachment.add_child(staff)
		# glTF converts the Blender staff's long Z axis to Godot Y. The authored
		# origin is already centered at the hand grip.
		staff.position=Vector3(0.0,0.0,0.0)
		staff.rotation=Vector3.ZERO
	else:
		add_child(staff)
	_staff_nodes.append(staff)
	staff.visible=false


func _build_staff_focus()->void:
	var skeleton:=_find_skeleton(_imported_hero)
	if skeleton==null or skeleton.find_bone("hand.R")<0:return
	if not is_instance_valid(_staff_hand_attachment):
		_staff_hand_attachment=BoneAttachment3D.new();_staff_hand_attachment.name="RoyalStaffGrip";_staff_hand_attachment.bone_name="hand.R";skeleton.add_child(_staff_hand_attachment)
	_staff_focus_marker=Node3D.new();_staff_focus_marker.name="RoyalStaffFocus";_staff_focus_marker.position=Vector3(0,-1.02,0);_staff_hand_attachment.add_child(_staff_focus_marker)
	var aura_mat:=StandardMaterial3D.new();aura_mat.albedo_color=Color(.18,.04,.06,.10);aura_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;aura_mat.emission_enabled=true;aura_mat.emission=Color(.30,.01,.015);aura_mat.emission_energy_multiplier=.55;aura_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_staff_focus_aura=_add_sphere(_staff_focus_marker,Vector3.ZERO,Vector3(.045,.045,.045),aura_mat)
	_staff_focus_light=OmniLight3D.new();_staff_focus_light.name="RoyalStaffLight";_staff_focus_light.light_color=Color(.55,.08,.10);_staff_focus_light.light_energy=.24;_staff_focus_light.omni_range=1.15;_staff_focus_marker.add_child(_staff_focus_light)
	_staff_focus_marker.visible=false


func _build_warrior_weapons()->void:
	var skeleton:=_find_skeleton(_imported_hero)
	if skeleton==null:return
	if skeleton.find_bone("hand.R")>=0:
		_sword_attachment=BoneAttachment3D.new()
		_sword_attachment.name="RoyalSwordGrip"
		_sword_attachment.bone_name="hand.L"
		skeleton.add_child(_sword_attachment)
		_sword_root=ROYAL_SWORD_SCENE.instantiate() as Node3D
		_sword_root.name="RoyalVanguardSword"
		_sword_attachment.add_child(_sword_root)
		_sword_root.visible=false
		_axe_root=AXE_SCENE.instantiate() as Node3D;_axe_root.name="Axe";_axe_root.rotation=Vector3.ZERO;_axe_root.scale=Vector3.ONE*.42;_sword_attachment.add_child(_axe_root)
		_axe_root.visible=false
		_pickaxe_root=PICKAXE_SCENE.instantiate() as Node3D;_pickaxe_root.name="Pickaxe";_pickaxe_root.rotation=Vector3.ZERO;_pickaxe_root.scale=Vector3.ONE*.40;_sword_attachment.add_child(_pickaxe_root)
		_pickaxe_root.visible=false
		_fishing_pole_root=FISHING_POLE_SCENE.instantiate() as Node3D;_fishing_pole_root.name="FishingPole";_fishing_pole_root.rotation=Vector3(0,0,PI);_fishing_pole_root.scale=Vector3.ONE*.58;_sword_attachment.add_child(_fishing_pole_root);_fishing_pole_root.visible=false
		# Blender's authored tip (.08, 2.10, -.18) converted to Godot's Y-up
		# glTF coordinates.  The marker follows the hand and animated rod.
		_fishing_pole_tip=Node3D.new();_fishing_pole_tip.name="FishingPoleTip";_fishing_pole_tip.position=Vector3(.08,-.18,-2.10);_fishing_pole_root.add_child(_fishing_pole_tip)
	if skeleton.find_bone("hand.R")>=0:
		_shield_attachment=BoneAttachment3D.new();_shield_attachment.name="RoyalShieldGrip";_shield_attachment.bone_name="hand.R";skeleton.add_child(_shield_attachment)
		_shield_root=ROYAL_SHIELD_SCENE.instantiate() as Node3D
		_shield_root.name="RoyalVanguardShield"
		_shield_attachment.add_child(_shield_root)
		_shield_root.visible=false


func _update_staff_effects()->void:
	if not _staff_equipped or not is_instance_valid(_staff_focus_marker):return
	var pulse:=sin(_time*3.8)*.035+sin(_time*7.7)*.012
	if is_instance_valid(_staff_focus_aura):_staff_focus_aura.scale=Vector3.ONE*(1.0+pulse)
	if is_instance_valid(_staff_focus_light):_staff_focus_light.light_energy=.24+pulse*.8


func get_staff_cast_origin()->Vector3:
	if _staff_equipped and is_instance_valid(_staff_focus_marker):return _staff_focus_marker.global_position
	return global_position+Vector3.UP*1.38+global_basis.z*.72


func _build_hand_torch() -> void:
	_torch_root = Node3D.new()
	_torch_root.name = "EquippedTravelerTorch"
	add_child(_torch_root)
	var skeleton := _find_skeleton(_imported_hero)
	if skeleton != null and skeleton.find_bone("hand.L") >= 0:
		_torch_hand_attachment = BoneAttachment3D.new()
		_torch_hand_attachment.name = "TorchHandGrip"
		_torch_hand_attachment.bone_name = "hand.L"
		skeleton.add_child(_torch_hand_attachment)
	var wood := _make_lit_material(Color(0.16, 0.065, 0.020), 0.92, 0.0)
	var leather := _make_lit_material(Color(0.075, 0.025, 0.010), 0.96, 0.0)
	var pitch := _make_lit_material(Color(0.030, 0.012, 0.006), 0.98, 0.0)
	var iron := _make_metal_material(Color(0.18, 0.16, 0.14), 0.72, 0.55)
	_add_tapered_cylinder(_torch_root, Vector3(0, 0.18, 0), 0.041, 0.030, 0.86, wood)
	_add_cylinder(_torch_root, Vector3(0, -0.255, 0), Vector3(0.047, 0.028, 0.047), iron)
	for wrap_y in [-0.11, -0.045, 0.020, 0.085]:
		_add_cylinder(_torch_root, Vector3(0, wrap_y, 0), Vector3(0.047, 0.022, 0.047), leather)
	_add_cylinder(_torch_root, Vector3(0, 0.565, 0), Vector3(0.075, 0.025, 0.075), iron)
	_add_tapered_cylinder(_torch_root, Vector3(0, 0.675, 0), 0.105, 0.080, 0.235, pitch)
	for wrap_y in [0.590, 0.645, 0.700, 0.755]:
		var wrap := _add_cylinder(_torch_root, Vector3(0, wrap_y, 0), Vector3(0.112, 0.018, 0.112), leather)
		wrap.rotation.y = wrap_y * 2.8

	var outer_flame := StandardMaterial3D.new()
	outer_flame.albedo_color = Color(1.0, 0.18, 0.015, 0.82)
	outer_flame.emission_enabled = true
	outer_flame.emission = Color(1.0, 0.08, 0.005)
	outer_flame.emission_energy_multiplier = 6.0
	outer_flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var inner_flame := outer_flame.duplicate() as StandardMaterial3D
	inner_flame.albedo_color = Color(1.0, 0.72, 0.10, 0.94)
	inner_flame.emission = Color(1.0, 0.42, 0.025)
	inner_flame.emission_energy_multiplier = 7.5
	var tip_flame := outer_flame.duplicate() as StandardMaterial3D
	tip_flame.albedo_color = Color(1.0, 0.34, 0.025, 0.65)
	_torch_flame_outer = _add_sphere(_torch_root, Vector3(0, 0.865, 0), Vector3(0.090, 0.175, 0.090), outer_flame)
	_torch_flame_inner = _add_sphere(_torch_root, Vector3(0, 0.825, -0.006), Vector3(0.052, 0.105, 0.052), inner_flame)
	_torch_flame_tip = _add_sphere(_torch_root, Vector3(0.018, 1.005, 0.005), Vector3(0.040, 0.095, 0.040), tip_flame)
	_torch_light = OmniLight3D.new()
	_torch_light.name = "TorchLight"
	_torch_light.position = Vector3(0, 0.89, 0)
	_torch_light.light_color = Color(1.0, 0.40, 0.12)
	_torch_light.light_energy = 2.15
	_torch_light.omni_range = 10.0
	_torch_light.shadow_enabled = true
	_torch_light.shadow_bias = 0.08
	_torch_root.add_child(_torch_light)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _update_hand_torch_transform() -> void:
	if not is_instance_valid(_torch_root) or not _torch_root.visible:
		return
	if is_instance_valid(_torch_hand_attachment):
		# Follow the animated hand position while keeping the torch upright. This
		# makes the hand close around the handle instead of leaving the prop hovering.
		var forward := global_basis.z.normalized()
		_torch_root.global_position = _torch_hand_attachment.global_position + Vector3.UP * 0.085 + forward * 0.018
		_torch_root.global_basis = Basis(Vector3.UP, global_rotation.y) * Basis.from_euler(Vector3(-0.07, 0.0, -0.045))


func _update_torch_effects() -> void:
	if not is_instance_valid(_torch_root) or not _torch_root.visible:
		return
	var flicker := sin(_time * 13.7) * 0.055 + sin(_time * 21.3 + 1.4) * 0.035
	var sway := sin(_time * 7.1) * 0.012
	if is_instance_valid(_torch_flame_outer):
		_torch_flame_outer.position = Vector3(sway, 0.865 + flicker * 0.10, 0.0)
		_torch_flame_outer.scale = Vector3(0.090 - flicker * 0.08, 0.175 + flicker * 0.22, 0.090 - flicker * 0.08)
	if is_instance_valid(_torch_flame_inner):
		_torch_flame_inner.position = Vector3(-sway * 0.45, 0.825, -0.006)
		_torch_flame_inner.scale = Vector3(0.052, 0.105 + flicker * 0.10, 0.052)
	if is_instance_valid(_torch_flame_tip):
		_torch_flame_tip.position = Vector3(0.018 + sway * 1.7, 1.005 + flicker * 0.18, 0.005)
	if is_instance_valid(_torch_light):
		_torch_light.light_energy = 2.15 + flicker * 4.0
		_torch_light.omni_range = 10.0 + flicker * 5.0


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _update_imported_animation(force: bool = false) -> void:
	if not is_instance_valid(_imported_animation_player):
		return
	if _death_active:
		return
	if _air_animation_state == &"Jump":
		# Hold the last airborne pose until the controller confirms ground contact.
		return
	if _air_animation_state == &"Land":
		if _imported_animation_player.is_playing():
			return
		_air_animation_state = &""
		_current_imported_animation = &""
	if _action_animation_state != &"":
		if _imported_animation_player.is_playing():
			return
		_action_animation_state = &""
		_current_imported_animation = &""
	var carrying_torch := is_instance_valid(_torch_root) and _torch_root.visible
	var target: StringName
	if _mounted:
		target=&"WarriorIdle" if _warrior_equipped and _imported_animation_player.has_animation(&"WarriorIdle") else &"Idle"
	elif _warrior_equipped:
		target=&"WarriorWalk" if _move_blend>.08 else &"WarriorIdle"
		if not _imported_animation_player.has_animation(target):target=&"Walk" if _move_blend>.08 else &"Idle"
	elif _staff_equipped:
		target=&"StaffWalk" if _move_blend>.08 else &"StaffIdle"
		if not _imported_animation_player.has_animation(target):target=&"Walk" if _move_blend>.08 else &"Idle"
	elif carrying_torch:
		target = &"TorchWalk" if _move_blend > 0.08 else &"TorchIdle"
		if not _imported_animation_player.has_animation(target):
			target = &"Walk" if _move_blend > 0.08 else &"Idle"
	else:
		target = &"Walk" if _move_blend > 0.08 else &"Idle"
	if force or target != _current_imported_animation or not _imported_animation_player.is_playing():
		_imported_animation_player.play(target, 0.16)
		_current_imported_animation = target
	if target == &"Walk" or target == &"TorchWalk" or target == &"StaffWalk" or target == &"WarriorWalk":
		# Use a jog-like visual cadence at high traversal speed. A strict foot-travel
		# ratio made the short-legged cycle spin unnaturally fast and read robotic.
		_imported_animation_player.speed_scale = clampf(_movement_speed / 3.6, 0.78, 2.35)
	else:
		_imported_animation_player.speed_scale = 1.0


func _apply_mounted_pose()->void:
	if not _mounted or not is_instance_valid(_imported_skeleton):return
	if _mounted_pose_base.is_empty():
		for bone_name in ["pelvis","thigh.L","thigh.R","shin.L","shin.R","foot.L","foot.R"]:
			var bone:=_imported_skeleton.find_bone(bone_name)
			if bone>=0:_mounted_pose_base[bone_name]=_imported_skeleton.get_bone_pose_rotation(bone)
	var offsets:={
		"pelvis":Vector3(deg_to_rad(-4.0),0.0,0.0),
		"thigh.L":Vector3(deg_to_rad(-49.0),deg_to_rad(-17.0),deg_to_rad(-8.0)),
		"thigh.R":Vector3(deg_to_rad(-49.0),deg_to_rad(17.0),deg_to_rad(8.0)),
		"shin.L":Vector3(deg_to_rad(76.0),0.0,0.0),
		"shin.R":Vector3(deg_to_rad(76.0),0.0,0.0),
		"foot.L":Vector3(deg_to_rad(-22.0),0.0,0.0),
		"foot.R":Vector3(deg_to_rad(-22.0),0.0,0.0),
	}
	for bone_name in offsets:
		if not _mounted_pose_base.has(bone_name):continue
		var bone:=_imported_skeleton.find_bone(bone_name)
		if bone<0:continue
		var base:Quaternion=_mounted_pose_base[bone_name]
		var euler:Vector3=offsets[bone_name]
		_imported_skeleton.set_bone_pose_rotation(bone,base*Basis.from_euler(euler).get_rotation_quaternion())
	_imported_skeleton.force_update_all_bone_transforms()


func _restore_mounted_pose()->void:
	if is_instance_valid(_imported_skeleton):
		for bone_name in _mounted_pose_base:
			var bone:=_imported_skeleton.find_bone(String(bone_name))
			if bone>=0:_imported_skeleton.set_bone_pose_rotation(bone,_mounted_pose_base[bone_name])
		_imported_skeleton.force_update_all_bone_transforms()
	_mounted_pose_base.clear()


func _update_warrior_weapon_action()->void:
	if not _warrior_equipped and not is_instance_valid(_axe_root) and not is_instance_valid(_pickaxe_root) and not is_instance_valid(_fishing_pole_root):return
	var action_duration:=.62
	if _action_kind!="sword" and is_instance_valid(_imported_animation_player) and _action_animation_state!=&"" and _imported_animation_player.has_animation(_action_animation_state):
		action_duration=maxf(.20,_imported_animation_player.get_animation(_action_animation_state).length)
	var phase:=1.0-clampf(_action_time/action_duration,0.0,1.0)
	var arc:=sin(phase*PI) if _action_time>0.0 else 0.0
	var rolling:=_action_animation_state==&"Roll" and _action_time>0.0
	var death_phase:=0.0
	if _death_active and is_instance_valid(_imported_animation_player) and _imported_animation_player.has_animation(&"Death"):
		death_phase=clampf(_imported_animation_player.current_animation_position/maxf(.01,_imported_animation_player.get_animation(&"Death").length),0.0,1.0)
	var body_spin:=phase*TAU if rolling else -death_phase*1.38
	if _action_kind=="sword" and _action_time>0.0:
		_apply_procedural_sword_swing(phase)
	elif _sword_pose_ready:
		_restore_procedural_sword_swing()
	if is_instance_valid(_sword_root):
		if is_instance_valid(_sword_attachment):
			# The blade is permanently rolled 90 degrees in the grip. During
			# the attack it makes one clean forward chop angled across the
			# body instead of following a perfectly vertical swing plane.
			if _action_kind=="sword" and _action_time>0.0:
				# Keep the sword attached to the animated hand.
				# The arm moves the weapon; the weapon no longer rotates independently.
				# Roll the blade away from the armored forearm while preserving the
				# hilt's seated position in the anatomical right hand (hand.L).
				var local_grip_basis:=Basis.from_euler(Vector3(-.10,.05,.20))*Basis(Vector3.UP,PI*.5)
				var local_grip:=Transform3D(local_grip_basis,SWORD_GRIP_LOCAL_POSITION)
				_sword_root.global_transform=_sword_attachment.global_transform*local_grip
			else:
				_sword_action_grip_ready=false
				_sword_root.global_position=_sword_attachment.to_global(SWORD_GRIP_LOCAL_POSITION)
				_sword_root.global_basis=Basis(Vector3.UP,global_rotation.y)*Basis.from_euler(Vector3(body_spin-.10,.05,.20))*Basis(Vector3.UP,PI*.5)
	if is_instance_valid(_axe_root):
		_axe_root.rotation=Vector3(-arc*1.05,arc*.72,-arc*.22) if _action_kind=="chop" and _action_time>0.0 else Vector3.ZERO
	if is_instance_valid(_pickaxe_root):
		_pickaxe_root.rotation=Vector3(-arc*1.18,arc*.64,-arc*.18) if _action_kind=="mine" and _action_time>0.0 else Vector3.ZERO
	if is_instance_valid(_fishing_pole_root):
		# FishCast already animates the wrist, elbow, torso and weight transfer.
		# The former sine rotation animated the rod a second time and produced
		# the violent, disconnected casting motion.
		_fishing_pole_root.rotation=Vector3(0,0,PI)
	if is_instance_valid(_shield_root):
		# The shield model is authored face-forward. Mount it in world space so
		# the crest faces away from the hero and its point remains downward;
		# inheriting the hand/forearm bone axes rotated it almost onto its back.
		var forward:=global_basis.z.normalized()
		var right:=global_basis.x.normalized()
		# Keep the guard on the shield side and the cut on the sword side.  The
		# previous subtraction pulled the shield inward across the breastplate,
		# directly into the blade path during the middle of the slash.
		var combo_clear:=arc*.075 if _action_kind=="sword" and _action_time>0.0 else 0.0
		var bash_drive:=arc*.34 if _action_kind=="shield" and _action_time>0.0 else 0.0
		if is_instance_valid(_shield_attachment):
			_shield_root.global_position=_shield_attachment.global_position-Vector3.UP*(.025+combo_clear*.12)+right*(.095+combo_clear)+forward*(.145+bash_drive+combo_clear*.20)
			_shield_root.global_basis=Basis(Vector3.UP,global_rotation.y)*Basis.from_euler(Vector3(body_spin-.08-arc*.10,-.10,.08))



func get_fishing_line_origin()->Vector3:
	if is_instance_valid(_fishing_pole_tip) and is_instance_valid(_fishing_pole_root) and _fishing_pole_root.visible:
		return _fishing_pole_tip.global_position
	if is_instance_valid(_sword_attachment):
		return _sword_attachment.global_position
	return global_position+Vector3.UP*1.15


func _apply_leg_proportion_correction()->void:
	# Preserve bone length and planted feet while keeping a strong-man amount of
	# thigh and calf mass.  The previous .87/.91 squeeze made the armored legs
	# look weak beside the cuirass and gauntlets.
	if not is_instance_valid(_imported_skeleton) or _leg_scale_bones.size() != 4:
		return
	for index in range(2):
		if _leg_scale_bones[index] >= 0:
			_imported_skeleton.set_bone_pose_scale(_leg_scale_bones[index],Vector3(.96,1.0,.96))
	for index in range(2,4):
		if _leg_scale_bones[index] >= 0:
			_imported_skeleton.set_bone_pose_scale(_leg_scale_bones[index],Vector3(.97,1.0,.97))


func _build_poor_hero(root: Node3D) -> void:
	_add_core_body(root, false)
	var head_anchor_y: float = _face_profile.get("head_anchor_y", DEFAULT_FACE_PROFILE["head_anchor_y"])
	_head_anchor = _make_anchor(root, "HeadAnchor", Vector3(0.0, head_anchor_y, 0.01))
	_add_poor_head(_head_anchor)

	_left_arm = _make_anchor(root, "LeftArm", Vector3(-0.27, 1.36, 0.0))
	_right_arm = _make_anchor(root, "RightArm", Vector3(0.27, 1.36, 0.0))
	_add_arm(_left_arm, -1.0, false)
	_add_arm(_right_arm, 1.0, false)

	_left_leg = _make_anchor(root, "LeftLeg", Vector3(-0.11, 0.98, 0.0))
	_right_leg = _make_anchor(root, "RightLeg", Vector3(0.11, 0.98, 0.0))
	_add_leg(_left_leg, -1.0, false)
	_add_leg(_right_leg, 1.0, false)


func _build_armored_hero(root: Node3D) -> void:
	_add_core_body(root, true)
	_armor_head_anchor = _make_anchor(root, "ArmorHeadAnchor", Vector3(0.0, 1.68, 0.01))
	_add_knight_head(_armor_head_anchor)

	_armor_left_arm = _make_anchor(root, "ArmorLeftArm", Vector3(-0.31, 1.40, 0.0))
	_armor_right_arm = _make_anchor(root, "ArmorRightArm", Vector3(0.31, 1.40, 0.0))
	_add_arm(_armor_left_arm, -1.0, true)
	_add_arm(_armor_right_arm, 1.0, true)

	_armor_left_leg = _make_anchor(root, "ArmorLeftLeg", Vector3(-0.13, 0.92, 0.0))
	_armor_right_leg = _make_anchor(root, "ArmorRightLeg", Vector3(0.13, 0.92, 0.0))
	_add_leg(_armor_left_leg, -1.0, true)
	_add_leg(_armor_right_leg, 1.0, true)

	_armor_cape = _make_anchor(root, "ArmorCape", Vector3(0.0, 1.52, -0.18))
	_add_knight_cape(_armor_cape)


func _apply_animation() -> void:
	var swing: float = sin(_walk_cycle) * 0.56 * _move_blend
	var counter: float = sin(_walk_cycle + PI) * 0.56 * _move_blend
	var bob: float = sin(_walk_cycle * 2.0) * 0.04 * _move_blend
	# The imported Blender hero owns its body motion through the skeleton. Keep
	# the legacy procedural bob only for the fallback constructed characters.
	# Mounted characters need their whole visual root seated above the saddle.
	# HeroController's node offset cannot own this because this animation pass
	# deliberately resets the imported root every frame.
	position.y = .92 if _mounted else (0.0 if is_instance_valid(_imported_hero) else bob)

	if is_instance_valid(_left_arm):
		_left_arm.rotation.x = swing
		_left_arm.rotation.z = -0.08
	if is_instance_valid(_right_arm):
		_right_arm.rotation.x = counter
		_right_arm.rotation.z = 0.08
	if is_instance_valid(_left_leg):
		_left_leg.rotation.x = counter * 0.42
	if is_instance_valid(_right_leg):
		_right_leg.rotation.x = swing * 0.42
	if is_instance_valid(_head_anchor):
		_head_anchor.rotation.x = sin(_time * 1.8) * 0.02 + _move_blend * 0.01
	if is_instance_valid(_cape):
		_cape.rotation.x = -0.10 - _move_blend * 0.22 + sin(_time * 2.5) * 0.04

	if is_instance_valid(_armor_left_arm):
		_armor_left_arm.rotation.x = swing * 0.82
		_armor_left_arm.rotation.z = -0.10
	if is_instance_valid(_armor_right_arm):
		_armor_right_arm.rotation.x = counter * 0.82
		_armor_right_arm.rotation.z = 0.10
	if is_instance_valid(_armor_left_leg):
		_armor_left_leg.rotation.x = counter * 0.40
	if is_instance_valid(_armor_right_leg):
		_armor_right_leg.rotation.x = swing * 0.40
	if is_instance_valid(_armor_head_anchor):
		_armor_head_anchor.rotation.x = sin(_time * 1.4) * 0.015
	if is_instance_valid(_armor_cape):
		_armor_cape.rotation.x = -0.18 - _move_blend * 0.20 + sin(_time * 2.8) * 0.035
	if is_instance_valid(_imported_hero):
		if _action_animation_state != &"":
			_imported_hero.rotation = Vector3.ZERO
			_imported_hero.position = Vector3.ZERO
			if is_instance_valid(_equipment_armor_root):
				_equipment_armor_root.rotation = Vector3.ZERO
				_equipment_armor_root.position = Vector3.ZERO
			return
		var action_strength := clampf(_action_time * 4.0, 0.0, 1.0)
		var thrust := sin(action_strength * PI) if _action_time > 0.0 else 0.0
		var cast_lean := 0.07 if _action_kind == "spark" else 0.11
		var sprint_factor:=clampf((_movement_speed-5.2)/3.3,0.0,1.0)
		_imported_hero.rotation = Vector3(-thrust * cast_lean-sprint_factor*.055, 0.0, -thrust * 0.035)
		# Imported hero and movement both face local +Z.
		_imported_hero.position = Vector3(0.0, -thrust * 0.025, thrust * 0.08)
		if is_instance_valid(_equipment_armor_root):
			_equipment_armor_root.rotation=_imported_hero.rotation
			_equipment_armor_root.position=_imported_hero.position


func _add_core_body(root: Node3D, armored: bool) -> void:
	var hips_mat: Material = _cloth_dark_mat if not armored else _iron_mat
	var chest_mat: Material = _linen_mat if not armored else _steel_mat

	_add_capsule(root, Vector3(0.0, 1.06, -0.04), Vector3(0.26, 0.42, 0.18), _skin_mat if not armored else chest_mat)
	_add_sphere(root, Vector3(0.0, 1.28, 0.00), Vector3(0.22, 0.14, 0.18), _skin_mat if not armored else chest_mat)
	_add_box(root, Vector3(0.0, 0.94, 0.04), Vector3(0.28, 0.14, 0.18), _skin_mat if not armored else hips_mat)
	_add_sphere(root, Vector3(-0.13, 0.97, 0.02), Vector3(0.09, 0.07, 0.09), _skin_mat if not armored else hips_mat)
	_add_sphere(root, Vector3(0.13, 0.97, 0.02), Vector3(0.09, 0.07, 0.09), _skin_mat if not armored else hips_mat)
	_add_cylinder(root, Vector3(0.0, 1.46, -0.01), Vector3(0.058, 0.032, 0.058), _skin_mat if not armored else _iron_mat)
	_add_sphere(root, Vector3(-0.21, 1.31, 0.00), Vector3(0.09, 0.07, 0.09), _skin_mat if not armored else chest_mat)
	_add_sphere(root, Vector3(0.21, 1.31, 0.00), Vector3(0.09, 0.07, 0.09), _skin_mat if not armored else chest_mat)
	_add_box(root, Vector3(0.0, 1.20, -0.10), Vector3(0.30, 0.10, 0.08), _skin_mat if not armored else chest_mat, Vector3(0.10, 0.0, 0.0))
	_add_box(root, Vector3(0.0, 1.38, 0.05), Vector3(0.28, 0.05, 0.12), _skin_mat if not armored else _trim_mat)
	_add_box(root, Vector3(0.0, 1.18, 0.10), Vector3(0.22, 0.18, 0.08), _skin_mat if not armored else chest_mat)
	_add_box(root, Vector3(0.0, 1.02, 0.12), Vector3(0.18, 0.14, 0.07), _skin_mat if not armored else hips_mat)
	_add_box(root, Vector3(-0.07, 1.03, 0.15), Vector3(0.04, 0.22, 0.04), _skin_mat if not armored else _trim_mat)
	_add_box(root, Vector3(0.07, 1.03, 0.15), Vector3(0.04, 0.22, 0.04), _skin_mat if not armored else _trim_mat)
	_add_box(root, Vector3(-0.10, 1.24, 0.13), Vector3(0.07, 0.18, 0.05), _skin_mat if not armored else chest_mat, Vector3(0.0, 0.0, 0.10))
	_add_box(root, Vector3(0.10, 1.24, 0.13), Vector3(0.07, 0.18, 0.05), _skin_mat if not armored else chest_mat, Vector3(0.0, 0.0, -0.10))
	_add_box(root, Vector3(-0.16, 1.12, -0.03), Vector3(0.06, 0.22, 0.08), _skin_mat if not armored else hips_mat, Vector3(0.12, 0.0, 0.0))
	_add_box(root, Vector3(0.16, 1.12, -0.03), Vector3(0.06, 0.22, 0.08), _skin_mat if not armored else hips_mat, Vector3(-0.12, 0.0, 0.0))

	if not armored:
		_add_box(root, Vector3(0.0, 0.96, 0.12), Vector3(0.34, 0.07, 0.07), _belt_mat)
		_add_box(root, Vector3(0.0, 0.74, 0.10), Vector3(0.16, 0.26, 0.04), _cloth_mat)
		_add_box(root, Vector3(-0.09, 0.73, 0.08), Vector3(0.08, 0.22, 0.04), _cloth_dark_mat, Vector3(0.0, 0.0, -0.10))
		_add_box(root, Vector3(0.09, 0.73, 0.08), Vector3(0.08, 0.22, 0.04), _cloth_dark_mat, Vector3(0.0, 0.0, 0.10))
		_add_box(root, Vector3(0.0, 1.27, 0.15), Vector3(0.10, 0.06, 0.03), _skin_mat)
		_add_box(root, Vector3(-0.11, 1.31, 0.12), Vector3(0.10, 0.05, 0.03), _skin_mat, Vector3(0.0, 0.0, 0.18))
		_add_box(root, Vector3(0.11, 1.31, 0.12), Vector3(0.10, 0.05, 0.03), _skin_mat, Vector3(0.0, 0.0, -0.18))
	else:
		_add_box(root, Vector3(0.0, 1.10, 0.15), Vector3(0.28, 0.44, 0.10), _tabard_mat, Vector3(-0.08, 0.0, 0.0))
		_add_box(root, Vector3(0.0, 0.86, 0.05), Vector3(0.30, 0.16, 0.20), hips_mat)
		_add_box(root, Vector3(0.0, 0.98, 0.14), Vector3(0.42, 0.08, 0.08), _belt_mat)
		_add_box(root, Vector3(0.0, 1.18, 0.14), Vector3(0.40, 0.46, 0.16), _steel_mat, Vector3(-0.06, 0.0, 0.0))
		_add_box(root, Vector3(0.0, 1.29, 0.22), Vector3(0.28, 0.12, 0.04), _trim_mat)
		_add_box(root, Vector3(0.0, 1.05, 0.22), Vector3(0.16, 0.34, 0.04), _trim_mat)
		_add_box(root, Vector3(0.0, 0.82, 0.14), Vector3(0.24, 0.30, 0.04), _tabard_mat)
		_add_box(root, Vector3(-0.18, 0.80, 0.10), Vector3(0.09, 0.22, 0.06), _iron_mat, Vector3(0.12, 0.0, -0.08))
		_add_box(root, Vector3(0.18, 0.80, 0.10), Vector3(0.09, 0.22, 0.06), _iron_mat, Vector3(0.12, 0.0, 0.08))
		_add_box(root, Vector3(-0.28, 1.34, 0.02), Vector3(0.12, 0.10, 0.20), _steel_mat, Vector3(0.0, 0.0, -0.26))
		_add_box(root, Vector3(0.28, 1.34, 0.02), Vector3(0.12, 0.10, 0.20), _steel_mat, Vector3(0.0, 0.0, 0.26))


func _add_poor_head(root: Node3D) -> void:
	var eye_y: float = _face_profile.get("eye_y", DEFAULT_FACE_PROFILE["eye_y"])
	var nose_depth: float = _face_profile.get("nose_depth", DEFAULT_FACE_PROFILE["nose_depth"])
	var mouth_y: float = _face_profile.get("mouth_y", DEFAULT_FACE_PROFILE["mouth_y"])
	var chin_y: float = _face_profile.get("chin_y", DEFAULT_FACE_PROFILE["chin_y"])
	var chin_depth: float = _face_profile.get("chin_depth", DEFAULT_FACE_PROFILE["chin_depth"])
	var cheek_depth: float = _face_profile.get("cheek_depth", DEFAULT_FACE_PROFILE["cheek_depth"])
	var jaw_width: float = _face_profile.get("jaw_width", DEFAULT_FACE_PROFILE["jaw_width"])
	var hair_side: float = _face_profile.get("hair_side", DEFAULT_FACE_PROFILE["hair_side"])
	var hair_front: float = _face_profile.get("hair_front", DEFAULT_FACE_PROFILE["hair_front"])
	var eye_depth_offset: float = _face_profile.get("eye_depth", DEFAULT_FACE_PROFILE["eye_depth"]) - DEFAULT_FACE_PROFILE["eye_depth"]
	var nose_offset: float = nose_depth - DEFAULT_FACE_PROFILE["nose_depth"]

	# Continuous head volume with a face surface, not a bunch of chunks glued on.
	_add_sphere(root, Vector3(0.0, -0.004, 0.004), Vector3(0.114, 0.100, 0.110), _skin_mat)
	_add_sphere(root, Vector3(0.0, -0.014, 0.036), Vector3(0.100, 0.080, 0.098), _skin_mat)
	_add_sphere(root, Vector3(0.0, 0.040, -0.008), Vector3(0.088, 0.030, 0.074), _skin_mat)
	_add_sphere(root, Vector3(-0.078, 0.000, 0.008), Vector3(0.034, 0.046, 0.032), _skin_mat)
	_add_sphere(root, Vector3(0.078, 0.000, 0.008), Vector3(0.034, 0.046, 0.032), _skin_mat)
	_add_sphere(root, Vector3(-0.044, -0.002, 0.074 + (cheek_depth - DEFAULT_FACE_PROFILE["cheek_depth"]) * 0.24), Vector3(0.032, 0.028, 0.026), _skin_mat)
	_add_sphere(root, Vector3(0.044, -0.002, 0.074 + (cheek_depth - DEFAULT_FACE_PROFILE["cheek_depth"]) * 0.24), Vector3(0.032, 0.028, 0.026), _skin_mat)
	_add_sphere(root, Vector3(-0.042 - jaw_width * 0.18, -0.056, 0.048), Vector3(0.034, 0.026, 0.030), _skin_mat)
	_add_sphere(root, Vector3(0.042 + jaw_width * 0.18, -0.056, 0.048), Vector3(0.034, 0.026, 0.030), _skin_mat)
	_add_sphere(root, Vector3(0.0, chin_y + 0.010, 0.084 + (chin_depth - DEFAULT_FACE_PROFILE["chin_depth"]) * 0.18), Vector3(0.026, 0.018, 0.020), _skin_mat)

	# The face itself is the main geometry.
	_add_face_shell(root, Vector3(0.0, 0.008, 0.096 + eye_depth_offset * 0.006), Vector2(0.108 + jaw_width * 0.14, 0.092))
	_add_face_patch(root, Vector3(0.0, 0.002 + eye_y * 0.02, 0.106 + eye_depth_offset * 0.008), Vector2(0.080 + jaw_width * 0.06, 0.062))

	# Minimal flush details only.
	_add_box(root, Vector3(0.0, 0.024 + eye_y * 0.02, 0.104), Vector3(0.050, 0.010, 0.008), _skin_mat)
	_add_box(root, Vector3(-0.022, 0.010 + eye_y * 0.03, 0.116), Vector3(0.014, 0.006, 0.004), _eye_white_mat)
	_add_box(root, Vector3(0.022, 0.010 + eye_y * 0.03, 0.116), Vector3(0.014, 0.006, 0.004), _eye_white_mat)
	_add_box(root, Vector3(-0.022, 0.010 + eye_y * 0.03, 0.119), Vector3(0.0036, 0.0036, 0.002), _iris_mat)
	_add_box(root, Vector3(0.022, 0.010 + eye_y * 0.03, 0.119), Vector3(0.0036, 0.0036, 0.002), _iris_mat)
	_add_box(root, Vector3(0.0, -0.002 + eye_y * 0.03, 0.118 + nose_offset * 0.08), Vector3(0.008, 0.022, 0.008), _skin_mat)
	_add_box(root, Vector3(0.0, -0.018 + eye_y * 0.03, 0.126 + nose_offset * 0.10), Vector3(0.012, 0.006, 0.008), _skin_mat)
	_add_box(root, Vector3(0.0, mouth_y + 0.020, 0.116), Vector3(0.018, 0.0032, 0.0032), _face_mat)

	# Ears and fuller hair cap to avoid the bald / shaved-strip look.
	_add_sphere(root, Vector3(-0.094, -0.010, -0.004), Vector3(0.012, 0.024, 0.010), _skin_mat)
	_add_sphere(root, Vector3(0.094, -0.010, -0.004), Vector3(0.012, 0.024, 0.010), _skin_mat)
	_add_sphere(root, Vector3(0.0, 0.058, -0.016), Vector3(0.104, 0.040, 0.088), _hair_mat)
	_add_sphere(root, Vector3(0.0, 0.030, 0.020), Vector3(0.104, 0.036, 0.066), _hair_mat)
	_add_sphere(root, Vector3(-0.078, 0.000, 0.012), Vector3(0.038, 0.066, 0.032 + hair_side * 0.10), _hair_mat)
	_add_sphere(root, Vector3(0.078, 0.000, 0.012), Vector3(0.038, 0.066, 0.032 + hair_side * 0.10), _hair_mat)
	_add_box(root, Vector3(0.0, 0.020, 0.072 + hair_front * 0.18), Vector3(0.094, 0.028, 0.022), _hair_mat)
	_add_box(root, Vector3(0.0, 0.094, -0.016), Vector3(0.090, 0.020, 0.070), _hair_mat)
	_add_box(root, Vector3(-0.050, -0.004, 0.060), Vector3(0.028, 0.056, 0.018), _hair_mat)
	_add_box(root, Vector3(0.050, -0.004, 0.060), Vector3(0.028, 0.056, 0.018), _hair_mat)


func _add_knight_head(root: Node3D) -> void:
	_add_capsule(root, Vector3(0.0, 0.06, -0.03), Vector3(0.18, 0.20, 0.16), _iron_mat)
	_add_box(root, Vector3(0.0, 0.20, 0.06), Vector3(0.19, 0.11, 0.08), _iron_mat)
	_add_box(root, Vector3(0.0, 0.11, 0.17), Vector3(0.24, 0.11, 0.08), _steel_mat)
	_add_box(root, Vector3(0.0, 0.12, 0.225), Vector3(0.13, 0.017, 0.015), _eye_mat)
	_add_box(root, Vector3(0.0, 0.25, -0.03), Vector3(0.08, 0.14, 0.08), _cape_mat)
	_add_box(root, Vector3(0.0, -0.13, 0.09), Vector3(0.17, 0.09, 0.15), _iron_mat, Vector3(0.10, 0.0, 0.0))
	_add_box(root, Vector3(-0.16, 0.03, 0.02), Vector3(0.038, 0.18, 0.13), _steel_mat, Vector3(0.0, 0.0, -0.08))
	_add_box(root, Vector3(0.16, 0.03, 0.02), Vector3(0.038, 0.18, 0.13), _steel_mat, Vector3(0.0, 0.0, 0.08))
	_add_box(root, Vector3(0.0, 0.18, -0.13), Vector3(0.18, 0.10, 0.11), _iron_mat)
	_add_box(root, Vector3(0.0, 0.28, 0.00), Vector3(0.045, 0.13, 0.045), _cape_mat)
	_add_box(root, Vector3(0.0, -0.01, 0.195), Vector3(0.075, 0.085, 0.026), _trim_mat)
	_add_box(root, Vector3(0.0, 0.20, 0.175), Vector3(0.17, 0.038, 0.026), _trim_mat)
	_add_box(root, Vector3(0.0, 0.04, 0.205), Vector3(0.045, 0.045, 0.018), _trim_mat)


func _make_head_ring(y: float, xw: float, back: float, side_back: float, cheek: float, front: float) -> Array:
	var front_mid := maxf(lerpf(0.0, cheek, 0.24), lerpf(0.0, front, 0.82))
	return [
		Vector3(0.0, y, back),
		Vector3(-xw * 0.30, y, lerpf(back, side_back, 0.65)),
		Vector3(-xw * 0.72, y, side_back),
		Vector3(-xw, y, 0.0),
		Vector3(-xw * 0.84, y, front_mid),
		Vector3(-xw * 0.52, y, cheek),
		Vector3(0.0, y, front),
		Vector3(xw * 0.52, y, cheek),
		Vector3(xw * 0.84, y, front_mid),
		Vector3(xw, y, 0.0),
		Vector3(xw * 0.72, y, side_back),
		Vector3(xw * 0.30, y, lerpf(back, side_back, 0.65)),
	]


func _add_face_patch(root: Node3D, pos: Vector3, size: Vector2) -> MeshInstance3D:
	var cols := 16
	var rows := 16
	var half_w := size.x * 0.5
	var half_h := size.y * 0.5
	var base_z := pos.z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y_index in range(rows):
		var v0 := float(y_index) / float(rows)
		var v1 := float(y_index + 1) / float(rows)
		var y0 := lerpf(half_h, -half_h, v0)
		var y1 := lerpf(half_h, -half_h, v1)
		for x_index in range(cols):
			var u0 := float(x_index) / float(cols)
			var u1 := float(x_index + 1) / float(cols)
			var x0 := lerpf(-half_w, half_w, u0)
			var x1 := lerpf(-half_w, half_w, u1)
			var nx0 := (u0 - 0.5) * 2.0
			var nx1 := (u1 - 0.5) * 2.0
			var ny0 := y0 / maxf(half_h, 0.001)
			var ny1 := y1 / maxf(half_h, 0.001)
			var r00 := clampf(sqrt(nx0 * nx0 + ny0 * ny0), 0.0, 1.4)
			var r10 := clampf(sqrt(nx1 * nx1 + ny0 * ny0), 0.0, 1.4)
			var r01 := clampf(sqrt(nx0 * nx0 + ny1 * ny1), 0.0, 1.4)
			var r11 := clampf(sqrt(nx1 * nx1 + ny1 * ny1), 0.0, 1.4)
			var face_mask00 := smoothstep(1.10, 0.08, r00)
			var face_mask10 := smoothstep(1.10, 0.08, r10)
			var face_mask01 := smoothstep(1.10, 0.08, r01)
			var face_mask11 := smoothstep(1.10, 0.08, r11)
			var brow_push00 := smoothstep(0.34, -0.16, ny0) * smoothstep(1.0, 0.0, absf(nx0))
			var brow_push10 := smoothstep(0.34, -0.16, ny0) * smoothstep(1.0, 0.0, absf(nx1))
			var brow_push01 := smoothstep(0.34, -0.16, ny1) * smoothstep(1.0, 0.0, absf(nx0))
			var brow_push11 := smoothstep(0.34, -0.16, ny1) * smoothstep(1.0, 0.0, absf(nx1))
			var forehead_push00 := smoothstep(0.78, 0.18, ny0) * smoothstep(0.78, 0.0, absf(nx0))
			var forehead_push10 := smoothstep(0.78, 0.18, ny0) * smoothstep(0.78, 0.0, absf(nx1))
			var forehead_push01 := smoothstep(0.78, 0.18, ny1) * smoothstep(0.78, 0.0, absf(nx0))
			var forehead_push11 := smoothstep(0.78, 0.18, ny1) * smoothstep(0.78, 0.0, absf(nx1))
			var nose_push00 := smoothstep(0.30, 0.0, absf(nx0)) * smoothstep(0.16, -0.18, ny0)
			var nose_push10 := smoothstep(0.30, 0.0, absf(nx1)) * smoothstep(0.16, -0.18, ny0)
			var nose_push01 := smoothstep(0.30, 0.0, absf(nx0)) * smoothstep(0.16, -0.18, ny1)
			var nose_push11 := smoothstep(0.30, 0.0, absf(nx1)) * smoothstep(0.16, -0.18, ny1)
			var philtrum_push00 := smoothstep(-0.04, -0.30, ny0) * smoothstep(0.18, 0.0, absf(nx0))
			var philtrum_push10 := smoothstep(-0.04, -0.30, ny0) * smoothstep(0.18, 0.0, absf(nx1))
			var philtrum_push01 := smoothstep(-0.04, -0.30, ny1) * smoothstep(0.18, 0.0, absf(nx0))
			var philtrum_push11 := smoothstep(-0.04, -0.30, ny1) * smoothstep(0.18, 0.0, absf(nx1))
			var chin_push00 := smoothstep(-0.18, -0.78, ny0) * smoothstep(1.0, 0.0, absf(nx0))
			var chin_push10 := smoothstep(-0.18, -0.78, ny0) * smoothstep(1.0, 0.0, absf(nx1))
			var chin_push01 := smoothstep(-0.18, -0.78, ny1) * smoothstep(1.0, 0.0, absf(nx0))
			var chin_push11 := smoothstep(-0.18, -0.78, ny1) * smoothstep(1.0, 0.0, absf(nx1))
			var lip_push00 := smoothstep(-0.22, -0.48, ny0) * smoothstep(0.44, 0.0, absf(nx0))
			var lip_push10 := smoothstep(-0.22, -0.48, ny0) * smoothstep(0.44, 0.0, absf(nx1))
			var lip_push01 := smoothstep(-0.22, -0.48, ny1) * smoothstep(0.44, 0.0, absf(nx0))
			var lip_push11 := smoothstep(-0.22, -0.48, ny1) * smoothstep(0.44, 0.0, absf(nx1))
			var underlip_hollow00 := smoothstep(-0.32, -0.60, ny0) * smoothstep(0.34, 0.02, absf(nx0))
			var underlip_hollow10 := smoothstep(-0.32, -0.60, ny0) * smoothstep(0.34, 0.02, absf(nx1))
			var underlip_hollow01 := smoothstep(-0.32, -0.60, ny1) * smoothstep(0.34, 0.02, absf(nx0))
			var underlip_hollow11 := smoothstep(-0.32, -0.60, ny1) * smoothstep(0.34, 0.02, absf(nx1))
			var eye_recess00 := smoothstep(0.14, -0.08, absf(ny0 - 0.12)) * smoothstep(0.62, 0.16, absf(nx0)) * smoothstep(0.04, 0.28, absf(nx0))
			var eye_recess10 := smoothstep(0.14, -0.08, absf(ny0 - 0.12)) * smoothstep(0.62, 0.16, absf(nx1)) * smoothstep(0.04, 0.28, absf(nx1))
			var eye_recess01 := smoothstep(0.14, -0.08, absf(ny1 - 0.12)) * smoothstep(0.62, 0.16, absf(nx0)) * smoothstep(0.04, 0.28, absf(nx0))
			var eye_recess11 := smoothstep(0.14, -0.08, absf(ny1 - 0.12)) * smoothstep(0.62, 0.16, absf(nx1)) * smoothstep(0.04, 0.28, absf(nx1))
			var cheek_pull00 := smoothstep(0.24, 0.82, absf(nx0)) * smoothstep(0.52, -0.28, ny0)
			var cheek_pull10 := smoothstep(0.24, 0.82, absf(nx1)) * smoothstep(0.52, -0.28, ny0)
			var cheek_pull01 := smoothstep(0.24, 0.82, absf(nx0)) * smoothstep(0.52, -0.28, ny1)
			var cheek_pull11 := smoothstep(0.24, 0.82, absf(nx1)) * smoothstep(0.52, -0.28, ny1)
			var temple_taper00 := smoothstep(0.54, 0.96, absf(nx0)) * smoothstep(0.20, 0.78, ny0)
			var temple_taper10 := smoothstep(0.54, 0.96, absf(nx1)) * smoothstep(0.20, 0.78, ny0)
			var temple_taper01 := smoothstep(0.54, 0.96, absf(nx0)) * smoothstep(0.20, 0.78, ny1)
			var temple_taper11 := smoothstep(0.54, 0.96, absf(nx1)) * smoothstep(0.20, 0.78, ny1)
			var edge_taper00 := smoothstep(0.38, 1.0, absf(nx0)) * 0.036
			var edge_taper10 := smoothstep(0.38, 1.0, absf(nx1)) * 0.036
			var edge_taper01 := smoothstep(0.38, 1.0, absf(nx0)) * 0.036
			var edge_taper11 := smoothstep(0.38, 1.0, absf(nx1)) * 0.036
			var skull_curve00 := absf(nx0) * absf(nx0) * 0.010
			var skull_curve10 := absf(nx1) * absf(nx1) * 0.010
			var skull_curve01 := absf(nx0) * absf(nx0) * 0.010
			var skull_curve11 := absf(nx1) * absf(nx1) * 0.010
			var z0 := base_z + face_mask00 * 0.008 + forehead_push00 * 0.003 + brow_push00 * 0.006 + nose_push00 * 0.018 + philtrum_push00 * 0.005 + lip_push00 * 0.005 + chin_push00 * 0.008 - underlip_hollow00 * 0.003 - eye_recess00 * 0.012 - cheek_pull00 * 0.004 - temple_taper00 * 0.005 - skull_curve00 - absf(ny0) * 0.0008 - edge_taper00 * 0.90
			var z1 := base_z + face_mask10 * 0.008 + forehead_push10 * 0.003 + brow_push10 * 0.006 + nose_push10 * 0.018 + philtrum_push10 * 0.005 + lip_push10 * 0.005 + chin_push10 * 0.008 - underlip_hollow10 * 0.003 - eye_recess10 * 0.012 - cheek_pull10 * 0.004 - temple_taper10 * 0.005 - skull_curve10 - absf(ny0) * 0.0008 - edge_taper10 * 0.90
			var z2 := base_z + face_mask01 * 0.008 + forehead_push01 * 0.003 + brow_push01 * 0.006 + nose_push01 * 0.018 + philtrum_push01 * 0.005 + lip_push01 * 0.005 + chin_push01 * 0.008 - underlip_hollow01 * 0.003 - eye_recess01 * 0.012 - cheek_pull01 * 0.004 - temple_taper01 * 0.005 - skull_curve01 - absf(ny1) * 0.0008 - edge_taper01 * 0.90
			var z3 := base_z + face_mask11 * 0.008 + forehead_push11 * 0.003 + brow_push11 * 0.006 + nose_push11 * 0.018 + philtrum_push11 * 0.005 + lip_push11 * 0.005 + chin_push11 * 0.008 - underlip_hollow11 * 0.003 - eye_recess11 * 0.012 - cheek_pull11 * 0.004 - temple_taper11 * 0.005 - skull_curve11 - absf(ny1) * 0.0008 - edge_taper11 * 0.90

			var a := Vector3(pos.x + x0, pos.y + y0, z0)
			var b := Vector3(pos.x + x1, pos.y + y0, z1)
			var c := Vector3(pos.x + x0, pos.y + y1, z2)
			var d := Vector3(pos.x + x1, pos.y + y1, z3)

			_emit_uv_tri(st, a, Vector2(u0, v0), c, Vector2(u0, v1), b, Vector2(u1, v0))
			_emit_uv_tri(st, b, Vector2(u1, v0), c, Vector2(u0, v1), d, Vector2(u1, v1))

	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _face_decal_mat
	root.add_child(node)
	return node


func _add_face_shell(root: Node3D, pos: Vector3, size: Vector2) -> MeshInstance3D:
	var cols := 24
	var rows := 28
	var half_w := size.x * 0.5
	var half_h := size.y * 0.5
	var base_z := pos.z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y_index in range(rows):
		var v0 := float(y_index) / float(rows)
		var v1 := float(y_index + 1) / float(rows)
		var y0 := lerpf(half_h, -half_h, v0)
		var y1 := lerpf(half_h, -half_h, v1)
		for x_index in range(cols):
			var u0 := float(x_index) / float(cols)
			var u1 := float(x_index + 1) / float(cols)
			var x0 := lerpf(-half_w, half_w, u0)
			var x1 := lerpf(-half_w, half_w, u1)
			var nx0 := (u0 - 0.5) * 2.0
			var nx1 := (u1 - 0.5) * 2.0
			var ny0 := y0 / maxf(half_h, 0.001)
			var ny1 := y1 / maxf(half_h, 0.001)

			var center00 := smoothstep(0.52, 0.0, absf(nx0))
			var center10 := smoothstep(0.52, 0.0, absf(nx1))
			var center01 := smoothstep(0.52, 0.0, absf(nx0))
			var center11 := smoothstep(0.52, 0.0, absf(nx1))
			var brow00 := smoothstep(0.12, -0.10, ny0) * center00
			var brow10 := smoothstep(0.12, -0.10, ny0) * center10
			var brow01 := smoothstep(0.12, -0.10, ny1) * center01
			var brow11 := smoothstep(0.12, -0.10, ny1) * center11
			var nose00 := smoothstep(0.14, -0.30, ny0) * smoothstep(0.24, 0.0, absf(nx0))
			var nose10 := smoothstep(0.14, -0.30, ny0) * smoothstep(0.24, 0.0, absf(nx1))
			var nose01 := smoothstep(0.14, -0.30, ny1) * smoothstep(0.24, 0.0, absf(nx0))
			var nose11 := smoothstep(0.14, -0.30, ny1) * smoothstep(0.24, 0.0, absf(nx1))
			var cheek00 := smoothstep(0.16, 0.42, absf(nx0)) * smoothstep(0.24, -0.10, ny0) * smoothstep(0.56, 0.0, absf(nx0))
			var cheek10 := smoothstep(0.16, 0.42, absf(nx1)) * smoothstep(0.24, -0.10, ny0) * smoothstep(0.56, 0.0, absf(nx1))
			var cheek01 := smoothstep(0.16, 0.42, absf(nx0)) * smoothstep(0.24, -0.10, ny1) * smoothstep(0.56, 0.0, absf(nx0))
			var cheek11 := smoothstep(0.16, 0.42, absf(nx1)) * smoothstep(0.24, -0.10, ny1) * smoothstep(0.56, 0.0, absf(nx1))
			var mouth00 := smoothstep(-0.18, -0.44, ny0) * center00
			var mouth10 := smoothstep(-0.18, -0.44, ny0) * center10
			var mouth01 := smoothstep(-0.18, -0.44, ny1) * center01
			var mouth11 := smoothstep(-0.18, -0.44, ny1) * center11
			var chin00 := smoothstep(-0.38, -0.78, ny0) * smoothstep(0.42, 0.0, absf(nx0))
			var chin10 := smoothstep(-0.38, -0.78, ny0) * smoothstep(0.42, 0.0, absf(nx1))
			var chin01 := smoothstep(-0.38, -0.78, ny1) * smoothstep(0.42, 0.0, absf(nx0))
			var chin11 := smoothstep(-0.38, -0.78, ny1) * smoothstep(0.42, 0.0, absf(nx1))
			var eye_recess00 := smoothstep(0.10, -0.04, absf(ny0 - 0.08)) * smoothstep(0.42, 0.16, absf(nx0)) * smoothstep(0.08, 0.24, absf(nx0))
			var eye_recess10 := smoothstep(0.10, -0.04, absf(ny0 - 0.08)) * smoothstep(0.42, 0.16, absf(nx1)) * smoothstep(0.08, 0.24, absf(nx1))
			var eye_recess01 := smoothstep(0.10, -0.04, absf(ny1 - 0.08)) * smoothstep(0.42, 0.16, absf(nx0)) * smoothstep(0.08, 0.24, absf(nx0))
			var eye_recess11 := smoothstep(0.10, -0.04, absf(ny1 - 0.08)) * smoothstep(0.42, 0.16, absf(nx1)) * smoothstep(0.08, 0.24, absf(nx1))
			var edge00 := smoothstep(0.30, 0.62, absf(nx0))
			var edge10 := smoothstep(0.30, 0.62, absf(nx1))
			var edge01 := smoothstep(0.30, 0.62, absf(nx0))
			var edge11 := smoothstep(0.30, 0.62, absf(nx1))

			var z0 := base_z + brow00 * 0.004 + nose00 * 0.013 + cheek00 * 0.004 + mouth00 * 0.005 + chin00 * 0.005 - eye_recess00 * 0.006 - edge00 * 0.004 - absf(ny0) * 0.0008
			var z1 := base_z + brow10 * 0.004 + nose10 * 0.013 + cheek10 * 0.004 + mouth10 * 0.005 + chin10 * 0.005 - eye_recess10 * 0.006 - edge10 * 0.004 - absf(ny0) * 0.0008
			var z2 := base_z + brow01 * 0.004 + nose01 * 0.013 + cheek01 * 0.004 + mouth01 * 0.005 + chin01 * 0.005 - eye_recess01 * 0.006 - edge01 * 0.004 - absf(ny1) * 0.0008
			var z3 := base_z + brow11 * 0.004 + nose11 * 0.013 + cheek11 * 0.004 + mouth11 * 0.005 + chin11 * 0.005 - eye_recess11 * 0.006 - edge11 * 0.004 - absf(ny1) * 0.0008

			var a := Vector3(pos.x + x0, pos.y + y0, z0)
			var b := Vector3(pos.x + x1, pos.y + y0, z1)
			var c := Vector3(pos.x + x0, pos.y + y1, z2)
			var d := Vector3(pos.x + x1, pos.y + y1, z3)

			_emit_tri(st, a, c, b)
			_emit_tri(st, b, c, d)

	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _skin_mat
	root.add_child(node)
	return node




func _add_arm(anchor: Node3D, side: float, armored: bool) -> void:
	var upper_mat: Material = _linen_mat if not armored else _steel_mat
	var fore_mat: Material = _skin_mat if not armored else _iron_mat
	var hand_mat: Material = _skin_mat if not armored else _steel_mat

	_add_sphere(anchor, Vector3(0.0, -0.01, 0.02), Vector3(0.10, 0.09, 0.10), _skin_mat if not armored else upper_mat)
	_add_box(anchor, Vector3(side * 0.02, -0.11, 0.02), Vector3(0.11, 0.12, 0.12), _skin_mat if not armored else upper_mat, Vector3(0.0, 0.0, side * 0.16))
	_add_cylinder(anchor, Vector3(0.0, -0.29, 0.02), Vector3(0.075, 0.22, 0.075), _skin_mat if not armored else upper_mat)
	_add_box(anchor, Vector3(0.0, -0.47, 0.04), Vector3(0.11, 0.09, 0.11), fore_mat)
	_add_cylinder(anchor, Vector3(0.0, -0.67, 0.05), Vector3(0.058, 0.19, 0.058), fore_mat)
	_add_box(anchor, Vector3(0.0, -0.86, 0.06), Vector3(0.07, 0.06, 0.08), fore_mat)
	_add_box(anchor, Vector3(0.0, -0.98, 0.11), Vector3(0.12, 0.08, 0.16), hand_mat, Vector3(0.08, 0.0, side * 0.10))
	_add_box(anchor, Vector3(side * 0.05, -0.96, 0.11), Vector3(0.03, 0.08, 0.06), hand_mat, Vector3(0.0, 0.0, side * 0.30))
	_add_box(anchor, Vector3(0.0, -1.04, 0.17), Vector3(0.08, 0.02, 0.08), hand_mat)

	if not armored:
		_add_box(anchor, Vector3(0.0, -0.70, 0.09), Vector3(0.10, 0.08, 0.11), _belt_mat)
	else:
		_add_box(anchor, Vector3(side * 0.06, 0.08, 0.05), Vector3(0.24, 0.12, 0.22), _steel_mat, Vector3(0.0, 0.0, side * 0.20))
		_add_box(anchor, Vector3(0.0, -0.62, 0.08), Vector3(0.14, 0.18, 0.18), _iron_mat, Vector3(0.08, 0.0, side * 0.08))
		_add_box(anchor, Vector3(0.0, -0.89, 0.10), Vector3(0.12, 0.10, 0.15), _steel_mat, Vector3(0.08, 0.0, side * 0.08))


func _add_leg(anchor: Node3D, side: float, armored: bool) -> void:
	var thigh_mat: Material = _cloth_dark_mat if not armored else _iron_mat
	var shin_mat: Material = _cloth_mat if not armored else _steel_mat

	_add_sphere(anchor, Vector3(0.0, -0.03, 0.02), Vector3(0.10, 0.08, 0.10), _skin_mat if not armored else thigh_mat)
	_add_cylinder(anchor, Vector3(0.0, -0.42, 0.01), Vector3(0.10, 0.36, 0.10), _skin_mat if not armored else thigh_mat)
	_add_sphere(anchor, Vector3(0.0, -0.80, 0.02), Vector3(0.07, 0.07, 0.07), shin_mat)
	_add_cylinder(anchor, Vector3(0.0, -1.14, 0.02), Vector3(0.08, 0.34, 0.08), shin_mat)
	_add_box(anchor, Vector3(0.0, -0.46, 0.08), Vector3(0.12, 0.18, 0.10), _skin_mat if not armored else thigh_mat)
	_add_box(anchor, Vector3(0.0, -1.11, 0.08), Vector3(0.10, 0.18, 0.09), shin_mat)
	_add_box(anchor, Vector3(0.0, -1.42, 0.08), Vector3(0.12, 0.10, 0.18), _boot_mat, Vector3(0.0, 0.0, side * 0.02))
	_add_box(anchor, Vector3(0.0, -1.48, 0.20), Vector3(0.18, 0.10, 0.16), _boot_mat, Vector3(0.0, 0.0, side * 0.03))

	if armored:
		_add_box(anchor, Vector3(0.0, -0.34, 0.10), Vector3(0.18, 0.24, 0.18), _iron_mat, Vector3(0.08, 0.0, 0.0))
		_add_box(anchor, Vector3(0.0, -1.06, 0.10), Vector3(0.16, 0.24, 0.18), _steel_mat, Vector3(0.06, 0.0, 0.0))
		_add_box(anchor, Vector3(0.0, -0.74, 0.10), Vector3(0.12, 0.10, 0.14), _trim_mat)


func _add_poor_cape(_root: Node3D) -> void:
	pass


func _add_knight_cape(root: Node3D) -> void:
	_add_box(root, Vector3(0.0, -0.38, -0.04), Vector3(0.62, 0.92, 0.04), _cape_mat, Vector3(0.14, 0.0, 0.0))
	_add_box(root, Vector3(0.0, -0.04, 0.04), Vector3(0.28, 0.08, 0.10), _trim_mat)


func _make_anchor(root: Node3D, anchor_name: String, pos: Vector3) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = anchor_name
	anchor.position = pos
	root.add_child(anchor)
	return anchor


func _add_sphere(root: Node3D, pos: Vector3, scale_value: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 28
	mesh.rings = 16
	node.mesh = mesh
	node.position = pos
	node.scale = scale_value
	node.material_override = mat
	root.add_child(node)
	return node


func _add_capsule(root: Node3D, pos: Vector3, scale_value: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 10
	node.mesh = mesh
	node.position = pos
	node.scale = scale_value
	node.material_override = mat
	root.add_child(node)
	return node


func _add_cylinder(root: Node3D, pos: Vector3, scale_value: Vector3, mat: Material, rotation_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 20
	mesh.rings = 4
	node.mesh = mesh
	node.position = pos
	node.scale = scale_value
	node.rotation = rotation_value
	node.material_override = mat
	root.add_child(node)
	return node


func _add_tapered_cylinder(root: Node3D, pos: Vector3, top_radius: float, bottom_radius: float, height: float, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 18
	mesh.rings = 4
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	root.add_child(node)
	return node


func _add_box(root: Node3D, pos: Vector3, size: Vector3, mat: Material, rotation_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.rotation = rotation_value
	node.material_override = mat
	root.add_child(node)
	return node


func _add_banded_head(root: Node3D, bands: Array, mat: Material) -> MeshInstance3D:
	var rings: Array = []
	for band in bands:
		var y: float = band["y"]
		var xw: float = band["xw"]
		var front: float = band["front"]
		var back: float = band["back"]
		var back_outer := lerpf(back, 0.0, 0.22)
		var back_mid := lerpf(back, 0.0, 0.46)
		var front_mid := lerpf(0.0, front, 0.58)
		var front_cheek := lerpf(0.0, front, 0.88)
		rings.append([
			Vector3(0.0, y, back),
			Vector3(-xw * 0.34, y, back_outer),
			Vector3(-xw * 0.78, y, back_mid),
			Vector3(-xw, y, 0.0),
			Vector3(-xw * 0.84, y, front_mid),
			Vector3(-xw * 0.52, y, front_cheek),
			Vector3(0.0, y, front),
			Vector3(xw * 0.52, y, front_cheek),
			Vector3(xw * 0.84, y, front_mid),
			Vector3(xw, y, 0.0),
			Vector3(xw * 0.78, y, back_mid),
			Vector3(xw * 0.34, y, back_outer),
		])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_size: int = rings[0].size()

	for ring_index in range(rings.size() - 1):
		var ring_a: Array = rings[ring_index]
		var ring_b: Array = rings[ring_index + 1]
		for point_index in range(ring_size):
			var next_index: int = (point_index + 1) % ring_size
			var a: Vector3 = ring_a[point_index]
			var b: Vector3 = ring_a[next_index]
			var c: Vector3 = ring_b[point_index]
			var d: Vector3 = ring_b[next_index]
			_emit_tri(st, a, c, b)
			_emit_tri(st, b, c, d)

	var top_ring: Array = rings[0]
	var bottom_ring: Array = rings[rings.size() - 1]
	var top_center := Vector3(0.0, bands[0]["y"], (bands[0]["front"] + bands[0]["back"]) * 0.25)
	var bottom_center := Vector3(0.0, bands[bands.size() - 1]["y"], (bands[bands.size() - 1]["front"] + bands[bands.size() - 1]["back"]) * 0.25)
	for point_index in range(ring_size):
		var next_index: int = (point_index + 1) % ring_size
		_emit_tri(st, top_center, top_ring[next_index], top_ring[point_index])
		_emit_tri(st, bottom_center, bottom_ring[point_index], bottom_ring[next_index])

	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	root.add_child(node)
	return node


func _add_ring_head(root: Node3D, rings: Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_size: int = rings[0].size()

	for ring_index in range(rings.size() - 1):
		var ring_a: Array = rings[ring_index]
		var ring_b: Array = rings[ring_index + 1]
		for point_index in range(ring_size):
			var next_index: int = (point_index + 1) % ring_size
			var a: Vector3 = ring_a[point_index]
			var b: Vector3 = ring_a[next_index]
			var c: Vector3 = ring_b[point_index]
			var d: Vector3 = ring_b[next_index]
			_emit_tri(st, a, c, b)
			_emit_tri(st, b, c, d)

	var top_ring: Array = rings[0]
	var bottom_ring: Array = rings[rings.size() - 1]
	var top_center := Vector3.ZERO
	var bottom_center := Vector3.ZERO
	for point in top_ring:
		top_center += point
	top_center /= float(ring_size)
	top_center.y += 0.012
	top_center.z += 0.006
	for point in bottom_ring:
		bottom_center += point
	bottom_center /= float(ring_size)

	for point_index in range(ring_size):
		var next_index: int = (point_index + 1) % ring_size
		_emit_tri(st, top_center, top_ring[next_index], top_ring[point_index])
		_emit_tri(st, bottom_center, bottom_ring[point_index], bottom_ring[next_index])

	st.generate_normals()
	var mesh := st.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	root.add_child(node)
	return node


func _emit_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _emit_uv_tri(st: SurfaceTool, a: Vector3, uv_a: Vector2, b: Vector3, uv_b: Vector2, c: Vector3, uv_c: Vector2) -> void:
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)


func _make_lit_material(color: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness_value
	material.metallic = metallic_value
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


func _make_metal_material(color: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness_value
	material.metallic = metallic_value
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_face_decal_material() -> StandardMaterial3D:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	_draw_soft_ellipse(image, Vector2(94, 96), Vector2(20.0, 3.8), Color(0.18, 0.12, 0.10, 0.92))
	_draw_soft_ellipse(image, Vector2(162, 96), Vector2(20.0, 3.8), Color(0.18, 0.12, 0.10, 0.92))
	_draw_soft_ellipse(image, Vector2(94, 118), Vector2(16.0, 7.0), Color(0.95, 0.94, 0.92, 1.0))
	_draw_soft_ellipse(image, Vector2(162, 118), Vector2(16.0, 7.0), Color(0.95, 0.94, 0.92, 1.0))
	_draw_soft_ellipse(image, Vector2(94, 118), Vector2(4.2, 4.2), Color(0.28, 0.34, 0.20, 1.0))
	_draw_soft_ellipse(image, Vector2(162, 118), Vector2(4.2, 4.2), Color(0.28, 0.34, 0.20, 1.0))
	_draw_soft_ellipse(image, Vector2(94, 118), Vector2(1.5, 1.5), Color(0.02, 0.02, 0.02, 1.0))
	_draw_soft_ellipse(image, Vector2(162, 118), Vector2(1.5, 1.5), Color(0.02, 0.02, 0.02, 1.0))
	_draw_soft_ellipse(image, Vector2(92, 124), Vector2(15.4, 6.2), Color(0.54, 0.40, 0.36, 0.16))
	_draw_soft_ellipse(image, Vector2(164, 124), Vector2(15.4, 6.2), Color(0.54, 0.40, 0.36, 0.16))

	var texture := ImageTexture.create_from_image(image)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.alpha_scissor_threshold = 0.05
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.no_depth_test = false
	return material


func _draw_soft_ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	var min_x := int(floor(center.x - radius.x - 1.0))
	var max_x := int(ceil(center.x + radius.x + 1.0))
	var min_y := int(floor(center.y - radius.y - 1.0))
	var max_y := int(ceil(center.y + radius.y + 1.0))
	for y in range(min_y, max_y + 1):
		if y < 0 or y >= image.get_height():
			continue
		for x in range(min_x, max_x + 1):
			if x < 0 or x >= image.get_width():
				continue
			var dx := (float(x) - center.x) / maxf(radius.x, 0.001)
			var dy := (float(y) - center.y) / maxf(radius.y, 0.001)
			var dist := sqrt(dx * dx + dy * dy)
			if dist > 1.0:
				continue
			var alpha := color.a * smoothstep(1.0, 0.72, dist)
			var base := image.get_pixel(x, y)
			image.set_pixel(x, y, base.blend(Color(color.r, color.g, color.b, alpha)))
