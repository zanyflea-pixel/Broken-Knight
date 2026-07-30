extends Control

signal close_requested

var director: Node
var main: Node
var status_label: Label
var one_hit_button:Button
var god_mode_button:Button
var _status_accumulator:=0.0

func configure(main_node: Node, gameplay_director: Node) -> void:
    main = main_node
    director = gameplay_director

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _build_interface()

func _build_interface() -> void:
    var dim:=ColorRect.new(); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); dim.color=Color(0,0,0,.68); dim.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(dim)
    var panel:=PanelContainer.new(); panel.set_anchors_preset(Control.PRESET_CENTER); panel.position=Vector2(-380,-260); panel.size=Vector2(760,520); add_child(panel)
    var margin:=MarginContainer.new(); margin.add_theme_constant_override("margin_left",24); margin.add_theme_constant_override("margin_right",24); margin.add_theme_constant_override("margin_top",20); margin.add_theme_constant_override("margin_bottom",20); panel.add_child(margin)
    var content:=VBoxContainer.new(); content.add_theme_constant_override("separation",10); margin.add_child(content)
    var title:=Label.new(); title.text="BROKEN KNIGHT  •  ADMIN TOOLS"; title.add_theme_font_size_override("font_size",24); title.add_theme_color_override("font_color",Color(1,.81,.35)); content.add_child(title)
    var hint:=Label.new(); hint.text="G, F8, or Esc closes this panel. Changes apply immediately."; hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.add_theme_color_override("font_color",Color(.68,.73,.80)); content.add_child(hint)
    content.add_child(HSeparator.new())
    var grid:=GridContainer.new(); grid.columns=3; grid.add_theme_constant_override("h_separation",10); grid.add_theme_constant_override("v_separation",10); content.add_child(grid)
    _button(grid,"Spawn Enemy",func(): director.admin_spawn(1,false))
    _button(grid,"Heal + Restore",func(): director.admin_heal())
    one_hit_button=_button(grid,"One-Hit Kill: OFF",func(): director.admin_toggle_one_hit_kill())
    god_mode_button=_button(grid,"God Mode: OFF",func(): director.admin_toggle_god_mode())
    _button(grid,"+250 Gold",func(): director.admin_add_gold(250))
    _button(grid,"Gain One Level",func(): director.admin_gain_level())
    _button(grid,"All Skills +1",func(): director.admin_gain_all_skills())
    _button(grid,"Equip Royal Armor",func(): director.admin_equip_armor())
    _button(grid,"Switch Mage / Warrior",func(): director.admin_switch_class())
    _button(grid,"Quick Save",func(): director.admin_save())
    _button(grid,"Quick Load",func(): director.admin_load())
    content.add_child(HSeparator.new())
    status_label=Label.new(); status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status_label.custom_minimum_size=Vector2(0,45); content.add_child(status_label)
    var close:=Button.new(); close.text="Close Admin Menu"; close.custom_minimum_size=Vector2(0,40); close.pressed.connect(func(): close_requested.emit()); content.add_child(close)

func _process(delta: float) -> void:
    _status_accumulator+=delta
    if _status_accumulator<.25:return
    _status_accumulator=0.0
    if visible and is_instance_valid(director) and status_label:
        var state:Dictionary=director.get_admin_status()
        var one_hit:bool=state.get("one_hit_kill",false)
        var god_mode:bool=state.get("god_mode",false)
        one_hit_button.text="One-Hit Kill: %s"%("ON" if one_hit else "OFF")
        god_mode_button.text="God Mode: %s"%("ON" if god_mode else "OFF")
        one_hit_button.modulate=Color(1.0,.72,.26) if one_hit else Color.WHITE
        god_mode_button.modulate=Color(.42,.88,1.0) if god_mode else Color.WHITE
        status_label.text="Enemies: %d   Loot: %d   Gold: %d   Level: %d\nCombat — One-Hit %s   God Mode %s\nMaterials — Herbs %d  Scrap %d  Ore %d  Essence %d" % [state.enemies,state.loot,state.gold,state.level,"ON" if one_hit else "OFF","ON" if god_mode else "OFF",state.herbs,state.scrap,state.ore,state.essence]

func _unhandled_input(event: InputEvent) -> void:
    if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_G,KEY_F8,KEY_ESCAPE]:
        close_requested.emit()
        get_viewport().set_input_as_handled()

func _button(grid: GridContainer, label_text: String, action: Callable) -> Button:
    var button:=Button.new(); button.text=label_text; button.custom_minimum_size=Vector2(218,42); button.pressed.connect(action); grid.add_child(button)
    return button
