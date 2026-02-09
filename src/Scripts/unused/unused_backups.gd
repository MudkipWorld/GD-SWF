extends Node

func build_bones_recursive_old(player: SWFPlayer, sprite_id: int, parent_bone_idx: int, bones_list: Array):
	if !player.sprites.has(sprite_id):
		return
	var sprite : SWFClasses.SWFSprite = player.sprites[sprite_id]
	if sprite.frames.size() == 0:
		return
	var frame_dict = sprite.frames[0]
	var depths = frame_dict.keys()
	for depth in depths:
		var ft = frame_dict[depth]
		
		var bone_idx = bones_list.size()
		var local_pos = Vector2(ft.x, -ft.y)
		var local_transform : Transform2D = Transform2D.IDENTITY
		var tex_name = ""
		if player.shapes.has(ft.symbol_id):
			tex_name = "shape_%d" % ft.symbol_id
			#local_pos = get_local_shape(player, ft)

		local_transform = local_transform.scaled(Vector2(ft.scale_x, ft.scale_y))
		local_transform = local_transform.rotated(deg_to_rad(ft.rotation))
		local_transform = local_transform.translated(local_pos)
		
		var bone = {
			"id": bone_idx,
			"parent_id": parent_bone_idx,
			"name": "symbol_%d" % ft.symbol_id,
			"pos": {"x": local_transform.get_origin().x, "y": local_transform.get_origin().y},
			"scale": {"x": local_transform.get_scale().x, "y": local_transform.get_scale().y},
			"rot": local_transform.get_rotation(),
			"tex": tex_name,
			"zindex": depth,
			"ik_family_id": -1,
		}
		bones_list.append(bone)

		if player.sprites.has(ft.symbol_id):
			build_bones_recursive_old(player, ft.symbol_id, bone_idx, bones_list)

func matrix_equals(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if abs(a[i] - b[i]) > 0.0001:
			return false
	return true

'''
func save_gdwf(path: String, player : SWFPlayer) -> void:
	if !DirAccess.dir_exists_absolute(gdwf_export_folder):
		DirAccess.make_dir_absolute(gdwf_export_folder)
	if path.get_extension().is_empty():
		path += ".tres"
	var res = GDWFResource.new()
	res.shapes = {}
	res.sprites = {}
	res.sprite_current_frames = {}
	res.animation_sprite_id = player.animated_sprite_id
	for id in player.shapes.keys():
		var shape : SWFClasses.SWFShape = player.shapes[id]
		res.shapes[id] = {
			"offset": shape.offset,
			"size": shape.size,
			"subpaths": shape.subpaths
		}
	for id in player.sprites.keys():
		var sprite : SWFClasses.SWFSprite = player.sprites[id]
		var sprite_dict = {
			"children": [],
			"frames": [],
			"frame_names": sprite.frame_names.duplicate(),
			"animations": {}
		}
		for child in sprite.children:
			sprite_dict["children"].append({
				"id": child.id,
				"type": child.type
			})
		for frame_dict in sprite.frames:
			var frame_data = {}
			for key in frame_dict.keys():
				var f : SWFClasses.SWFFrame = frame_dict[key]
				frame_data[key] = {
					"symbol_id": f.symbol_id,
					"depth": f.depth,
					"x": f.x,
					"y": f.y,
					"scale_x": f.scale_x,
					"scale_y": f.scale_y,
					"rotation": f.rotation,
					"visible": f.visible,
					"transform_matrix": f.transform_matrix
				}
			sprite_dict["frames"].append(frame_data)
		for anim_name in sprite.animations.keys():
			sprite_dict["animations"][anim_name] = sprite.animations[anim_name].duplicate()
		res.sprites[id] = sprite_dict
		res.sprite_current_frames[id] = player.sprite_current_frames.get(id, 0)
	res.metadata = {"source_file": path}
	var err = ResourceSaver.save(res, path)
	if err != OK:
		printerr("Failed to save GDWFResource:", path)
		return
	print("Saved GDWFResource to", path)

func load_gdwf(file: GDWFResource, player : SWFPlayer) -> void:
	if file == null:
		printerr("Failed to load GDWFResource:", file)
		return
	player.file_loaded_right = true
	player.shapes.clear()
	player.sprites.clear()
	player.sprite_current_frames.clear()
	player.sprite_current_animation.clear()
	player.sprite_current_anim_frame.clear()
	player.animated_sprite_id = file.animation_sprite_id
	for id in file.shapes.keys():
		var shape_data = file.shapes[id]
		var shape = SWFClasses.SWFShape.new({})
		shape.offset = shape_data.get("offset", Vector2.ZERO)
		shape.size = shape_data.get("size", Vector2.ZERO)
		shape.subpaths = shape_data.get("subpaths", [])
		player.shapes[id] = shape
	for id in file.sprites.keys():
		var sp_data = file.sprites[id]
		var sprite = SWFClasses.SWFSprite.new({})
		sprite.children = []
		for child_data in sp_data.get("children", []):
			sprite.children.append(SWFClasses.SWFChild.new({
				"ID": child_data.get("id", 0),
				"Type": child_data.get("type", "Shape")
			}))
		sprite.frames = []
		for frame_dict in sp_data.get("frames", []):
			var new_frame_dict = {}
			for key in frame_dict.keys():
				var f_data = frame_dict[key]
				new_frame_dict[key] = SWFClasses.SWFFrame.new({
					"SymbolID": f_data.get("symbol_id", 0),
					"Depth": f_data.get("depth", 0),
					"X": f_data.get("x", 0.0),
					"Y": f_data.get("y", 0.0),
					"ScaleX": f_data.get("scale_x", 1.0),
					"ScaleY": f_data.get("scale_y", 1.0),
					"Rotation": f_data.get("rotation", 0.0),
					"Visible": f_data.get("visible", true),
					"TransformMatrix": f_data.get("transform_matrix", [])
				})
			sprite.frames.append(new_frame_dict)
		sprite.frame_names = sp_data.get("frame_names", []).duplicate()
		sprite.animations.clear()
		for anim_name in sp_data.get("animations", {}).keys():
			sprite.animations[anim_name] = sp_data["animations"][anim_name].duplicate()
		sprite._build_animations()
		player.sprites[id] = sprite
		player.sprite_current_frames[id] = file.sprite_current_frames.get(id, 0)
		player.sprite_current_animation[id] = ""
		player.sprite_current_anim_frame[id] = 0

'''

#"PositionX":element_index = 0
#"PositionY":element_index = 1
#"Rotation":element_index = 2
#"ScaleX":element_index = 3
#"ScaleY":element_index = 4
#"Zindex":element_index = 5
#"Texture":element_index = 6
#"Hidden":element_index = 8
#"TintR":element_index = 11
#"TintG":element_index = 12
#"TintB":element_index = 13
#"TintA":element_index = 14
