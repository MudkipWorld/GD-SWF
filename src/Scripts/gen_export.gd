extends Node

var gdwf_save_name : String = ""
var gdwf_export_folder : String = "user://Exports/"
var json_export_folder :String = "user://JsonExports/"
var svg_export_folder : String = "user://SVGExports/"
var skf_export_folder : String = "user://SKFExports/"
var use_fallback : bool = false
var smooth_iteration : int = 5
var hollow_pieces : bool = false

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

func export_all_svgs(player : SWFPlayer):
	if !DirAccess.dir_exists_absolute(svg_export_folder):
		DirAccess.make_dir_absolute(svg_export_folder)
	for shape_id in player.shapes.keys():
		var shape : SWFClasses.SWFShape = player.shapes[shape_id]
		#shape._generate_svg()
		var svg_str = shape.to_svg()
		if svg_str.is_empty():continue
		var file_path = svg_export_folder + "/" + "%s.svg" % shape_id
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_string(svg_str)
			file.close()

func parse_json(data: Dictionary, player : SWFPlayer, bake : bool = true) -> Array:
	player.file_loaded_right = false
	if data.is_empty():
		printerr("JSON parse error")
		return []
		
	player.shapes.clear()
	player.sprites.clear()
	player.sprite_current_frames.clear()
	player.sprite_current_animation.clear()
	player.sprite_current_anim_frame.clear()
	var returned_shapes : Array = []
	if data.has("Shapes"):
		for id in data["Shapes"].keys():
			var shape = SWFClasses.SWFShape.new(data["Shapes"][id])
			shape.build_geometry(use_fallback, smooth_iteration, hollow_pieces)
			shape._generate_svg()
			var image = Image.new()
			if !shape.to_svg().is_empty():
				image.load_svg_from_string(shape.to_svg())
				shape.texture = ImageTexture.create_from_image(image)
			player.shapes[id] = shape
			returned_shapes.append({shape = shape, id = id })
	if data.has("Sprites"):
		for id in data["Sprites"].keys():
			var sprite = SWFClasses.SWFSprite.new(data["Sprites"][id])
			player.sprites[id] = sprite
			player.sprite_current_frames[id] = 0
			player.sprite_current_animation[id] = ""
			player.sprite_current_anim_frame[id] = 0
	
	player.animated_sprite_id = int(data["Sprites"].keys()[-1])
	
	player.timeline_baked = bake
	player.center_model()
	player.file_loaded_right = true
	return returned_shapes

func _on_fallback_gen_toggled(toggled_on: bool) -> void:
	use_fallback = toggled_on

func _on_hole_detection_toggled(toggled_on: bool) -> void:
	hollow_pieces = toggled_on

func regen_shapes(player : SWFPlayer):
	for sp in player.shapes.values():
		sp.build_geometry(use_fallback, smooth_iteration, hollow_pieces)

func export_json_optimized(data : Dictionary = {}, file_name : String = ""):
	if data.is_empty(): return
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(json_export_folder + "/" + file_name + ".json", FileAccess.WRITE)
	file.store_string(json)
	file.close()

