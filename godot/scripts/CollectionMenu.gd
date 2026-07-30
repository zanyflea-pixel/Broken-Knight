extends Control

signal close_requested

@export_enum("bag", "skills", "quests") var mode := "bag"
var hero: Node
var director: Node
var title: Label
var body: RichTextLabel


func configure(h: Node, d: Node) -> void:
    hero = h
    director = d


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0, 0, 0, .7)
    add_child(dim)
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position = Vector2(-390, -300)
    panel.size = Vector2(780, 600)
    add_child(panel)
    var margin := MarginContainer.new()
    for side in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_%s"%side,24 if side in ["left","right"] else 20)
    panel.add_child(margin)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    margin.add_child(box)
    title = Label.new()
    title.add_theme_font_size_override("font_size", 24)
    title.add_theme_color_override("font_color", Color(1, .80, .32))
    box.add_child(title)
    body = RichTextLabel.new()
    body.bbcode_enabled = true
    body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.scroll_active = true
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(body)
    var close := Button.new()
    close.text = "Close  [Esc]"
    close.custom_minimum_size = Vector2(0, 42)
    close.pressed.connect(func(): close_requested.emit())
    box.add_child(close)


func refresh() -> void:
    if not is_instance_valid(hero):return
    if mode == "bag":
        title.text = "BAG - %d / 80 SLOTS" % hero.bag_slots.size()
        var lines := ["[color=#d8c184][b]CRAFTING MATERIALS[/b][/color]", "Herbs %d   Logs %d   Ore %d   Scrap %d   Leather %d   Cloth %d"%[hero.herbs,hero.logs,hero.ore,hero.scrap,hero.leather,hero.cloth],"Stone %d   Resin %d   Mushrooms %d   Crystal %d   Essence %d"%[hero.stone,hero.resin,hero.mushrooms,hero.crystal,hero.essence], "", "[color=#d8c184][b]EQUIPMENT & ITEMS[/b][/color]"]
        for i in range(hero.bag_slots.size()):
            var item: Dictionary = hero.bag_slots[i]
            lines.append("%02d   [b]%s[/b] x%d\n      Armor +%d    HP +%d    Power +%d" % [i + 1, item.name, int(item.get("quantity",1)), item.get("armor", 0), item.get("hp", 0), item.get("power", 0)])
        if hero.bag_slots.is_empty():lines.append("Bag is empty. Defeated enemies can drop armor and materials.")
        body.text = "\n".join(lines)
    elif mode == "skills":
        title.text = "SKILLS"
        var state: Dictionary = director.get_skill_state()
        var lines := ["Skills gain experience whenever they are successfully used."]
        for i in range(4):
            var level := int(state.levels[i])
            var need := level * 8
            var next_unlock := "Level 10: final mastery" if level >= 5 and level < 10 else ("Level 5: first mastery" if level < 5 else "Mastery active")
            lines.append("[b]%d - %s[/b]\n      Level %d    XP %d / %d\n      [color=#8fd8ff]%s[/color]    %s" % [i + 1, state.names[i], level, state.xp[i], need, state.upgrades[i], next_unlock])
        body.text = "\n\n".join(lines)
    else:
        title.text = "QUEST JOURNAL"
        var quest_lines:Array[String]=["[color=#e7bd55][b]THE BROKEN CROWN CHRONICLE[/b][/color]","The king is missing, the old seals are failing, and something beneath the river is calling its champions.",""]
        for quest in director.get_quest_state():
            var available:bool=quest.get("available",true)
            var status:="[color=#83d69a]COMPLETE - REWARD CLAIMED[/color]" if quest.get("claimed",false) else ("%d / %d"%[quest.current,quest.goal] if available else "[color=#78828c]LOCKED - continue the main story[/color]")
            var story:=str(quest.get("story","")) if available else "This chapter has not yet been revealed."
            quest_lines.append("[color=#e7bd55]CHAPTER %s[/color]  [b]%s[/b]    %s\n[color=#a8b7c4]%s[/color]\n%s\n[color=#9fc6e8]Objective: %s\nReward: %s[/color]"%[quest.get("chapter",""),quest.title,status,quest.get("giver",""),story,quest.description,quest.reward])
        quest_lines.append("\n[color=#8292a8]Quest, gathering, crafting, equipment and dungeon progress are saved.[/color]")
        body.text="\n\n".join(quest_lines)


func _unhandled_input(event: InputEvent) -> void:
    var key := KEY_B if mode == "bag" else (KEY_K if mode == "skills" else KEY_J)
    if visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == key or event.keycode == KEY_ESCAPE):
        close_requested.emit()
        get_viewport().set_input_as_handled()
