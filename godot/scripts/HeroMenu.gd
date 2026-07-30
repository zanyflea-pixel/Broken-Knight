extends Control

signal close_requested
const EquipmentSlot=preload("res://scripts/EquipmentSlot.gd")

var hero:Node
var director:Node
var stats:Label
var slots_root:GridContainer
var bag_root:GridContainer
var bag_count:Label
var portrait_piece_roots:Dictionary={}
var portrait_model:Node3D
var portrait_holder:SubViewportContainer
var portrait_camera:Camera3D
var _rotating:=false
var portrait_item_variants:Dictionary={}
var portrait_base_loin_nodes:Array[Node]=[]
var portrait_animation_player:AnimationPlayer
var portrait_skeleton:Skeleton3D


func configure(hero_node:Node,gameplay_director:Node=null)->void:
    hero=hero_node
    director=gameplay_director
    refresh()


func _panel_style(color:Color,border:Color,radius:=10)->StyleBoxFlat:
    var style:=StyleBoxFlat.new()
    style.bg_color=color
    style.border_color=border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    return style


func _ready()->void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    var dim:=ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color=Color(.006,.009,.016,.94)
    add_child(dim)

    # The old fixed 1400x840 panel could never fit inside the 1280x720 game
    # window. Anchor to the live viewport and preserve a small safe margin.
    var panel:=PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    panel.offset_left=14
    panel.offset_top=12
    panel.offset_right=-14
    panel.offset_bottom=-12
    panel.add_theme_stylebox_override("panel",_panel_style(Color(.018,.025,.040,.985),Color(.36,.48,.68,.8),14))
    add_child(panel)

    var margin:=MarginContainer.new()
    for side in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_"+side,14)
    panel.add_child(margin)
    var page:=VBoxContainer.new()
    page.add_theme_constant_override("separation",8)
    margin.add_child(page)

    var header:=HBoxContainer.new()
    page.add_child(header)
    var title:=Label.new()
    title.text="HERO & INVENTORY"
    title.add_theme_font_size_override("font_size",22)
    title.add_theme_color_override("font_color",Color(1,.79,.30))
    title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    header.add_child(title)
    var hint:=Label.new()
    hint.text="Drag the hero with the mouse to rotate  |  Double-click to use or equip  |  B / I / Esc closes"
    hint.add_theme_font_size_override("font_size",11)
    hint.add_theme_color_override("font_color",Color(.62,.70,.82))
    header.add_child(hint)
    page.add_child(HSeparator.new())

    var columns:=HBoxContainer.new()
    columns.add_theme_constant_override("separation",10)
    columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
    page.add_child(columns)
    _build_equipment_column(columns)
    _build_portrait(columns)
    _build_bag_column(columns)

    var close:=Button.new()
    close.text="RETURN TO WORLD"
    close.custom_minimum_size=Vector2(0,34)
    close.pressed.connect(func():close_requested.emit())
    page.add_child(close)


func _section_panel(parent:Container,width:float)->VBoxContainer:
    var frame:=PanelContainer.new()
    frame.custom_minimum_size=Vector2(width,0)
    frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
    frame.add_theme_stylebox_override("panel",_panel_style(Color(.027,.037,.055,.96),Color(.16,.23,.34,.9),9))
    parent.add_child(frame)
    var margin:=MarginContainer.new()
    for side in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_"+side,10)
    frame.add_child(margin)
    var box:=VBoxContainer.new()
    box.add_theme_constant_override("separation",6)
    margin.add_child(box)
    return box


func _heading(parent:Container,text_value:String)->void:
    var label:=Label.new()
    label.text=text_value
    label.add_theme_font_size_override("font_size",14)
    label.add_theme_color_override("font_color",Color(.88,.76,.42))
    parent.add_child(label)


func _build_equipment_column(columns:HBoxContainer)->void:
    var left:=_section_panel(columns,252)
    _heading(left,"EQUIPPED GEAR")
    stats=Label.new()
    stats.add_theme_font_size_override("font_size",11)
    stats.custom_minimum_size=Vector2(0,46)
    stats.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    left.add_child(stats)
    slots_root=GridContainer.new()
    slots_root.columns=1
    slots_root.add_theme_constant_override("v_separation",3)
    slots_root.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    slots_root.size_flags_vertical=Control.SIZE_EXPAND_FILL
    left.add_child(slots_root)


