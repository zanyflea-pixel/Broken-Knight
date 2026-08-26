extends Control

signal close_requested

var player: Node
var director: Node
var vendor: Dictionary = {}
var title_label: Label
var gold_label: Label
var item_root: VBoxContainer
var status_label: Label
var detail_name: Label
var detail_type: Label
var detail_description: Label
var price_label: Label
var quantity: SpinBox
var buy_button: Button
var selected_index := 0


func configure(hero: Node, gameplay_director: Node) -> void:
    player = hero
    director = gameplay_director


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.005, 0.008, 0.014, 0.82)
    add_child(dim)
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position = Vector2(-360, -300)
    panel.size = Vector2(720, 600)
    add_child(panel)
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 24)
    panel.add_child(margin)
    var page := VBoxContainer.new()
    page.add_theme_constant_override("separation", 10)
    margin.add_child(page)
    title_label = Label.new()
    title_label.add_theme_font_size_override("font_size", 25)
    title_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.32))
    page.add_child(title_label)
    gold_label = Label.new()
    gold_label.add_theme_color_override("font_color", Color(0.88, 0.78, 0.50))
    page.add_child(gold_label)
    page.add_child(HSeparator.new())
    var content := HBoxContainer.new()
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 18)
    page.add_child(content)
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(330, 0)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    content.add_child(scroll)
    item_root = VBoxContainer.new()
    item_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    item_root.add_theme_constant_override("separation", 8)
    scroll.add_child(item_root)
    var detail_panel := PanelContainer.new()
    detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(detail_panel)
    var detail_margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        detail_margin.add_theme_constant_override("margin_" + side, 18)
    detail_panel.add_child(detail_margin)
    var detail := VBoxContainer.new()
    detail.add_theme_constant_override("separation", 12)
    detail_margin.add_child(detail)
    detail_type = Label.new()
    detail_type.add_theme_color_override("font_color", Color(0.68, 0.76, 0.88))
    detail.add_child(detail_type)
    detail_name = Label.new()
    detail_name.add_theme_font_size_override("font_size", 22)
    detail_name.add_theme_color_override("font_color", Color(1.0, 0.81, 0.34))
    detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail.add_child(detail_name)
    detail_description = Label.new()
    detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
    detail.add_child(detail_description)
    price_label = Label.new()
    price_label.add_theme_font_size_override("font_size", 18)
    detail.add_child(price_label)
    var quantity_row := HBoxContainer.new()
    detail.add_child(quantity_row)
    var quantity_text := Label.new()
    quantity_text.text = "Quantity"
    quantity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    quantity_row.add_child(quantity_text)
    quantity = SpinBox.new()
    quantity.min_value = 1
    quantity.max_value = 20
    quantity.value = 1
    quantity.custom_minimum_size = Vector2(95, 38)
    quantity.value_changed.connect(func(_value: float): _refresh_detail())
    quantity_row.add_child(quantity)
    buy_button = Button.new()
    buy_button.text = "BUY"
    buy_button.custom_minimum_size = Vector2(0, 48)
    buy_button.pressed.connect(_buy_selected)
    detail.add_child(buy_button)
    status_label = Label.new()
    status_label.custom_minimum_size = Vector2(0, 38)
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
    page.add_child(status_label)
    var close := Button.new()
    close.text = "Leave Shop  [Esc]"
    close.custom_minimum_size = Vector2(0, 42)
    close.pressed.connect(func(): close_requested.emit())
    page.add_child(close)


func show_vendor(vendor_data: Dictionary) -> void:
    vendor = vendor_data
    selected_index = 0
    quantity.value = 1
    status_label.text = str(vendor.get("greeting", "Take a look at my wares."))
    _refresh()


func _refresh() -> void:
    if not is_instance_valid(player) or not item_root:
        return
    title_label.text = "%s  •  %s" % [vendor.get("name", "Merchant"), vendor.get("type_name", "Shop")]
    gold_label.text = "Your gold: %d     Bag: %d / 80" % [player.hero_gold, player.bag_slots.size()]
    for child in item_root.get_children():
        item_root.remove_child(child)
        child.queue_free()
    var inventory: Array = vendor.get("inventory", [])
    for i in range(inventory.size()):
        var item: Dictionary = inventory[i]
        var button := Button.new()
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.custom_minimum_size = Vector2(310, 58)
        button.text = "%s\n%d gold" % [item.get("name", "Item"), item.get("price", 0)]
        button.button_pressed = i == selected_index
        button.pressed.connect(_select_item.bind(i))
        item_root.add_child(button)
    _refresh_detail()


func _select_item(index: int) -> void:
    selected_index = index
    quantity.value = 1
    _refresh()


func _refresh_detail() -> void:
    var inventory: Array = vendor.get("inventory", [])
    if inventory.is_empty() or selected_index < 0 or selected_index >= inventory.size():
        detail_name.text = "No stock"
        detail_type.text = ""
        detail_description.text = "This merchant has nothing available."
        price_label.text = ""
        buy_button.disabled = true
        return
    var item: Dictionary = inventory[selected_index]
    var kind := str(item.get("kind", "goods")).replace("_", " ").capitalize()
    detail_type.text = kind.to_upper()
    detail_name.text = str(item.get("name", "Item"))
    detail_description.text = str(item.get("description", ""))
    var is_unique:bool=str(item.get("kind", "")) in ["armor","repair"]
    quantity.editable = not is_unique
    quantity.max_value = 1 if is_unique else 20
    if is_unique:
        quantity.value = 1
    var total := int(item.get("price", 0)) * int(quantity.value)
    price_label.text = "%d gold each\nTotal: %d gold" % [item.get("price", 0), total]
    buy_button.text = "BUY %d  -  %d GOLD" % [int(quantity.value), total]
    buy_button.disabled = player.hero_gold < total or (str(item.get("kind",""))=="armor" and player.bag_slots.size() >= 80)


func _buy_selected() -> void:
    if not is_instance_valid(director):
        return
    var requested := int(quantity.value)
    var purchased := 0
    var last_result := ""
    for _i in range(requested):
        last_result = director.purchase_vendor_item(vendor, selected_index)
        if not last_result.begins_with("Purchased"):
            break
        purchased += 1
    if purchased > 0:
        status_label.text = "Purchased %d item%s. Your order has been added to your supplies." % [purchased, "" if purchased == 1 else "s"]
    else:
        status_label.text = last_result
    _refresh()


func _unhandled_input(event: InputEvent) -> void:
    if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        close_requested.emit()
        get_viewport().set_input_as_handled()