func matrix_equals(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if abs(a[i] - b[i]) > 0.0001:
			return false
	return true

#------Fancy lines, okay, no joke, i am very stuck, check the issue.png in the source to see why...

func export_skelform(player: SWFPlayer, file_name: String = ""):
	if player == null:
		push_error("Player is null")
		return
	var zip := ZIPPacker.new()
	var path := skf_export_folder + "/" + file_name + ".skf"
	print("EXPORT PATH:", path)
	if zip.open(path) != OK:
		push_error("Failed to create SKF")
		return
	var armature := {
		"version": "0.2.0",
		"ik_root_ids": [],
		"styles": [],
		"bones": [],
		"animations": [],
		"atlases": []
	}
	var atlas_data = create_texture_atlas(player)
	armature["styles"].append(atlas_data["style"])
	armature["atlases"].append(atlas_data["atlas_info"])

	if !player.sprites.has(0):
		push_error("Sprite 0 missing")
		zip.close()
		return
	var bones_list = []
	var root_bone = {
		"id": 0,
		"parent_id": -1,
		"name": "Root",
		"pos": {"x": player.model_placement.x, "y": -player.model_placement.y},
		"scale": {"x": 1.0, "y": 1.0},
		"rot": 0.0,
		"init_pos": {"x": player.model_placement.x, "y": -player.model_placement.y},
		"init_scale": {"x": 1.0, "y": 1.0},
		"init_rot": 0.0,
		"tex": "",
		"zindex": 0,
		"ik_family_id": -1,
		"ik_mode": 0,
		"ik_target_id": -1,
		"ik_constraint": 0,
		"ik_constraint_str": "None",
		"ik_bone_ids": [],
		"binds": [],
		"vertices": [],
		"indices": [],
		"is_hidden": false,
		"init_is_hidden": false
	}
	bones_list.append(root_bone)
	build_bones_recursive(player, 0, 0, bones_list)
	armature["bones"] = bones_list
	var animations_list = build_animations(player, player.animated_sprite_id, bones_list)
	armature["animations"] = animations_list
	var json_data := JSON.stringify(armature, "\t")
	zip.start_file("armature.json")
	zip.write_file(json_data.to_utf8_buffer())
	zip.close_file()
	zip.start_file("atlas0.png")
	zip.write_file(atlas_data["image"].save_png_to_buffer())
	zip.close_file()
	zip.close()
	print("SKF export complete:", path)

func build_bones_recursive(player: SWFPlayer, sprite_id: int, parent_bone_idx: int, bones_list: Array):
	if !player.sprites.has(sprite_id):
		return
	var sprite : SWFClasses.SWFSprite = player.sprites[sprite_id]
	if sprite.frames.size() == 0:
		return
	var frame_dict = sprite.frames[0]
	var depths = frame_dict.keys()
	depths.sort()
	for depth in depths:
		var ft = frame_dict[depth]
		
		var my_bone_idx = bones_list.size()
		var local_pos = Vector2(ft.local_x, ft.local_y)

		var tex_name = ""
		if player.shapes.has(ft.symbol_id):
			tex_name = "shape_%d" % ft.symbol_id

			# override local pos to be the offset of this shape
			var shape = player.shapes.get(ft.symbol_id)
			var pos := Vector2(ft.x, ft.y)
			var min_pt := Vector2(INF, INF)
			var max_pt := Vector2(-INF, -INF)
			for sp in shape.subpaths:
				for seg in sp["segments"]:
					for pt in [seg.Start, seg.End, seg.Control]:
						var pt_pos = Vector2(pt["X"], pt["Y"])
						if pt_pos != Vector2.ZERO:
							var transformed = pos + pt_pos
							min_pt = Vector2(min(min_pt.x, transformed.x), min(min_pt.y, transformed.y))
							max_pt = Vector2(max(max_pt.x, transformed.x), max(max_pt.y, transformed.y))
			local_pos = (min_pt + max_pt) * 0.5

			# flip Y, since swf is -Y while skf is +Y
			local_pos.y = -local_pos.y

		var bone = {
			"id": my_bone_idx,
			"parent_id": parent_bone_idx,
			"name": "symbol_%d" % ft.symbol_id,
			"pos": {"x": local_pos.x, "y": local_pos.y},
			"scale": {"x": ft.scale_x, "y": ft.scale_y},
			"rot": deg_to_rad(ft.rotation),
			"init_pos": {"x": local_pos.x, "y": local_pos.y},
			"init_scale": {"x": ft.scale_x, "y": ft.scale_y},
			"init_rot": deg_to_rad(ft.rotation),
			"tex": tex_name,
			"zindex": depth,
			"ik_family_id": -1,
			"ik_mode": 0,
			"ik_target_id": -1,
			"ik_constraint": 0,
			"ik_constraint_str": "None",
			"ik_bone_ids": [],
			"binds": [],
			"vertices": [],
			"indices": [],
			"is_hidden": false,
			"init_is_hidden": false
		}
		bones_list.append(bone)
		
		if player.sprites.has(ft.symbol_id):
			build_bones_recursive(player, ft.symbol_id, my_bone_idx, bones_list)

func build_animations(player: SWFPlayer, root_sprite_id: int, bones_list: Array) -> Array:
	var animations_list = []
	if !player.sprites.has(root_sprite_id):
		return animations_list
	var root_sprite : SWFClasses.SWFSprite = player.sprites[root_sprite_id]
	var symbol_to_bones_map = {}
	for b in bones_list:
		if b.name.begins_with("symbol_"):
			var parts = b.name.split("_")
			var sym_id = int(parts[1])
			if !symbol_to_bones_map.has(sym_id):
				symbol_to_bones_map[sym_id] = []
			symbol_to_bones_map[sym_id].append(b.id)
	var anim_names = root_sprite.animations.keys()
	for anim_id in range(anim_names.size()):
		var anim_name = anim_names[anim_id]
		var anim = {"name": anim_name, "id": anim_id, "fps": player.fps, "keyframes": []}
		var frame_indices = root_sprite.animations[anim_name]
		if frame_indices.is_empty():
			continue
		var frame_offset = frame_indices[0]
		for f_idx in frame_indices:
			var local_frame = f_idx - frame_offset
			if local_frame < 0 or f_idx >= root_sprite.frames.size():
				continue
			var frame_data = root_sprite.frames[f_idx]
			var depths = frame_data.keys()
			for depth in depths:
				var ft = frame_data[depth]
				if !ft.visible:
					continue
				var target_bone_ids = symbol_to_bones_map.get(ft.symbol_id, [])
				var global_pos = to_skel_pos(ft)
				for bone_id in target_bone_ids:
					var parent_id = bones_list[bone_id]["parent_id"]
					var local_pos = global_pos
					var parent_rot = 0.0
					var parent_scale = Vector2(1, 1)
					if parent_id >= 0:
						local_pos -= Vector2(bones_list[parent_id]["pos"]["x"], bones_list[parent_id]["pos"]["y"])
						parent_rot = bones_list[parent_id]["rot"]
						parent_scale = Vector2(bones_list[parent_id]["scale"]["x"], bones_list[parent_id]["scale"]["y"])
						local_pos = local_pos.rotated(-parent_rot)
						local_pos.x /= max(parent_scale.x, 0.0001)
						local_pos.y /= max(parent_scale.y, 0.0001)
					anim["keyframes"].append({
						"frame": local_frame,
						"bone_id": bone_id,
						"element": 0,
						"element_str": "PositionX",
						"value": local_pos.x,
						"transition": "Linear"
					})
					anim["keyframes"].append({
						"frame": local_frame,
						"bone_id": bone_id,
						"element": 1,
						"element_str": "PositionY",
						"value": local_pos.y,
						"transition": "Linear"
					})
					anim["keyframes"].append({
						"frame": local_frame,
						"bone_id": bone_id,
						"element": 2,
						"element_str": "Rotation",
						"value": deg_to_rad(ft.rotation),
						"transition": "Linear"
					})
					anim["keyframes"].append({
						"frame": local_frame,
						"bone_id": bone_id,
						"element": 3,
						"element_str": "ScaleX",
						"value": ft.scale_x,
						"transition": "Linear"
					})
					anim["keyframes"].append({
						"frame": local_frame,
						"bone_id": bone_id,
						"element": 4,
						"element_str": "ScaleY",
						"value": ft.scale_y,
						"transition": "Linear"
					})
		animations_list.append(anim)
	return animations_list

func create_texture_atlas(player: SWFPlayer) -> Dictionary:
	var atlas_img := Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0,0,0,0))
	
	var style_textures := []
	var texture_map := {} 
	
	var cursor := Vector2(0, 0)
	var row_height := 0
	
	var shape_ids = player.shapes.keys()
	
	for sid in shape_ids:
		var s : SWFClasses.SWFShape = player.shapes[sid]
		
		if s.svg_text.is_empty():
			s._generate_svg()
		
		var img := Image.new()
		var err = img.load_svg_from_string(s.svg_text)
		
		if err != OK or img.is_empty():
			continue

		if cursor.x + img.get_width() > atlas_img.get_width():
			cursor.x = 0
			cursor.y += row_height
			row_height = 0
		
		atlas_img.blit_rect(img, Rect2(Vector2.ZERO, img.get_size()), cursor)
		
		var tex_info = {
			"offset": Vector2(cursor.x, cursor.y),
			"size": Vector2(img.get_width(), img.get_height())
		}
		texture_map[int(sid)] = tex_info
		
		style_textures.append({
			"name": "shape_%d" % sid,
			"offset": {"x": int(tex_info.offset.x), "y": int(tex_info.offset.y)},
			"size": {"x": int(tex_info.size.x), "y": int(tex_info.size.y)},
			"atlas_idx": 0
		})
		
		cursor.x += img.get_width()
		row_height = max(row_height, img.get_height())

	return {
		"image": atlas_img,
		"style": {"name": "Default", "textures": style_textures},
		"atlas_info": {"filename": "atlas0.png", "size": {"x": atlas_img.get_width(), "y": atlas_img.get_height()}},
		"texture_map": texture_map
	}

func to_skel_pos(ft: SWFClasses.SWFFrame) -> Vector2:
	var t = Vector2(ft.x, -ft.y)
	return t
