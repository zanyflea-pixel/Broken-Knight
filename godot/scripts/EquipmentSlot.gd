extends PanelContainer

static var _item_icon_cache:Dictionary={}

var hero:Node
var menu:Control
var origin:="bag"
var slot_key:=""
var item:Dictionary={}


func setup(hero_node:Node,menu_node:Control,source:String,key:String,data:Dictionary)->void:
    hero=hero_node
    menu=menu_node
    origin=source
    slot_key=key
    item=data
    mouse_filter=Control.MOUSE_FILTER_STOP
    if origin=="bag":_build_bag_tile()
    else:_build_equipment_row()


func _build_bag_tile()->void:
    custom_minimum_size=Vector2(68,72)
    var box:=VBoxContainer.new()
    box.alignment=BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",1)
    add_child(box)
    var icon:=TextureRect.new()
    icon.custom_minimum_size=Vector2(46,46)
    icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    box.add_child(icon)
    var label:=Label.new()
    label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
    label.custom_minimum_size=Vector2(64,15)
    label.add_theme_font_size_override("font_size",8)
    box.add_child(label)
    if item.is_empty():
        label.text=slot_key
        modulate=Color(.35,.40,.48)
        return
    icon.texture=_item_icon_texture(item)
    label.text=str(item.get("name","Item"))
    var quantity:=maxi(1,int(item.get("quantity",1)))
    if quantity>1:
        var badge:=Label.new()
        badge.text="x%d"%quantity
        badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
        badge.vertical_alignment=VERTICAL_ALIGNMENT_TOP
        badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        badge.offset_right=-5
        badge.offset_top=4
        badge.add_theme_font_size_override("font_size",12)
        badge.add_theme_color_override("font_color",Color(1,.88,.42))
        badge.add_theme_color_override("font_outline_color",Color(.02,.025,.035))
        badge.add_theme_constant_override("outline_size",4)
        badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
        add_child(badge)
    tooltip_text="%s%s\n%s\nArmor +%d   HP +%d   Power +%d"%[
        item.get("name","Item"),
        " x%d"%quantity if quantity>1 else "",
        item.get("description",""),
        item.get("armor",0),
        item.get("hp",0),
        item.get("power",0)
    ]


func _build_equipment_row()->void:
    custom_minimum_size=Vector2(224,41)
    var box:=HBoxContainer.new()
    box.add_theme_constant_override("separation",6)
    add_child(box)
    var icon:=TextureRect.new()
    icon.custom_minimum_size=Vector2(36,36)
    icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    box.add_child(icon)
    var label:=Label.new()
    label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size=Vector2(170,0)
    label.add_theme_font_size_override("font_size",9)
    box.add_child(label)
    if item.is_empty():
        label.text=slot_key.capitalize()+" - Empty"
        modulate=Color(.58,.63,.70)
    else:
        icon.texture=_item_icon_texture(item)
        label.text="%s\n%s | Armor +%d | Power +%d"%[
            item.get("name","Item"),slot_key.capitalize(),
            item.get("armor",0),item.get("power",0)
        ]


func _get_drag_data(_at:Vector2)->Variant:
    if item.is_empty():return null
    var preview:=TextureRect.new()
    preview.texture=_item_icon_texture(item)
    preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.custom_minimum_size=Vector2(46,46)
    preview.size=Vector2(46,46)
    set_drag_preview(preview)
    return {"item_id":item.get("id",""),"origin":origin,"slot":slot_key}


func _can_drop_data(_at:Vector2,data:Variant)->bool:
    if not data is Dictionary:return false
    if origin=="equip":
        for bag_item in hero.bag_slots:
            if bag_item.get("id","")==data.get("item_id",""):
                return bag_item.get("slot","chest")==slot_key
    return origin=="bag" and data.get("origin","")=="equip"


func _drop_data(_at:Vector2,data:Variant)->void:
    if origin=="equip":hero.equip_item_id(data.item_id)
    elif data.origin=="equip":hero.unequip_slot(data.slot)
    menu.refresh()


func _gui_input(event:InputEvent)->void:
    if event is InputEventMouseButton and event.double_click and not item.is_empty():
        if origin=="bag":
            if hero.has_method("use_bag_item_id"):hero.use_bag_item_id(item.id)
            else:hero.equip_item_id(item.id)
        else:
            hero.unequip_slot(slot_key)
        menu.refresh()


