extends SceneTree


const LOGO_PATH:="res://assets/branding/broken_knight_logo_v1.png"
const ICON_PATH:="res://assets/branding/broken_knight_icon_master_v1.png"
const HUD_ICON_PATH:="res://assets/branding/broken_knight_icon_256_v1.png"
const SPLASH_PATH:="res://assets/branding/broken_knight_splash_v1.png"


func _init()->void:
    var failures:Array[String]=[]
    for path in [LOGO_PATH,ICON_PATH,HUD_ICON_PATH,SPLASH_PATH]:
        if not ResourceLoader.exists(path):
            failures.append("missing brand resource: %s"%path)

    if ProjectSettings.get_setting("application/config/name","")!="Broken Knight":
        failures.append("application name is not Broken Knight")
    if ProjectSettings.get_setting("application/config/icon","")!=ICON_PATH:
        failures.append("project icon does not use brand icon")
    if ProjectSettings.get_setting("application/boot_splash/image","")!=SPLASH_PATH:
        failures.append("boot splash does not use brand logo")

    var packed:=load("res://scenes/Main.tscn") as PackedScene
    var main:=packed.instantiate()
    var pause_logo:=main.get_node_or_null("UI/PauseMenu/MenuPanel/BrandLogo") as TextureRect
    if pause_logo==null or pause_logo.texture==null:
        failures.append("pause menu brand logo is missing")
    elif pause_logo.texture.resource_path!=LOGO_PATH:
        failures.append("pause menu uses the wrong logo")
    var pause_logo_ok:=pause_logo!=null and pause_logo.texture!=null
    main.free()

    var windows_icon_ok:=FileAccess.file_exists("res://assets/branding/broken_knight.ico")
    if not windows_icon_ok:
        failures.append("multi-resolution Windows icon is missing")
    print("BRANDING|logo=%s|icon=%s|splash=%s|pause=%s|windows_ico=%s|failures=%d"%[
        LOGO_PATH,ICON_PATH,SPLASH_PATH,pause_logo_ok,windows_icon_ok,failures.size()
    ])
    for failure in failures:
        push_error(failure)
    quit(0 if failures.is_empty() else 1)