func _build_bag_column(columns:HBoxContainer)->void:
    var right:=_section_panel(columns,330)
    var bag_header:=HBoxContainer.new()
    right.add_child(bag_header)
    _heading(bag_header,"TRAVEL BAG")
    bag_count=Label.new()
    bag_count.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
    bag_count.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    bag_count.add_theme_font_size_override("font_size",10)
    bag_count.add_theme_color_override("font_color",Color(.62,.70,.82))
    bag_header.add_child(bag_count)
    var bag_hint:=Label.new()
    bag_hint.text="80 slots | identical supplies stack | drag equipped gear here"
    bag_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    bag_hint.add_theme_font_size_override("font_size",9)
    bag_hint.add_theme_color_override("font_color",Color(.48,.57,.68))
    right.add_child(bag_hint)
    var bag_scroll:=ScrollContainer.new()
    bag_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
    right.add_child(bag_scroll)
    bag_root=GridContainer.new()
    bag_root.columns=4
    bag_root.add_theme_constant_override("h_separation",5)
    bag_root.add_theme_constant_override("v_separation",5)
    bag_scroll.add_child(bag_root)


func refresh()->void:
    if not is_instance_valid(hero) or not slots_root:return
    if hero.has_method("sync_material_inventory"):hero.sync_material_inventory()
    var state:Dictionary=hero.get_equipment_state()
    stats.text="LEVEL %d    %s\nHealth %d / %d    %s %d / %d\nArmor %d    Power %d    Gold %d"%[
        hero.hero_level,hero.active_class.to_upper(),hero.hp,hero.max_hp,
        "Stamina" if hero.has_method("is_warrior") and hero.is_warrior() else "Mana",
        hero.stamina if hero.has_method("is_warrior") and hero.is_warrior() else hero.mana,
        hero.max_stamina if hero.has_method("is_warrior") and hero.is_warrior() else hero.max_mana,
        state.armor,state.power,hero.hero_gold
    ]
    for child in slots_root.get_children():
        slots_root.remove_child(child)
        child.queue_free()
    for slot in ["head","chest","shoulders","hands","feet","pants","mainhand","offhand"]:
        var card:=EquipmentSlot.new()
        card.setup(hero,self,"equip",slot,state.slots.get(slot,{}))
        slots_root.add_child(card)
        if portrait_piece_roots.has(slot):
            for equipment_node in portrait_piece_roots[slot]:
                equipment_node.visible=not state.slots.get(slot,{}).is_empty()
    var lower_armor_shown:bool=not state.slots.get("pants",{}).is_empty()
    for loin_node in portrait_base_loin_nodes:
        if is_instance_valid(loin_node):loin_node.visible=not lower_armor_shown
    for item_id in portrait_item_variants:
        for equipment_node in portrait_item_variants[item_id]:
            equipment_node.visible=false
    for slot in ["mainhand","offhand"]:
        var equipped_id:String=state.slots.get(slot,{}).get("id","")
        if portrait_item_variants.has(equipped_id):
            for equipment_node in portrait_item_variants[equipped_id]:
                equipment_node.visible=true
    _sync_portrait_pose(
        str(state.slots.get("mainhand",{}).get("id","")),
        str(state.slots.get("offhand",{}).get("id",""))
    )

    for child in bag_root.get_children():
        bag_root.remove_child(child)
        child.queue_free()
    var bag:Array=state.bag
    var total_items:=0
    for stored_item in bag:
        total_items+=maxi(1,int(stored_item.get("quantity",1)))
    bag_count.text="%d / 80 SLOTS   %d ITEMS"%[bag.size(),total_items]
    for index in range(80):
        var item:Dictionary=bag[index] if index<bag.size() else {}
        var card:=EquipmentSlot.new()
        card.setup(hero,self,"bag","Slot %02d"%(index+1),item)
        bag_root.add_child(card)


