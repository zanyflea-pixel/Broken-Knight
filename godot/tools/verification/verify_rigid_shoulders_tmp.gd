extends SceneTree

const MODEL_PATH := "res://assets/hero/hero_rigid_shoulders_test.glb"

func _initialize() -> void:
    var packed := load(MODEL_PATH) as PackedScene

    if packed == null:
        print("RIGID_SHOULDERS|LOAD_FAILED")
        quit(1)
        return

    var root := packed.instantiate()
    var pieces: Array[String] = []
    var player := find_animation_player(root)

    find_pieces(root, pieces)

    var has_slash := (
        player != null
        and player.has_animation(&"SwordSlash")
    )

    print(
        "RIGID_SHOULDERS|pieces=%d|sword_slash=%s|names=%s" %
        [
            pieces.size(),
            str(has_slash),
            ",".join(pieces)
        ]
    )

    root.free()

    if pieces.size() != 4 or not has_slash:
        quit(1)
        return

    quit(0)


func find_pieces(node: Node, pieces: Array[String]) -> void:
    var node_name := String(node.name)

    if node_name.begins_with(
        "RoyalArmor_shoulders_ApexImprovedPauldron"
    ):
        pieces.append(node_name)

    for child in node.get_children():
        find_pieces(child, pieces)


func find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer

    for child in node.get_children():
        var found := find_animation_player(child)

        if found != null:
            return found

    return null