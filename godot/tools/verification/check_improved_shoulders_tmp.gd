extends SceneTree

const MODEL_PATH := "res://assets/hero/hero_equipped_shoulders_test.glb"

func _initialize() -> void:
    var packed := load(MODEL_PATH) as PackedScene

    if packed == null:
        print("SHOULDER_TEST|LOAD_FAILED")
        quit(1)
        return

    var root := packed.instantiate()
    var improved: Array[String] = []

    find_improved_pieces(root, improved)

    print(
        "SHOULDER_TEST|piece_count=%d|names=%s" %
        [improved.size(), ",".join(improved)]
    )

    root.free()

    if improved.size() != 4:
        quit(1)
        return

    quit(0)


func find_improved_pieces(
    node: Node,
    improved: Array[String]
) -> void:
    var node_name := String(node.name)

    if node_name.begins_with(
        "RoyalArmor_shoulders_ApexImprovedPauldron"
    ):
        improved.append(node_name)

    for child in node.get_children():
        find_improved_pieces(child, improved)