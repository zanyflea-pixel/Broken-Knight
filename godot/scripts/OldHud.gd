extends Control

@export var hero_path: NodePath = NodePath("../../Player")

var _hero: Node
var _director: Node
var _redraw_accumulator := 0.0
var _style_cache: Dictionary = {}
var _fps_value := 0
var _fps_accumulator := 0.0
var _notification_text:=""
var _notification_color:=Color.WHITE
var _notification_time:=0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hero = get_node_or_null(hero_path)
    _director = get_node_or_null("../../GameplayDirector")
    set_process(true)
    queue_redraw()


func _process(delta: float) -> void:
    _notification_time=maxf(0.0,_notification_time-delta)
    _fps_accumulator += delta
    if _fps_accumulator >= .50:
        _fps_accumulator = 0.0
        _fps_value = Engine.get_frames_per_second()
    _redraw_accumulator += delta
    if _redraw_accumulator >= 0.10:
        _redraw_accumulator = 0.0
        queue_redraw()


func _draw() -> void:
    if _hero == null or not _hero.has_method("get_hud_state"):
        return
    var state: Dictionary = _hero.get_hud_state()
    _draw_status_panel(state)
    _draw_action_bar()
    _draw_quest_tracker(state)
    _draw_controls()
    _draw_fps_counter()
    _draw_notification()


func show_notification(message:String,color:Color=Color.WHITE)->void:
    _notification_text=message
    _notification_color=color
    _notification_time=3.2
    queue_redraw()


func _draw_notification()->void:
    if _notification_time<=0.0 or _notification_text.is_empty():return
    var viewport_size:=get_viewport_rect().size
    var alpha:=clampf(_notification_time/.45,0.0,1.0)
    var rect:=Rect2(Vector2(viewport_size.x*.5-220.0,52.0),Vector2(440.0,42.0))
    draw_style_box(_style(Color(.018,.026,.038,.90*alpha),Color(_notification_color.r,_notification_color.g,_notification_color.b,.72*alpha),8.0),rect)
    draw_string(ThemeDB.fallback_font,rect.position+Vector2(12,27),_notification_text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x-24,16,Color(_notification_color.r,_notification_color.g,_notification_color.b,alpha))


func _draw_fps_counter()->void:
    var viewport_size:Vector2=get_viewport_rect().size
    var fps:int=_fps_value if _fps_value>0 else Engine.get_frames_per_second()
    var frame_ms:float=1000.0/maxf(1.0,float(fps))
    var color:Color=Color(.42,1.0,.55) if fps>=55 else (Color(1.0,.78,.30) if fps>=35 else Color(1.0,.35,.30))
    var rect:=Rect2(Vector2(viewport_size.x*.5-64.0,14.0),Vector2(128.0,28.0))
    draw_style_box(_style(Color(.018,.025,.038,.88),Color(color.r,color.g,color.b,.55),7.0),rect)
    draw_string(ThemeDB.fallback_font,rect.position+Vector2(6.0,19.0),"FPS %d   %.1f ms"%[fps,frame_ms],HORIZONTAL_ALIGNMENT_CENTER,rect.size.x-12.0,12,color)


