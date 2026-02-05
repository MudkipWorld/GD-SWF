extends Node

enum ExportType {
	Normal,
	SVG,
	SKF
}

@onready var gen = %GenScript
@onready var player = %Player
@onready var tree = %Tree

var last_path : String = ""
var baked_data : bool = true
var loaded_data : Dictionary = {}
var loaded_swf_name : String = ""
var current_export_type : ExportType = ExportType.Normal
var zoom_trigger : bool = false
var dragging : bool = false

func _on_import_pressed() -> void:
	%FileDialog.popup()

func _on_file_dialog_file_selected(path: String) -> void:
	load_path(path)

func populate_tree(shapes : Array = []):
	if shapes.is_empty(): return
	tree.clear()
	var root : TreeItem = tree.create_item(null)
	root.set_text(0, "Model Shapes")
	
	for sp in shapes:
		var pending_item : TreeItem = tree.create_item(root)
		pending_item.set_text(0, str(sp.id))
		pending_item.set_metadata(0, sp.shape)
		pending_item.set_icon_max_width(0, 25)
		pending_item.set_icon(0, sp.shape.texture)

func populate_option_button():
	%Animations.clear()
	if !player.sprites.has(player.animated_sprite_id): return
	var sprite : SWFClasses.SWFSprite = player.sprites[player.animated_sprite_id]
	for i in sprite.animations.keys():
		%Animations.add_item(i)

func _on_re_gen_poly_pressed() -> void:
	%GenExport.regen_shapes(player)

func _on_reload_pressed() -> void:
	if last_path.is_empty(): return
	tree.clear()
	load_path(last_path)

func load_path(path : String = ""):
	if !FileAccess.file_exists(path) : return
	loaded_data = gen.LoadSwf(path, baked_data)
	#var stage_size = loaded_data.get("SceneSize", { "Width": 300, "Height": 300 })
	#%GenExport.stage_size = Vector2(stage_size["Width"], stage_size["Height"])
	if loaded_data.is_empty(): return
	last_path = path
	loaded_swf_name = path.get_basename().get_file()
	var shapes : Array = %GenExport.parse_json(loaded_data, player, baked_data)
	populate_tree(shapes)
	populate_option_button()

func _on_animations_item_selected(index: int) -> void:
	if !player.sprites.has(player.animated_sprite_id): return
	var sprite : SWFClasses.SWFSprite = player.sprites[player.animated_sprite_id]
	if index == -1 or index > sprite.animations.size(): return
	player.current_animation = index

func _on_fps_value_changed(value: float) -> void:
	player.fps = int(value)

func _on_tree_item_selected() -> void:
	var item : TreeItem = tree.get_selected()
	if item == null or !is_instance_valid(item): return
	if item.get_metadata(0) == null: return
	if item.get_metadata(0) is SWFClasses.SWFShape:
		%Preview.texture = item.get_metadata(0).texture
	else:
		%Preview.texture = null

func _on_baked_keyframes_toggled(toggled_on: bool) -> void:
	baked_data = toggled_on

func _on_save_json_pressed() -> void:
	current_export_type = ExportType.Normal
	%ExportDialog.popup()

func _on_save_svg_pressed() -> void:
	current_export_type = ExportType.SVG
	%ExportDialog.popup()

func _on_save_skf_pressed() -> void:
	current_export_type = ExportType.SKF
	%ExportDialog.popup()

func _on_export_dialog_dir_selected(dir: String) -> void:
	match current_export_type:
		ExportType.Normal:
			%GenExport.json_export_folder = dir
			%GenExport.export_json_optimized(loaded_data, loaded_swf_name)
		ExportType.SVG:
			%GenExport.svg_export_folder = dir
			%GenExport.export_all_svgs(player)
		ExportType.SKF:
			%GenExport.skf_export_folder = dir
			%GenExport.export_skelform(player, loaded_swf_name)

func _input(event: InputEvent) -> void:
	if zoom_trigger:
		if event.is_action_pressed("wheel_up"):
			%Player.scale *= 1.1
			%Player.scale = Vector2(min(%Player.scale.x, 10), min(%Player.scale.y, 10))
			%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)
		elif event.is_action_pressed("wheel_down"):
			%Player.scale /= 1.1
			%Player.scale = Vector2(max(%Player.scale.x, 0.001), max(%Player.scale.y, 0.001))
			%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)
		
		if event.is_action_pressed("wheel_middle"):
			dragging = true
		elif event.is_action_released("wheel_middle"):
			dragging = false
			
		if event is InputEventMouseMotion:
			if dragging:
				%Player.position += event.relative

func _on_control_mouse_entered() -> void:
	zoom_trigger = true

func _on_control_mouse_exited() -> void:
	zoom_trigger = false