func _build_portrait(columns:HBoxContainer)->void:
    var center:=VBoxContainer.new()
    center.custom_minimum_size=Vector2(390,0)
    center.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    center.size_flags_vertical=Control.SIZE_EXPAND_FILL
    columns.add_child(center)
    var frame:=PanelContainer.new()
    frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
    frame.add_theme_stylebox_override("panel",_panel_style(Color(.05,.07,.095,1),Color(.25,.36,.55,.9),10))
    center.add_child(frame)
    portrait_holder=SubViewportContainer.new()
    portrait_holder.stretch=true
    portrait_holder.mouse_filter=Control.MOUSE_FILTER_STOP
    portrait_holder.gui_input.connect(_portrait_input)
    frame.add_child(portrait_holder)
    var viewport:=SubViewport.new()
    viewport.size=Vector2i(520,640)
    viewport.own_world_3d=true
    viewport.transparent_bg=false
    viewport.msaa_3d=Viewport.MSAA_2X
    viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
    portrait_holder.add_child(viewport)
    var world:=Node3D.new()
    viewport.add_child(world)
    var preview_env:=WorldEnvironment.new()
    var env:=Environment.new()
    env.background_mode=Environment.BG_COLOR
    env.background_color=Color(.075,.095,.125)
    env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color=Color(.55,.61,.70)
    env.ambient_light_energy=.92
    env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
    preview_env.environment=env
    world.add_child(preview_env)
    _add_portrait_stage(world)

    var scene:PackedScene=load("res://assets/hero/hero_base_body.glb")
    portrait_model=scene.instantiate() as Node3D
    world.add_child(portrait_model)
    portrait_model.position=Vector3(0,-.52,0)
    portrait_piece_roots={"head":[],"chest":[],"shoulders":[],"hands":[],"feet":[],"pants":[]}
    portrait_item_variants={}
    portrait_base_loin_nodes=[]
    _collect_portrait_equipment(portrait_model)
    portrait_skeleton=_find_portrait_skeleton(portrait_model)
    portrait_animation_player=_find_portrait_animation_player(portrait_model)
    _apply_portrait_leg_mass()
    var axe_tool:=_add_portrait_axe()
    _add_portrait_aliases(axe_tool,["forester_axe","quest_forester_axe"])
    _add_portrait_tool("starter_pickaxe","res://assets/items/pickaxe.glb",.34,Vector3(.45,.76,.18),Vector3.ZERO)
    _add_portrait_tool("starter_fishing_pole","res://assets/items/fishing_pole.glb",.50,Vector3(.43,.76,.18))
    var sword_tool:=_add_portrait_tool("royal_vanguard_sword","res://assets/equipment/royal_vanguard_sword.glb",1.0,Vector3(.375,1.175,.257),Vector3(-.12,.05,-.12))
    _add_portrait_aliases(sword_tool,["iron_sword"])
    var shield_tool:=_add_portrait_tool("royal_vanguard_shield","res://assets/equipment/royal_vanguard_shield.glb",1.0,Vector3(-.333,1.178,.334),Vector3(-.08,-.14,.10))
    _add_portrait_aliases(shield_tool,["oak_shield"])
    _add_portrait_torch()

    var light:=DirectionalLight3D.new()
    light.rotation=Vector3(-.52,-.72,0)
    light.light_energy=1.55
    light.shadow_enabled=true
    world.add_child(light)
    var fill:=DirectionalLight3D.new()
    fill.rotation=Vector3(-.16,.72,0)
    fill.light_color=Color(.46,.58,.82)
    fill.light_energy=.48
    world.add_child(fill)
    var rim:=DirectionalLight3D.new()
    rim.rotation=Vector3(-.28,2.5,0)
    rim.light_color=Color(1.0,.66,.34)
    rim.light_energy=.78
    world.add_child(rim)
    portrait_camera=Camera3D.new()
    portrait_camera.position=Vector3(0,1.02,3.15)
    portrait_camera.fov=48.0
    world.add_child(portrait_camera)
    portrait_camera.look_at(Vector3(0,.64,0))
    portrait_camera.current=true

    var rotate_hint:=Label.new()
    rotate_hint.text="LEFT-DRAG HERO TO ROTATE  |  MOUSE WHEEL TO ZOOM"
    rotate_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    rotate_hint.add_theme_font_size_override("font_size",10)
    rotate_hint.add_theme_color_override("font_color",Color(.55,.65,.78))
    center.add_child(rotate_hint)


