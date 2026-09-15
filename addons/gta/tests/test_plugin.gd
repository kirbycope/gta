extends GutTest

## Purpose: the addon actually enables.
##
## This exists because it did not, and nothing noticed. The per-game folder move
## renamed the class names inside `plugin.gd` but left its preload paths at the
## old `addons/gta/scripts/`, and the addon then failed to enable in every
## consuming project with three parse errors. The whole suite stayed green and so
## did CI, because GUT never instantiates an `EditorPlugin`, scene validation
## never loads one, and this repository does not enable its own plugin in its own
## `project.godot`. It took someone opening a project in the editor to find it.
##
## The guard is cheaper than it looks and needs no editor. Loading a GDScript
## compiles it, and a `preload` of a file that is not there is a compile error,
## so a broken `plugin.gd` comes back null from [method load]. That single
## assertion would have caught the original break.
##
## The second reason this file is worth having: `plugin.gd` preloads by paths
## relative to itself, so it is the one place in the addon that a search for
## "res://" does not reach, and every future move will miss it again.

const PLUGIN_PATH: String = "res://addons/gta/plugin.gd"


func test_the_plugin_script_compiles() -> void:
	# the whole bug in one assertion: a bad preload makes this null
	assert_not_null(load(PLUGIN_PATH),
		"plugin.gd failed to compile, which means the addon will not enable")


func test_every_path_the_plugin_preloads_exists() -> void:
	# and this one names which path is wrong rather than just failing to compile
	var source: String = FileAccess.get_file_as_string(PLUGIN_PATH)
	assert_ne(source, "", "plugin.gd is readable")

	var finder := RegEx.create_from_string(r'preload\("([^"]+)"\)')
	var found: Array[RegExMatch] = finder.search_all(source)
	assert_gt(found.size(), 0, "the plugin preloads at least one script")

	var base_dir: String = PLUGIN_PATH.get_base_dir()
	for hit: RegExMatch in found:
		var quoted: String = hit.get_string(1)
		# the paths here are relative to plugin.gd, which is exactly why a
		# find-and-replace over res:// paths does not find them
		var resolved: String = quoted if quoted.begins_with("res://") \
			else base_dir.path_join(quoted)
		assert_true(ResourceLoader.exists(resolved),
			"plugin.gd preloads %s, which resolves to %s and is not there" % [quoted, resolved])


func test_the_cars_it_registers_are_the_cars_the_addon_has() -> void:
	# a car added to the addon and forgotten here never appears in the Create
	# New Node dialog, which is how MkCar was missed
	var source: String = FileAccess.get_file_as_string(PLUGIN_PATH)
	var finder := RegEx.create_from_string(r'add_custom_type\("([^"]+)"')
	var registered: Array[String] = []
	for hit: RegExMatch in finder.search_all(source):
		registered.append(hit.get_string(1))

	for expected: String in ["GtaCar", "TwCar", "RlCar", "MkCar"]:
		assert_true(registered.has(expected),
			"%s is one of the addon's cars, so the plugin should register it" % expected)

	# and everything it registers is removed again, or the editor keeps a stale
	# entry after the addon is disabled
	var remover := RegEx.create_from_string(r'remove_custom_type\("([^"]+)"')
	var removed: Array[String] = []
	for hit: RegExMatch in remover.search_all(source):
		removed.append(hit.get_string(1))
	for name: String in registered:
		assert_true(removed.has(name), "%s is registered, so it must be removed too" % name)
