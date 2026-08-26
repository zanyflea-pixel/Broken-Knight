extends Control

signal close_requested

var hero:Node
var director:Node
var station:Dictionary={}
var recipe_root:VBoxContainer
var detail:RichTextLabel
var status:Label
var selected_recipe:String=""


func configure(hero_node:Node,director_node:Node)->void:
    hero=hero_node;director=director_node


func _ready()->void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    var dim:=ColorRect.new();dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);dim.color=Color(0,0,0,.76);add_child(dim)
    var panel:=PanelContainer.new();panel.name="CraftPanel";panel.set_anchors_preset(Control.PRESET_CENTER);panel.position=Vector2(-510,-320);panel.size=Vector2(1020,640);add_child(panel)
    var margin:=MarginContainer.new();margin.name="PageMargin"
    for side in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_%s"%side,22)
    panel.add_child(margin)
    var page:=VBoxContainer.new();page.name="Page";page.add_theme_constant_override("separation",12);margin.add_child(page)
    var heading:=Label.new();heading.name="Heading";heading.text="TOWN CRAFTING YARD";heading.add_theme_font_size_override("font_size",27);heading.add_theme_color_override("font_color",Color(1,.78,.28));page.add_child(heading)
    var material_line:=Label.new();material_line.name="Materials";material_line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;material_line.add_theme_color_override("font_color",Color(.70,.82,.68));page.add_child(material_line)
    var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.split_offset=560;page.add_child(split)
    var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(560,0);split.add_child(scroll)
    recipe_root=VBoxContainer.new();recipe_root.size_flags_horizontal=Control.SIZE_EXPAND_FILL;recipe_root.add_theme_constant_override("separation",6);scroll.add_child(recipe_root)
    var right:=VBoxContainer.new();right.custom_minimum_size=Vector2(360,0);right.add_theme_constant_override("separation",12);split.add_child(right)
    detail=RichTextLabel.new();detail.bbcode_enabled=true;detail.fit_content=false;detail.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(detail)
    var craft:=Button.new();craft.text="CRAFT SELECTED ITEM";craft.custom_minimum_size=Vector2(0,46);craft.pressed.connect(_craft_selected);right.add_child(craft)
    status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size=Vector2(0,44);right.add_child(status)
    var close:=Button.new();close.text="RETURN TO WORLD  [ESC]";close.custom_minimum_size=Vector2(0,42);close.pressed.connect(func():close_requested.emit());page.add_child(close)


func show_station(data:Dictionary)->void:
    station=data
    selected_recipe=""
    status.text="Select a recipe."
    refresh()


func refresh()->void:
    if not is_instance_valid(hero) or not is_instance_valid(director):return
    var heading:=get_node_or_null("CraftPanel/PageMargin/Page/Heading") as Label
    if heading:heading.text=str(station.get("name","Town Crafting Yard")).to_upper()
    var materials:=get_node_or_null("CraftPanel/PageMargin/Page/Materials") as Label
    if materials:materials.text="HERBS %d   LOGS %d   ORE %d   SCRAP %d   LEATHER %d   CLOTH %d   STONE %d   RESIN %d   MUSHROOMS %d   CRYSTAL %d   ESSENCE %d"%[hero.herbs,hero.logs,hero.ore,hero.scrap,hero.leather,hero.cloth,hero.stone,hero.resin,hero.mushrooms,hero.crystal,hero.essence]
    for child in recipe_root.get_children():child.queue_free()
    var last_category:=""
    var visible_recipes:=_visible_recipes()
    for recipe in visible_recipes:
        var category:String=recipe.get("category","General")
        if category!=last_category:
            var category_label:=Label.new();category_label.text=category.to_upper();category_label.add_theme_color_override("font_color",Color(.93,.66,.24));category_label.add_theme_font_size_override("font_size",18);recipe_root.add_child(category_label);last_category=category
        var requirement:=_cost_text(recipe.get("cost",{}))
        if not str(recipe.get("ingredient_id","")).is_empty():requirement="1 Raw Fish"
        var button:=Button.new();button.text="%s    —    %s"%[recipe.get("name","Recipe"),requirement];button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.custom_minimum_size=Vector2(0,38);button.disabled=not director.can_craft_recipe(recipe);button.pressed.connect(_select_recipe.bind(str(recipe.id)));recipe_root.add_child(button)
    if selected_recipe.is_empty() and not visible_recipes.is_empty():_select_recipe(str(visible_recipes[0].id))


func _select_recipe(recipe_id:String)->void:
    selected_recipe=recipe_id
    for recipe in _visible_recipes():
        if str(recipe.id)!=recipe_id:continue
        var requirement:=_cost_text(recipe.get("cost",{}))
        if not str(recipe.get("ingredient_id","")).is_empty():requirement="1 Raw Fish"
        detail.text="[color=#f2c45d][font_size=23][b]%s[/b][/font_size][/color]\n\n%s\n\n[color=#91b9d8]Requires[/color]\n%s\n\n[color=#8fd09b]%s[/color]"%[recipe.name,recipe.get("description",""),requirement,"Ready to craft" if director.can_craft_recipe(recipe) else "Ingredients missing"]
        break


func _visible_recipes()->Array:
    var recipes:Array=director.get_recipes()
    if str(station.get("kind",""))!="cooking":return recipes
    return recipes.filter(func(recipe:Dictionary)->bool:return str(recipe.get("category",""))=="Cooking")


func _craft_selected()->void:
    if selected_recipe.is_empty():return
    status.text=director.craft_recipe(selected_recipe)
    refresh()


func _cost_text(cost:Dictionary)->String:
    var parts:Array[String]=[]
    for kind in cost:parts.append("%d %s"%[int(cost[kind]),str(kind).capitalize()])
    return "  •  ".join(parts)


func _unhandled_input(event:InputEvent)->void:
    if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
        close_requested.emit();get_viewport().set_input_as_handled()