func _add_portrait_stage(world:Node3D)->void:
    var stone:=StandardMaterial3D.new()
    stone.albedo_color=Color(.19,.23,.28)
    stone.roughness=.94
    var stone_light:=StandardMaterial3D.new()
    stone_light.albedo_color=Color(.29,.33,.37)
    stone_light.roughness=.90
    var royal:=StandardMaterial3D.new()
    royal.albedo_color=Color(.28,.035,.045)
    royal.roughness=.86
    var floor:=MeshInstance3D.new()
    var floor_mesh:=PlaneMesh.new()
    floor_mesh.size=Vector2(10,10)
    floor.mesh=floor_mesh
    floor.position.y=-.69
    floor.material_override=stone
    world.add_child(floor)
    var dais:=MeshInstance3D.new()
    var dais_mesh:=CylinderMesh.new()
    dais_mesh.top_radius=1.25
    dais_mesh.bottom_radius=1.42
    dais_mesh.height=.16
    dais_mesh.radial_segments=32
    dais.mesh=dais_mesh
    dais.position=Vector3(0,-.61,0)
    dais.material_override=stone_light
    world.add_child(dais)
    var backdrop:=MeshInstance3D.new()
    var backdrop_mesh:=BoxMesh.new()
    backdrop_mesh.size=Vector3(7.5,5.2,.28)
    backdrop.mesh=backdrop_mesh
    backdrop.position=Vector3(0,1.65,-1.55)
    backdrop.material_override=stone
    world.add_child(backdrop)
    for side in [-1.0,1.0]:
        var column:=MeshInstance3D.new()
        var column_mesh:=CylinderMesh.new()
        column_mesh.top_radius=.24
        column_mesh.bottom_radius=.31
        column_mesh.height=4.6
        column_mesh.radial_segments=12
        column.mesh=column_mesh
        column.position=Vector3(side*2.25,1.2,-1.34)
        column.material_override=stone_light
        world.add_child(column)
        var banner:=MeshInstance3D.new()
        var banner_mesh:=BoxMesh.new()
        banner_mesh.size=Vector3(.72,2.3,.06)
        banner.mesh=banner_mesh
        banner.position=Vector3(side*1.45,1.75,-1.36)
        banner.material_override=royal
        world.add_child(banner)


func _rotate_button(parent:Container,text_value:String,amount:float,reset:=false)->void:
    var button:=Button.new()
    button.text=text_value
    button.custom_minimum_size=Vector2(92,28)
    button.add_theme_font_size_override("font_size",10)
    button.pressed.connect(func():
        if not is_instance_valid(portrait_model):return
        if reset:portrait_model.rotation=Vector3.ZERO
        else:portrait_model.rotate_y(amount)
    )
    parent.add_child(button)


func _portrait_input(event:InputEvent)->void:
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        _rotating=event.pressed
        portrait_holder.accept_event()
    elif event is InputEventMouseMotion and _rotating and is_instance_valid(portrait_model):
        portrait_model.rotate_y(-event.relative.x*.012)
        portrait_holder.accept_event()
    elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and is_instance_valid(portrait_camera):
        portrait_camera.position.z=clampf(portrait_camera.position.z+(-.18 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .18),2.45,4.0)
        portrait_holder.accept_event()


