extends SceneTree

const MODEL_PATH := "res://assets/hero/hero_base_body.glb"

func _initialize() -> void:
    var packed := load(MODEL_PATH) as PackedScene

    if packed == null:
        print("LIVE_RIGID_SHOULDERS|LOAD_FAILED")
        quit(1)
        return

    var root := packed.instantiate()
    var improved_pieces: Array[String] = []
    var animation_player := find_animation_player(root)

    find_improved_pieces(root, improved_pieces)

    var has_sword_slash := (
        animation_player != null
        and animation_player.has_animation(&"SwordSlash")
    )

    print(
        "LIVE_RIGID_SHOULDERS|pieces=%d|sword_slash=%s|names=%s" %
        [
            improved_pieces.size(),
            str(has_sword_slash),
            ",".join(improved_pieces)
        ]
    )

    root.free()

    if improved_pieces.size() != 4 or not has_sword_slash:
        quit(1)
        return

    quit(0)


func find_improved_pieces(
    node: Node,
    improved_pieces: Array[String]
) -> void:
    var node_name := String(node.name)

    if node_name.begins_with(
        "RoyalArmor_shoulders_ApexImprovedPauldron"
    ):
        improved_pieces.append(node_name)

    for child in node.get_children():
        find_improved_pieces(child, improved_pieces)


func find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer

    for child in node.get_children():
        var found := find_animation_player(child)

        if found != null:
            return found

    return null