func _draw_status_panel(state: Dictionary) -> void:
    var viewport_size := get_viewport_rect().size
    var scale_factor := clampf(viewport_size.x / 1600.0, 0.78, 1.15)
    var panel_size := Vector2(390.0, 168.0) * scale_factor
    var panel := Rect2(Vector2(22.0,22.0), panel_size)
    _panel(panel, Color(0.035, 0.045, 0.065, 0.91), Color(0.48, 0.37, 0.72, 0.82), 10.0)

    var pad := 14.0 * scale_factor
    var x := panel.position.x + pad
    var y := panel.position.y + pad
    var title := str(state.get("name", "Broken Knight"))
    var subtitle := str(state.get("title", "Frontline Adventurer"))
    draw_string(ThemeDB.fallback_font, Vector2(x, y + 17.0 * scale_factor), title, HORIZONTAL_ALIGNMENT_LEFT, 190.0 * scale_factor, 18 * scale_factor, Color(0.96, 0.97, 1.0))
    draw_string(ThemeDB.fallback_font, Vector2(x, y + 34.0 * scale_factor), subtitle, HORIZONTAL_ALIGNMENT_LEFT, 210.0 * scale_factor, 11 * scale_factor, Color(0.56, 0.66, 0.77))

    var gold_rect := Rect2(panel.end.x - 108.0 * scale_factor, y, 92.0 * scale_factor, 23.0 * scale_factor)
    _pill(gold_rect, "Gold %d" % int(state.get("gold", 0)), Color(0.95, 0.74, 0.30), scale_factor)
    var level_rect := Rect2(gold_rect.position.x - 69.0 * scale_factor, y, 60.0 * scale_factor, 23.0 * scale_factor)
    _pill(level_rect, "Lv %d" % int(state.get("level", 1)), Color(0.87, 0.86, 0.76), scale_factor)

    var bar_x := x
    var bar_width := panel_size.x - pad * 2.0
    var hp := float(state.get("hp", 0.0))
    var max_hp := maxf(1.0, float(state.get("max_hp", 1.0)))
    var mana := float(state.get("mana", 0.0))
    var max_mana := maxf(1.0, float(state.get("max_mana", 1.0)))
    var warrior_resource:bool=is_instance_valid(_hero) and _hero.has_method("is_warrior") and _hero.is_warrior()
    var secondary:=float(state.get("stamina",100.0)) if warrior_resource else mana
    var secondary_max:=maxf(1.0,float(state.get("max_stamina",100.0))) if warrior_resource else max_mana
    _bar(Rect2(bar_x, y + 48.0 * scale_factor, bar_width, 22.0 * scale_factor), hp / max_hp, Color(0.62, 0.10, 0.18), Color(1.0, 0.36, 0.43), "HP  %d / %d" % [roundi(hp), roundi(max_hp)], scale_factor)
    _bar(Rect2(bar_x, y + 77.0 * scale_factor, bar_width, 19.0 * scale_factor), secondary / secondary_max, Color(0.08,0.28,0.10) if warrior_resource else Color(0.10, 0.28, 0.65), Color(0.30,0.84,0.35) if warrior_resource else Color(0.30, 0.68, 1.0), ("STAMINA  %d / %d" if warrior_resource else "MANA  %d / %d") % [roundi(secondary),roundi(secondary_max)], scale_factor)
    var xp := float(state.get("xp", 0.0))
    var next_xp := maxf(1.0, float(state.get("next_xp", 1.0)))
    _bar(Rect2(bar_x, y + 103.0 * scale_factor, bar_width, 12.0 * scale_factor), xp / next_xp, Color(0.37, 0.24, 0.08), Color(0.94, 0.77, 0.30), "", scale_factor)
    draw_string(ThemeDB.fallback_font, Vector2(bar_x + 6.0 * scale_factor, y + 137.0 * scale_factor), "XP %d / %d    RELICS %d    KILLS %d" % [roundi(xp), roundi(next_xp), int(state.get("relic_shards",0)), int(state.get("enemies_defeated",0))], HORIZONTAL_ALIGNMENT_LEFT, bar_width, 11 * scale_factor, Color(0.78, 0.82, 0.88))


func _draw_action_bar() -> void:
    var viewport_size := get_viewport_rect().size
    var scale_factor := clampf(viewport_size.x / 1600.0, 0.78, 1.10)
    var slot := 55.0 * scale_factor
    var gap := 7.0 * scale_factor
    var count := 6
    var total := slot * count + gap * (count - 1)
    var origin := Vector2((viewport_size.x - total) * 0.5, viewport_size.y - slot - 26.0 * scale_factor)
    var warrior:bool=is_instance_valid(_hero) and _hero.has_method("is_warrior") and _hero.is_warrior()
    var labels := ["SLASH", "BASH", "CHARGE", "WAR CRY", "HP", "MP"] if warrior else ["SPARK", "NOVA", "BLINK", "ORB", "HP", "MP"]
    var max_cooldowns: Array = _director.get_max_cooldowns() if is_instance_valid(_director) and _director.has_method("get_max_cooldowns") else [0.22, 1.8, 2.8, 3.4]
    var cooldown_values: Array = _director.get_cooldowns() if is_instance_valid(_director) and _director.has_method("get_cooldowns") else []
    var staff_ready:bool=(is_instance_valid(_hero) and _hero.has_method("has_warrior_weapons_equipped") and _hero.has_warrior_weapons_equipped()) if warrior else (is_instance_valid(_hero) and _hero.has_method("has_magic_staff_equipped") and bool(_hero.has_magic_staff_equipped()))
    for i in range(count):
        var rect := Rect2(origin + Vector2((slot + gap) * i, 0.0), Vector2(slot, slot))
        _panel(rect, Color(0.025, 0.033, 0.048, 0.90), Color(0.30, 0.35, 0.43, 0.9), 6.0)
        draw_string(ThemeDB.fallback_font, rect.position + Vector2(7.0, 15.0 * scale_factor), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, slot - 12.0, 11 * scale_factor, Color(0.92, 0.78, 0.38))
        draw_string(ThemeDB.fallback_font, rect.position + Vector2(3.0, 39.0 * scale_factor), labels[i], HORIZONTAL_ALIGNMENT_CENTER, slot - 6.0, 9 * scale_factor, Color(0.78, 0.84, 0.91))
        if i<4 and not staff_ready:
            draw_rect(rect.grow(-2.0),Color(.01,.012,.018,.62),true)
            draw_string(ThemeDB.fallback_font,rect.position+Vector2(3.0,33.0*scale_factor),"WEAPONS" if warrior else "STAFF",HORIZONTAL_ALIGNMENT_CENTER,slot-6.0,10*scale_factor,Color(1.0,.45,.28))
        if i == 4 or i == 5:
            var count_value := int(_hero.health_potions if i == 4 else _hero.mana_potions)
            draw_string(ThemeDB.fallback_font, rect.position + Vector2(7.0, 15.0 * scale_factor), "%d  x%d" % [i+1,count_value], HORIZONTAL_ALIGNMENT_LEFT, slot-10.0, 10*scale_factor, Color(0.92,0.78,0.38))
        if i < cooldown_values.size() and float(cooldown_values[i]) > 0.0:
            var frac: float = clampf(float(cooldown_values[i]) / max_cooldowns[i], 0.0, 1.0)
            draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * frac)), Color(0.01,0.015,0.025,0.68), true)
            draw_string(ThemeDB.fallback_font, rect.position + Vector2(3.0, 33.0 * scale_factor), "%.1f" % float(cooldown_values[i]), HORIZONTAL_ALIGNMENT_CENTER, slot - 6.0, 13 * scale_factor, Color.WHITE)