func _collect_portrait_equipment(node:Node)->void:
    var node_name:=String(node.name)
    if node_name.begins_with("Loincloth") or node_name.begins_with("LoinTie") or node_name.begins_with("LoinKnot") or node_name.begins_with("LoinTail"):
        portrait_base_loin_nodes.append(node)
    if node_name.begins_with("RoyalArmor_"):
        for slot in ["head","chest","shoulders","hands","feet","pants"]:
            if node_name.begins_with("RoyalArmor_%s_"%slot):
                portrait_piece_roots[slot].append(node)
                node.visible=false
                break
    elif node_name.begins_with("RoyalStaff_"):
        _add_portrait_variant("royal_vanguard_staff",node)
    elif node_name.begins_with("RoyalVanguardSword"):
        node.visible=false
    elif node_name.begins_with("RoyalVanguardShield"):
        node.visible=false
    for child in node.get_children():
        _collect_portrait_equipment(child)


func _add_portrait_variant(item_id:String,node:Node)->void:
    if not portrait_item_variants.has(item_id):portrait_item_variants[item_id]=[]
    portrait_item_variants[item_id].append(node)
    node.visible=false


func _add_portrait_tool(item_id:String,path:String,scale_value:float,mount_position:Vector3,rotation_value:Vector3=Vector3(0,0,PI))->Node3D:
    var scene:=load(path) as PackedScene
    if scene==null or not is_instance_valid(portrait_model):return null
    # Inventory previews are a static dressing view. Fixed mounts produce a
    # much cleaner silhouette than inheriting the imported T-pose hand-bone
    # axes, and still rotate with the hero because they share portrait_model.
    var tool:=scene.instantiate() as Node3D
    tool.position=mount_position
    tool.rotation=rotation_value
    tool.scale=Vector3.ONE*scale_value
    portrait_model.add_child(tool)
    _add_portrait_variant(item_id,tool)
    return tool


func _add_portrait_axe()->Node3D:
    if not is_instance_valid(portrait_model):return null
    var axe:=Node3D.new()
    axe.name="AxePreview"
    axe.position=Vector3(.45,.78,.18)
    axe.rotation=Vector3(0,-.12,-.05)
    portrait_model.add_child(axe)
    var wood:=StandardMaterial3D.new()
    wood.albedo_color=Color(.30,.13,.045)
    wood.roughness=.96
    var steel:=StandardMaterial3D.new()
    steel.albedo_color=Color(.43,.49,.53)
    steel.metallic=.72
    steel.roughness=.34
    var handle:=MeshInstance3D.new()
    var handle_mesh:=CylinderMesh.new()
    handle_mesh.top_radius=.026
    handle_mesh.bottom_radius=.034
    handle_mesh.height=.80
    handle_mesh.radial_segments=10
    handle.mesh=handle_mesh
    handle.position.y=-.02
    handle.material_override=wood
    axe.add_child(handle)
    var eye:=MeshInstance3D.new()
    var eye_mesh:=BoxMesh.new()
    eye_mesh.size=Vector3(.17,.12,.105)
    eye.mesh=eye_mesh
    eye.position=Vector3(0,.35,0)
    eye.material_override=steel
    axe.add_child(eye)
    var blade:=MeshInstance3D.new()
    blade.mesh=_make_portrait_axe_blade_mesh()
    blade.position=Vector3(0,.35,0)
    blade.material_override=steel
    axe.add_child(blade)
    var pommel:=MeshInstance3D.new()
    var pommel_mesh:=CylinderMesh.new()
    pommel_mesh.top_radius=.042
    pommel_mesh.bottom_radius=.047
    pommel_mesh.height=.055
    pommel_mesh.radial_segments=10
    pommel.mesh=pommel_mesh
    pommel.position.y=-.43
    pommel.material_override=steel
    axe.add_child(pommel)
    _add_portrait_variant("starter_wood_axe",axe)
    return axe


func _make_portrait_axe_blade_mesh()->ArrayMesh:
    var st:=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var front:=[Vector3(.045,-.075,-.045),Vector3(.34,-.17,-.045),Vector3(.34,.17,-.045),Vector3(.045,.075,-.045)]
    var back:=[Vector3(.045,-.075,.045),Vector3(.34,-.17,.045),Vector3(.34,.17,.045),Vector3(.045,.075,.045)]
    for vertex in [front[0],front[1],front[2],front[0],front[2],front[3]]:st.add_vertex(vertex)
    for vertex in [back[2],back[1],back[0],back[3],back[2],back[0]]:st.add_vertex(vertex)
    for edge in range(4):
        var next:=(edge+1)%4
        for vertex in [front[edge],back[edge],back[next],front[edge],back[next],front[next]]:st.add_vertex(vertex)
    st.generate_normals()
    return st.commit()


