extends SceneTree

const CANDIDATE_PATH := "res://assets/hero/hero_full_continuous_body.glb"


func collect(node:Node,skeletons:Array,players:Array,meshes:Array)->void:
	if node is Skeleton3D:skeletons.append(node)
	if node is AnimationPlayer:players.append(node)
	if node is MeshInstance3D:meshes.append(node)
	for child in node.get_children():collect(child,skeletons,players,meshes)


func _initialize()->void:
	var hero_path:=OS.get_environment("BK_VERIFY_HERO")
	if hero_path.is_empty():hero_path=CANDIDATE_PATH
	var resource:=load(hero_path)
	if not resource is PackedScene:
		push_error("CURRENT_HERO_VERIFY|load_failed");quit(2);return
	var hero:Node=(resource as PackedScene).instantiate()
	var skeletons:Array=[];var players:Array=[];var meshes:Array=[]
	collect(hero,skeletons,players,meshes)
	var required:=["Idle","Walk","TorchIdle","TorchWalk","StaffIdle","StaffWalk","Jump","Land","Roll","Death","Spark","Nova","Blink","Orb","StaffSpark","StaffNova","StaffBlink","StaffOrb","WarriorIdle","WarriorWalk","SwordSlash","ShieldBash","FishCast"]
	var names:Array[String]=[]
	for player in players:
		for animation_name in (player as AnimationPlayer).get_animation_list():
			if animation_name!="RESET":names.append(String(animation_name))
	var missing:=required.filter(func(name):return not names.has(name))
	var armor:=0;var skinned:=0;var slots:={"head":0,"chest":0,"shoulders":0,"hands":0,"pants":0,"feet":0}
	for mesh in meshes:
		var mesh_name:=String(mesh.name)
		if mesh_name.begins_with("RoyalArmor_"):
			armor+=1
			if (mesh as MeshInstance3D).skin!=null:skinned+=1
			for slot in slots:
				if mesh_name.begins_with("RoyalArmor_%s_"%slot):slots[slot]+=1
	var valid:=skeletons.size()==1 and not players.is_empty() and missing.is_empty() and armor>=6 and armor<=12 and skinned==armor
	for slot in slots:valid=valid and slots[slot]>0
	if valid:
		var player:=players[0] as AnimationPlayer
		player.play("Walk");player.advance(.35)
		valid=player.current_animation=="Walk"
	print("CURRENT_HERO_IMPORT|skeletons=%d|players=%d|meshes=%d|armor=%d|skinned=%d|slots=%s|animations=%d|missing=%s"%[skeletons.size(),players.size(),meshes.size(),armor,skinned,slots,names.size(),missing])
	print("CURRENT_HERO_VERIFY|%s"%("PASS" if valid else "FAIL"))
	hero.free();quit(0 if valid else 3)