func _item_icon_texture(data:Dictionary)->Texture2D:
    var visual_kind:=_visual_kind(data)
    var unique_key:="%s|%s"%[visual_kind,str(data.get("name","Item"))]
    if _item_icon_cache.has(unique_key):return _item_icon_cache[unique_key]
    var hue:=float(abs(unique_key.hash())%360)/360.0
    var accent:=Color.from_hsv(hue,.48,.88).to_html(false)
    var shape:=_svg_shape(visual_kind,accent)
    var svg:="""<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#26384c"/><stop offset=".52" stop-color="#101a28"/><stop offset="1" stop-color="#070b12"/></linearGradient>
<radialGradient id="glow"><stop stop-color="#%s" stop-opacity=".34"/><stop offset="1" stop-color="#%s" stop-opacity="0"/></radialGradient>
<filter id="shadow"><feDropShadow dx="0" dy="3" stdDeviation="2" flood-color="#000814" flood-opacity=".8"/></filter>
</defs>
<rect x="2" y="2" width="92" height="92" rx="15" fill="url(#bg)" stroke="#9aabc0" stroke-width="2"/>
<rect x="6" y="6" width="84" height="84" rx="12" fill="none" stroke="#%s" stroke-opacity=".48" stroke-width="2"/>
<circle cx="48" cy="43" r="37" fill="url(#glow)"/>
<g filter="url(#shadow)">
%s
</g>
<path d="M18 82Q48 89 78 82" fill="none" stroke="#d4e1ef" stroke-opacity=".25" stroke-width="2"/>
</svg>"""%[accent,accent,accent,shape]
    var image:=Image.new()
    var error:=image.load_svg_from_string(svg,1.5)
    if error!=OK:return _legacy_icon(int(data.get("icon",5)))
    var texture:=ImageTexture.create_from_image(image)
    _item_icon_cache[unique_key]=texture
    return texture


func _visual_kind(data:Dictionary)->String:
    var combined:=(str(data.get("visual",""))+" "+str(data.get("id",""))+" "+str(data.get("name",""))+" "+str(data.get("material",""))).to_lower()
    for kind in ["fishing","pickaxe","axe","sword","shield","staff","torch","fish","berries","log","ore","crystal","herb","mushroom","resin","leather","cloth","stone","scrap","essence","key","potion"]:
        if kind in combined:return kind
    var slot:=str(data.get("slot",""))
    if slot=="head":return "helmet"
    if slot in ["chest","shoulders"]:return "armor"
    if slot=="hands":return "gloves"
    if slot=="feet":return "boots"
    if slot=="pants":return "pants"
    if slot=="consumable":return "potion"
    return "pack"