func _draw_controls() -> void:
    var viewport_size := get_viewport_rect().size
    var text := "G PANEL   SHIFT SPRINT   CTRL ROLL   I/B BAG   K SKILLS   M MAP   E INTERACT"
    draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x - 430.0, viewport_size.y - 28.0), text, HORIZONTAL_ALIGNMENT_RIGHT, 405.0, 12, Color(0.82, 0.86, 0.91, 0.88))


func _draw_quest_tracker(state: Dictionary) -> void:
    if not is_instance_valid(_director) or not _director.has_method("get_gameplay_state"): return
    var game: Dictionary = _director.get_gameplay_state()
    var rect:=Rect2(Vector2(22,202),Vector2(286,92))
    _panel(rect,Color(0.025,0.035,0.05,0.82),Color(0.43,0.35,0.22,0.75),8.0)
    draw_string(ThemeDB.fallback_font,rect.position+Vector2(14,23),"ACTIVE BOUNTY",HORIZONTAL_ALIGNMENT_LEFT,250,12,Color(0.93,0.75,0.33))
    draw_string(ThemeDB.fallback_font,rect.position+Vector2(14,46),str(game.get("quest","Riverbank Menace")),HORIZONTAL_ALIGNMENT_LEFT,250,16,Color.WHITE)
    var complete: bool = game.get("quest_complete",false)
    var detail := "COMPLETE - reward claimed" if complete else "Progress  %d / %d" % [game.get("quest_current",0),game.get("quest_goal",8)]
    draw_string(ThemeDB.fallback_font,rect.position+Vector2(14,70),detail,HORIZONTAL_ALIGNMENT_LEFT,250,12,Color(0.65,0.78,0.69) if complete else Color(0.75,0.79,0.85))
    draw_string(ThemeDB.fallback_font,rect.position+Vector2(14,85),"H:%d  Logs:%d  Ore:%d  Leather:%d" % [state.get("herbs",0),state.get("logs",0),state.get("ore",0),state.get("leather",0)],HORIZONTAL_ALIGNMENT_LEFT,250,10,Color(0.58,0.65,0.73))
    var interaction:=str(game.get("interaction",""))
    if not interaction.is_empty():draw_string(ThemeDB.fallback_font,Vector2(22,316),interaction,HORIZONTAL_ALIGNMENT_LEFT,440,14,Color(1,.82,.36))


func _panel(rect: Rect2, fill: Color, border: Color, radius: float) -> void:
    draw_style_box(_style(fill, border, radius), rect)


func _pill(rect: Rect2, text: String, color: Color, scale_factor: float) -> void:
    draw_style_box(_style(Color(color.r, color.g, color.b, 0.11), Color(color.r, color.g, color.b, 0.30), 8.0), rect)
    draw_string(ThemeDB.fallback_font, rect.position + Vector2(4.0, 16.0 * scale_factor), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 10 * scale_factor, color)


func _bar(rect: Rect2, fraction: float, dark: Color, bright: Color, label: String, scale_factor: float) -> void:
    draw_style_box(_style(Color(0.01, 0.015, 0.022, 0.92), Color(0.20, 0.23, 0.29, 0.9), 5.0), rect)
    var inner := rect.grow(-2.0)
    inner.size.x *= clampf(fraction, 0.0, 1.0)
    if inner.size.x > 1.0:
        draw_rect(inner, dark.lerp(bright, 0.45), true)
        draw_line(inner.position + Vector2(1.0, 1.0), Vector2(inner.end.x - 1.0, inner.position.y + 1.0), Color(bright.r, bright.g, bright.b, 0.65), 1.0)
    if not label.is_empty():
        draw_string(ThemeDB.fallback_font, rect.position + Vector2(7.0, rect.size.y * 0.72), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14.0, 11 * scale_factor, Color(0.98, 0.98, 1.0))


func _style(fill: Color, border: Color, radius: float) -> StyleBoxFlat:
    var key := "%s|%s|%.2f" % [fill.to_html(true), border.to_html(true), radius]
    if _style_cache.has(key):
        return _style_cache[key]
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(roundi(radius))
    style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
    style.shadow_size = 5
    _style_cache[key] = style
    return style