func _add_portrait_aliases(tool:Node3D,item_ids:Array)->void:
    if not is_instance_valid(tool):return
    for item_id in item_ids:_add_portrait_variant(str(item_id),tool)


func _add_portrait_torch()->void:
    if not is_instance_valid(portrait_model):return
    var torch:=Node3D.new()
    torch.name="TravelerTorchPreview"
    torch.position=Vector3(-.43,.72,.16)
    portrait_model.add_child(torch)
    var wood:=StandardMaterial3D.new();wood.albedo_color=Color(.25,.105,.035);wood.roughness=.9
    var iron:=StandardMaterial3D.new();iron.albedo_color=Color(.18,.20,.21);iron.metallic=.55;iron.roughness=.42
    var flame:=StandardMaterial3D.new();flame.albedo_color=Color(1.0,.38,.045);flame.emission_enabled=true;flame.emission=Color(1.0,.14,.018);flame.emission_energy_multiplier=2.4
    var shaft:=MeshInstance3D.new();var shaft_mesh:=CylinderMesh.new();shaft_mesh.top_radius=.027;shaft_mesh.bottom_radius=.037;shaft_mesh.height=.74;shaft.mesh=shaft_mesh;shaft.position.y=.12;shaft.material_override=wood;torch.add_child(shaft)
    var collar:=MeshInstance3D.new();var collar_mesh:=CylinderMesh.new();collar_mesh.top_radius=.062;collar_mesh.bottom_radius=.062;collar_mesh.height=.085;collar.mesh=collar_mesh;collar.position.y=.52;collar.material_override=iron;torch.add_child(collar)
    var fire:=MeshInstance3D.new();var fire_mesh:=SphereMesh.new();fire_mesh.radius=.052;fire_mesh.height=.16;fire_mesh.radial_segments=8;fire_mesh.rings=5;fire.mesh=fire_mesh;fire.position.y=.65;fire.material_override=flame;torch.add_child(fire)
    _add_portrait_variant("traveler_torch",torch)


func _find_portrait_skeleton(node:Node)->Skeleton3D:
    if node is Skeleton3D:return node as Skeleton3D
    for child in node.get_children():
        var result:=_find_portrait_skeleton(child)
        if result:return result
    return null


func _find_portrait_animation_player(node:Node)->AnimationPlayer:
    if node is AnimationPlayer:return node as AnimationPlayer
    for child in node.get_children():
        var result:=_find_portrait_animation_player(child)
        if result:return result
    return null


func _apply_portrait_leg_mass()->void:
    if not is_instance_valid(portrait_skeleton):return
    for bone_name in ["thigh.L","thigh.R"]:
        var index:=portrait_skeleton.find_bone(bone_name)
        if index>=0:portrait_skeleton.set_bone_pose_scale(index,Vector3(.96,1.0,.96))
    for bone_name in ["shin.L","shin.R"]:
        var index:=portrait_skeleton.find_bone(bone_name)
        if index>=0:portrait_skeleton.set_bone_pose_scale(index,Vector3(.97,1.0,.97))


func _sync_portrait_pose(mainhand:String,offhand:String)->void:
    if not is_instance_valid(portrait_animation_player):return
    var target:=&"Idle"
    if mainhand=="royal_vanguard_staff":
        target=&"StaffIdle"
    elif mainhand=="royal_vanguard_sword" or offhand=="royal_vanguard_shield":
        target=&"WarriorIdle"
    if not portrait_animation_player.has_animation(target):return
    portrait_animation_player.play(target)
    portrait_animation_player.seek(0.0,true)
    portrait_animation_player.pause()


func _unhandled_input(event:InputEvent)->void:
    if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_B,KEY_I,KEY_ESCAPE]:
        close_requested.emit()
        get_viewport().set_input_as_handled()
