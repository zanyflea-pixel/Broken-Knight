extends SceneTree

const MODELS := {
    "ORIGINAL": "res://assets/hero/hero_base_body.glb",
    "SHOULDER_TEST": "res://assets/hero/hero_equipped_shoulders_test.glb",
}

func _initialize() -> void:
    for label in MODELS:
        inspect_model(label, MODELS[label])

    quit(0)


func inspect_model(label: String, path: String) -> void:
    var packed := load(path) as PackedScene

    if packed == null:
        print("MODEL|%s|LOAD_FAILED|%s" % [label, path])
        return

    var root := packed.instantiate()
    var players: Array[AnimationPlayer] = []

    find_animation_players(root, players)

    print(
        "MODEL|%s|players=%d|path=%s" %
        [label, players.size(), path]
    )

    for player in players:
        for animation_name in player.get_animation_list():
            var animation := player.get_animation(animation_name)

            if animation == null:
                continue

            print(
                "ANIMATION|model=%s|player=%s|name=%s|length=%.3f|loop_mode=%d|tracks=%d" %
                [
                    label,
                    player.name,
                    animation_name,
                    animation.length,
                    animation.loop_mode,
                    animation.get_track_count()
                ]
            )

    root.free()


func find_animation_players(
    node: Node,
    players: Array[AnimationPlayer]
) -> void:
    if node is AnimationPlayer:
        players.append(node as AnimationPlayer)

    for child in node.get_children():
        find_animation_players(child, players)