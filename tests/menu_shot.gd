extends SceneTree
## The start menu as it looks (needs a window):
##   godot --path . --resolution 1600x900 -s res://tests/menu_shot.gd -- --out=<folder>

var _out := "user://shots"
var _f := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	root.add_child(load("res://scenes/menu.tscn").instantiate())


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 90:
		root.get_texture().get_image().save_png(_out.path_join("shot_menu.png"))
		return true
	return false