func _svg_shape(kind:String,accent:String)->String:
    var metal:="#d8e1e6"
    var dark:="#3c2d24"
    match kind:
        "sword":return '<path d="M68 18L75 25 50 57 42 49Z" fill="%s"/><path d="M37 48L49 60 44 65 32 53Z" fill="#d7a83c"/><path d="M39 61L30 70" stroke="%s" stroke-width="7" stroke-linecap="round"/>'%[metal,dark]
        "axe":return '<path d="M42 27L72 21 76 41 47 47Z" fill="%s"/><path d="M47 39L31 76" stroke="%s" stroke-width="8" stroke-linecap="round"/>'%[metal,dark]
        "pickaxe":return '<path d="M19 34Q48 18 78 34L72 44Q48 33 25 44Z" fill="%s" stroke="#9da9ae" stroke-width="3"/><path d="M49 34L38 79" stroke="%s" stroke-width="8" stroke-linecap="round"/><path d="M20 34L12 41M78 34L86 42" stroke="#dce5e8" stroke-width="4" stroke-linecap="round"/>'%[metal,dark]
        "fishing":return '<path d="M28 72Q41 26 67 19" fill="none" stroke="%s" stroke-width="6" stroke-linecap="round"/><path d="M66 20Q72 43 62 61Q57 70 66 76" fill="none" stroke="#d9d1ad" stroke-width="2"/><path d="M66 76q-10 3-8-7" fill="none" stroke="%s" stroke-width="3"/>'%[dark,metal]
        "shield":return '<path d="M48 17L75 28V49Q72 70 48 80Q24 70 21 49V28Z" fill="#%s" stroke="%s" stroke-width="4"/><path d="M48 24V72M29 43H67" stroke="#e4bd51" stroke-width="4"/>'%[accent,metal]
        "staff":return '<path d="M37 77L58 28" stroke="%s" stroke-width="7" stroke-linecap="round"/><path d="M58 28L70 18M58 28L48 16" stroke="#d8b64e" stroke-width="5"/><circle cx="59" cy="27" r="8" fill="#b92635" stroke="#ffd66b" stroke-width="3"/>'%dark
        "torch":return '<path d="M43 47L52 78" stroke="%s" stroke-width="9"/><path d="M35 46L56 42 54 54 39 57Z" fill="#6a4321"/><path d="M46 43Q27 31 44 16Q60 27 53 43Z" fill="#f19a25"/><path d="M46 38Q38 31 47 23Q55 31 51 39Z" fill="#ffe06c"/>'%dark
        "fish":return '<path d="M22 51Q40 27 67 43L80 33 78 59 67 51Q42 70 22 51Z" fill="#%s" stroke="#d5edf1" stroke-width="3"/><circle cx="60" cy="43" r="3" fill="#101820"/>'%accent
        "berries":return '<path d="M49 32Q52 19 65 18" fill="none" stroke="#557c37" stroke-width="5"/><circle cx="35" cy="49" r="13" fill="#9f294b"/><circle cx="55" cy="45" r="14" fill="#bd3158"/><circle cx="48" cy="63" r="14" fill="#79213f"/>'
        "log":return '<rect x="19" y="38" width="59" height="27" rx="12" fill="#704928" stroke="#b37b3b" stroke-width="4"/><circle cx="72" cy="51" r="11" fill="#b77f42"/><path d="M67 51q5-7 10 0q-5 7-10 0" fill="none" stroke="#6c4929" stroke-width="2"/>'
        "ore","scrap","stone":return '<path d="M20 66L29 34 48 23 73 35 79 61 59 77 34 75Z" fill="#%s" stroke="%s" stroke-width="4"/><path d="M31 58L45 35 66 40M45 35L54 68" fill="none" stroke="#f1f1e3" stroke-opacity=".35" stroke-width="3"/>'%[accent,metal]
        "crystal","essence":return '<path d="M48 14L69 39 59 79 36 82 25 43Z" fill="#%s" stroke="#c9f5ff" stroke-width="4"/><path d="M48 15L45 75M26 43L67 39" fill="none" stroke="#ffffff" stroke-opacity=".45" stroke-width="3"/>'%accent
        "herb":return '<path d="M48 78Q45 47 50 20" fill="none" stroke="#699c42" stroke-width="5"/><path d="M47 51Q22 46 24 29Q45 30 48 47M49 39Q70 27 75 42Q62 56 49 50" fill="#6eaa4a" stroke="#b0d47d" stroke-width="2"/>'
        "mushroom":return '<path d="M41 47H56L61 76H36Z" fill="#dcc6a3"/><path d="M20 49Q25 17 49 17Q75 18 78 49Z" fill="#a94a36" stroke="#e6b17b" stroke-width="3"/><circle cx="38" cy="31" r="4" fill="#f2d6af"/><circle cx="59" cy="39" r="5" fill="#f2d6af"/>'
        "resin","potion":return '<path d="M38 20H59L57 34Q70 44 67 66Q64 80 48 81Q31 80 29 65Q27 45 40 34Z" fill="#%s" stroke="%s" stroke-width="4"/><path d="M34 58Q48 49 63 58V69Q57 76 48 76Q38 75 33 68Z" fill="#ef7f37"/>'%[accent,metal]
        "leather","cloth":return '<path d="M25 22Q48 30 71 22L77 70Q58 82 19 70Z" fill="#%s" stroke="#d6b98b" stroke-width="4"/><path d="M29 36L68 61M67 36L29 61" stroke="#f0ddbd" stroke-opacity=".45" stroke-width="3"/>'%accent
        "key":return '<circle cx="34" cy="38" r="15" fill="none" stroke="#e2bd55" stroke-width="7"/><path d="M44 49L73 77M59 63L66 56M66 70L73 63" stroke="#e2bd55" stroke-width="7" stroke-linecap="round"/>'
        "helmet":return '<path d="M25 55Q25 21 48 18Q72 21 72 55V72H56V47H43V72H25Z" fill="#%s" stroke="%s" stroke-width="4"/>'%[accent,metal]
        "armor":return '<path d="M31 20L43 28H53L66 20L79 37 68 48V78H28V48L17 37Z" fill="#%s" stroke="%s" stroke-width="4"/><path d="M37 32L48 42 59 32" fill="none" stroke="#e6bd50" stroke-width="4"/>'%[accent,metal]
        "gloves":return '<path d="M27 72L22 46 30 28 37 44 40 21 47 44 52 25 57 52 69 44 66 68 52 79Z" fill="#%s" stroke="%s" stroke-width="3"/>'%[accent,metal]
        "boots":return '<path d="M28 18H48L47 61Q57 65 72 68V80H25Z" fill="#%s" stroke="%s" stroke-width="4"/>'%[accent,dark]
        "pants":return '<path d="M29 19H67L63 78H48L46 47 42 78H25Z" fill="#%s" stroke="%s" stroke-width="4"/>'%[accent,metal]
        _:return '<path d="M23 34L48 20 73 34V71L48 82 23 71Z" fill="#%s" stroke="%s" stroke-width="4"/><path d="M23 34L48 49 73 34M48 49V82" fill="none" stroke="#e7d39d" stroke-width="3"/>'%[accent,metal]


func _legacy_icon(index:int)->Texture2D:
    if index==6:return load("res://assets/concepts/royal_vanguard_staff_concept.png")
    if index==7:return load("res://assets/concepts/royal_vanguard_pants_concept.png")
    var atlas:=AtlasTexture.new()
    atlas.atlas=load("res://assets/ui/equipment_icons_v1.png")
    var col:=index%3
    var row:=index/3
    atlas.region=Rect2(col*416,row*624,416,624)
    return atlas
