extends GutTest

## Purpose: the drop-in asset folder is genuinely optional.
##
## The demo ships with the addon's own primitive karts and has to keep working
## on a fresh clone where the folder does not exist at all. These tests pin down
## that nothing is required, that a missing file falls back rather than erroring,
## and that a kart built with an empty folder still has its stock model.

const KART_SCENE: String = "res://addons/gta/mk/scenes/mk_kart.tscn"


func test_the_folder_layout_is_under_one_root() -> void:
	assert_string_contains(MkAssets.KART_DIR, MkAssets.ROOT, "karts live under the root")
	assert_string_contains(MkAssets.DRIVER_DIR, MkAssets.ROOT, "and so do drivers")
	assert_string_contains(MkAssets.SOUND_DIR, MkAssets.ROOT, "and sounds")
	assert_string_contains(MkAssets.ROOT, "/mk/",
		"the folder sits with the rest of the Mario Kart demo rather than off on its own")


func test_a_missing_asset_is_null_rather_than_an_error() -> void:
	# whatever is or is not in the folder on this machine, asking for something
	# that cannot be there has to come back empty rather than blow up
	assert_null(MkAssets.kart_model(&"no_such_driver_at_all"),
		"an unknown driver has no kart model")
	assert_null(MkAssets.driver_model(&"no_such_driver_at_all"),
		"and no driver model")
	assert_null(MkAssets.sound("no_such_sound_at_all"),
		"and a sound that is not there is null")


func test_an_empty_name_asks_for_nothing() -> void:
	assert_null(MkAssets.kart_model(&""), "an empty driver key does not become a path")
	assert_null(MkAssets.sound(""), "nor an empty sound name")


func test_every_extension_offered_is_one_godot_imports() -> void:
	for extension: String in MkAssets.MODEL_EXTENSIONS:
		assert_true(extension.begins_with("."), "%s is an extension" % extension)
	for extension: String in MkAssets.SOUND_EXTENSIONS:
		assert_true(extension.begins_with("."), "%s is an extension" % extension)
	assert_true(MkAssets.MODEL_EXTENSIONS.has(".glb"),
		"glb, since that is what most rips and exports arrive as")
	assert_true(MkAssets.SOUND_EXTENSIONS.has(".ogg"), "ogg, which the addon already uses")


func test_a_kart_keeps_its_stock_model_when_nothing_has_been_dropped_in() -> void:
	var kart: MkCar = (load(KART_SCENE) as PackedScene).instantiate() as MkCar
	kart.driver = &"rook"
	add_child_autofree(kart)
	await wait_physics_frames(1)

	if MkAssets.kart_model(&"rook") != null:
		# somebody has actually dropped a kart in on this machine, so the stock
		# body is meant to be hidden and this test has nothing to say
		assert_not_null(kart.get_node_or_null(^"DropInModel"),
			"a dropped in model is instanced when one is present")
		return

	assert_null(kart.get_node_or_null(^"DropInModel"),
		"with an empty folder no replacement model is added")
	var chassis: Node3D = kart.get_node_or_null(^"Chassis") as Node3D
	assert_not_null(chassis, "the stock chassis is still there")
	assert_true(chassis.visible, "and still visible, because nothing replaced it")


func test_the_parts_a_replacement_hides_are_named_rather_than_guessed() -> void:
	var kart: MkCar = (load(KART_SCENE) as PackedScene).instantiate() as MkCar
	add_child_autofree(kart)
	await wait_physics_frames(1)
	assert_gt(kart.stock_model_parts.size(), 0, "the stock parts are listed")
	for path: NodePath in kart.stock_model_parts:
		assert_not_null(kart.get_node_or_null(path),
			"%s is a real node on the kart, so hiding it will work" % path)
