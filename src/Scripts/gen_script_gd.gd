extends Node

enum ExportType {
	Normal,
	SVG,
	SVGSingle,
	SKF
}

@onready var gen = %GenScript
@onready var player = %Player
@onready var tree = %Tree

var last_path : String = ""
var baked_data : bool = true
var loaded_data : Dictionary
var loaded_swf_name : String = ""
var current_export_type : ExportType = ExportType.Normal
var zoom_trigger : bool = false
var dragging : bool = false
var smooth_iterations : int = 5
var selected_shape : SWFClasses.SWFShape = null
var exported_shape : SWFClasses.SWFShape = null

# Loading data from selected file.
func load_path(path : String = ""):
	if !FileAccess.file_exists(path) : return
	var dummy = gen.LoadSwf(path, baked_data)
	if dummy == null:
		printerr("Corrupt Load.")
		return
	loaded_data = dummy
	#var stage_size = loaded_data.get("SceneSize", { "Width": 300, "Height": 300 })
	#%GenExport.stage_size = Vector2(stage_size["Width"], stage_size["Height"])
	
	if loaded_data.is_empty(): return
	last_path = path
	loaded_swf_name = path.get_basename().get_file()
	player.current_animation = 0
	player.current_frame = 0
	%GenExport.parse_json(loaded_data, player, smooth_iterations)
	%SaveJson.disabled = false
	%SaveSVG.disabled = false
	%SaveSKF.disabled = false
	populate_tree()
	populate_sprites_options()
	#populate_option_button()

# Simple Zoom-in/out.. really idk what to comment here.
func _input(event: InputEvent) -> void:
	if zoom_trigger:
		var was_able_to_pan : bool = false
		if OS.has_feature("macos"):
			if event is InputEventPanGesture:
				var scroll_amount = event.delta.y
				%Player.scale *= scroll_amount
				%Player.scale = Vector2(%Player.scale.x, %Player.scale.x).clamp(Vector2(0.001, 0.001), Vector2(50.0, 50.0))
				%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)
				was_able_to_pan = true
		
		if !was_able_to_pan:
			if event.is_action_pressed("wheel_up"):
				%Player.scale *= 1.1
				%Player.scale = Vector2(min(%Player.scale.x, 50), min(%Player.scale.y, 50))
				%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)
			elif event.is_action_pressed("wheel_down"):
				%Player.scale *= 0.9
				%Player.scale = Vector2(max(%Player.scale.x, 0.001), max(%Player.scale.y, 0.001))
				%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)
				
		if event.is_action_pressed("wheel_middle"):
			dragging = true
		elif event.is_action_released("wheel_middle"):
			dragging = false
			
		if event is InputEventMouseMotion:
			if dragging:
				%Player.position += event.relative

#region UI Population
# todo : make the population both for shapes and sprites.
# Currently only supports shape viewing for debug purposes like polygon regeneration.
func populate_tree():
	tree.clear()
	var root : TreeItem = tree.create_item(null)
	root.set_text(0, "Model Shapes")

	var all_sprite_shapes : Dictionary[int, TreeItem] = {}

	for shape_id in player.shapes.keys():
		var shape = player.shapes[shape_id]
		var shape_item = tree.create_item(root)
		shape_item.set_text(0, str(shape_id))
		shape_item.set_metadata(0, shape)
		shape_item.set_icon_max_width(0, 18)
		shape_item.set_icon(0, shape.texture)
		all_sprite_shapes[shape_id] = shape_item

	for sprite_id in player.sprites.keys():
		var sprite = player.sprites[sprite_id]
		var sprite_item = tree.create_item(root)
		sprite_item.set_text(0, sprite.full_sprite_name)
		sprite_item.set_metadata(0, sprite)
		sprite_item.set_icon_max_width(0, 18)
		sprite_item.set_icon(0, preload("res://Assets/FolderButton.png"))
		all_sprite_shapes[sprite_id] = sprite_item

	for sprite_id in player.sprites.keys():
		var sprite = player.sprites[sprite_id]
		var parent_item = all_sprite_shapes[sprite_id]

		for child in sprite.children:
			if all_sprite_shapes.has(child.id):
				var child_item = all_sprite_shapes[child.id]
				child_item.get_parent().remove_child(child_item)
				parent_item.add_child(child_item)

# Since the general animation could be from a specific sprite, this lets you select which sprite to set as the root for animation.
func populate_sprites_options():
	%RootAnimaSprite.clear()
	var index : int = 0
	for sp in player.sprites.keys():
		%RootAnimaSprite.add_item(player.sprites[sp].full_sprite_name)
		%RootAnimaSprite.set_item_metadata(index, sp)

		if sp == player.animated_sprite_id:
			%RootAnimaSprite.select(index)
		
		index += 1
	# Makes sure the animation is based off the current selected animated sprite id.
	populate_animations()

# Populate the animation options with the imported data's animation.
func populate_animations():
	%Animations.clear()
	if !player.sprites.has(player.animated_sprite_id): return
	var sprite : SWFClasses.SWFSprite = player.sprites[player.animated_sprite_id]
	if sprite.animations.is_empty():
		if sprite.frames.size() < 2:
			%Animations.add_item("No Animation")
		else:
			%Animations.add_item("Untitled")
		%Animations.select(0)
		return
	for i in sprite.animations.keys():
		if i == null:
			%Animations.add_item("Untitled/ Null")
		else:
			%Animations.add_item(i)
	
	%Animations.select(0)

