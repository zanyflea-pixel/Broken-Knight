extends Control

signal close_requested

var _title:Label
var _body:RichTextLabel


func _ready()->void:
    process_mode=Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter=Control.MOUSE_FILTER_STOP
    var shade:=ColorRect.new()
    shade.color=Color(0.008,0.010,0.016,.80)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(shade)
    var panel:=PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position=Vector2(-350,-245)
    panel.size=Vector2(700,490)
    add_child(panel)
    var margin:=MarginContainer.new()
    margin.add_theme_constant_override("margin_left",38)
    margin.add_theme_constant_override("margin_right",38)
    margin.add_theme_constant_override("margin_top",30)
    margin.add_theme_constant_override("margin_bottom",26)
    panel.add_child(margin)
    var column:=VBoxContainer.new()
    column.add_theme_constant_override("separation",18)
    margin.add_child(column)
    _title=Label.new()
    _title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    _title.add_theme_font_size_override("font_size",26)
    _title.add_theme_color_override("font_color",Color(1.0,.79,.38))
    column.add_child(_title)
    var rule:=HSeparator.new();column.add_child(rule)
    _body=RichTextLabel.new()
    _body.bbcode_enabled=true
    _body.fit_content=false
    _body.custom_minimum_size=Vector2(620,330)
    _body.add_theme_font_size_override("normal_font_size",18)
    _body.add_theme_color_override("default_color",Color(.89,.88,.79))
    _body.scroll_active=true
    column.add_child(_body)
    var close:=Button.new()
    close.text="Close  [Esc]"
    close.custom_minimum_size=Vector2(150,42)
    close.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
    close.pressed.connect(func():close_requested.emit())
    column.add_child(close)
    visible=false


func show_entry(title:String,body:String)->void:
    _title.text=title
    _body.text="[center][i]Recovered writing from the world of Broken Knight[/i][/center]\n\n%s"%body
    _body.scroll_to_line(0)
    visible=true