#endregion

#region UI
#--------- Selections
func _on_file_dialog_file_selected(path: String) -> void:
	load_path(path)

func _on_animations_item_selected(index: int) -> void:
	if !player.sprites.has(player.animated_sprite_id): return
	var sprite : SWFClasses.SWFSprite = player.sprites[player.animated_sprite_id]
	if index == -1 or index > sprite.animations.size(): return
	player.current_animation = index
	player.current_frame = 0

func _on_export_dialog_dir_selected(dir: String) -> void:
	match current_export_type:
		ExportType.Normal:
			%GenExport.json_export_folder = dir
			%GenExport.export_json_optimized(player, loaded_swf_name)
		ExportType.SVG:
			%GenExport.svg_export_folder = dir
			%GenExport.export_all_svgs(player.shapes)
		ExportType.SKF:
			%GenExport.skf_export_folder = dir
			%GenExport.export_skelform(player, loaded_swf_name, loaded_data)
		ExportType.SVGSingle:
			%GenExport.svg_export_folder = dir
			var id = player.shapes.find_key(exported_shape)
			%GenExport.export_all_svgs({"id" : id, "shape" : exported_shape})

func _on_root_anima_sprite_item_selected(_index: int) -> void:
	var sel = %RootAnimaSprite.get_selected_metadata()
	if !sel: return
	player.animated_sprite_id = sel
	populate_animations()

# Shape Selection from the TreeView
func _on_tree_item_selected() -> void:
	var item : TreeItem = tree.get_selected()
	if item == null or !is_instance_valid(item): 
		selected_shape = null
		%Preview.texture = null
		return
	if item.get_metadata(0) == null: 
		%Preview.texture = null
		return
	if item.get_metadata(0) is SWFClasses.SWFShape:
		selected_shape = item.get_metadata(0)
		%Preview.texture = selected_shape.texture
	else:
		%Preview.texture = null

func _on_tree_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	var sel : TreeItem = %Tree.get_item_at_position(mouse_position)
	if sel == null or !is_instance_valid(sel): return
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		if sel.get_metadata(0) is SWFClasses.SWFShape:
			exported_shape = sel.get_metadata(0)
			%TreeShapePopup.popup(Rect2(mouse_position.x, mouse_position.y, 100, 100))

func _on_popup_menu_id_pressed(id: int) -> void:
	match id:
		0:
			current_export_type = ExportType.SVGSingle
			%ExportDialog.popup()

#--------- Button presses
func _on_save_json_pressed() -> void:
	current_export_type = ExportType.Normal
	%ExportDialog.popup()

func _on_save_svg_pressed() -> void:
	current_export_type = ExportType.SVG
	%ExportDialog.popup()

func _on_save_skf_pressed() -> void:
	current_export_type = ExportType.SKF
	%ExportDialog.popup()

func _on_re_gen_poly_pressed() -> void:
	if selected_shape != null && is_instance_valid(selected_shape):
		selected_shape.build_geometry(smooth_iterations, %GenExport.hollow_pieces)
		selected_shape.generate_svg()
		var image = Image.new()
		if !selected_shape.to_svg().is_empty():
			image.load_svg_from_string(selected_shape.to_svg())
			selected_shape.texture = ImageTexture.create_from_image(image)
		var item : TreeItem = tree.get_selected()
		if item == null or !is_instance_valid(item): return
		if item.get_metadata(0) == null: return
		item.set_icon(0,selected_shape.texture)
		%Preview.texture = item.get_metadata(0).texture

func _on_reload_pressed() -> void:
	if last_path.is_empty(): return
	tree.clear()
	load_path(last_path)

func _on_import_pressed() -> void:
	%FileDialog.popup()

#--------- UI Checks
func _on_control_mouse_entered() -> void:
	zoom_trigger = true

func _on_control_mouse_exited() -> void:
	zoom_trigger = false

#--------- Misc
func _on_smooth_iteration_value_changed(value: float) -> void:
	smooth_iterations = int(value)

func _on_fps_value_changed(value: float) -> void:
	player.fps = int(value)

func _on_debug_lines_toggled(toggled_on: bool) -> void:
	player.draw_debug_mode = toggled_on

#region Zooms

func _on_ui_scale_up_pressed() -> void:
	get_window().content_scale_factor *= 1.1
	get_window().content_scale_factor  = clamp(get_window().content_scale_factor, 0.5, 2.0)
	%UIScale.text = "Zoom " + str(snappedf(get_window().content_scale_factor, 0.1) * 100)

func _on_ui_scale_down_pressed() -> void:
	get_window().content_scale_factor *= 0.9
	get_window().content_scale_factor  = clamp(get_window().content_scale_factor, 0.5, 2.0)
	%UIScale.text = "Zoom " + str(snappedf(get_window().content_scale_factor, 0.1) * 100)

func _on_cam_zoom_in_pressed() -> void:
	%Player.scale *= 1.1
	%Player.scale = Vector2(min(%Player.scale.x, 50), min(%Player.scale.y, 50))
	%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)

func _on_cam_zoom_out_pressed() -> void:
	%Player.scale *= 0.9
	%Player.scale = Vector2(max(%Player.scale.x, 0.001), max(%Player.scale.y, 0.001))
	%ZoomLabel.text = "Zoom " + str(snappedf(%Player.scale.length(), 0.1) * 100)

#endregion

#endregion
