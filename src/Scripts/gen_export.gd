extends Node

var gdwf_save_name : String = ""
var gdwf_export_folder : String = "user://Exports/"
var json_export_folder :String = "user://JsonExports/"
var svg_export_folder : String = "user://SVGExports/"
var skf_export_folder : String = "user://SKFExports/"
var use_fallback : bool = false
var hollow_pieces : bool = false


#region Json Stuff
# -- Json import/ export
func parse_json(data: Dictionary, player : SWFPlayer, smooth : int = 5) -> Array:
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
			shape.build_geometry(smooth, hollow_pieces)
			
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
	
	player.center_model()
	player.file_loaded_right = true
	return returned_shapes

# Done!
func export_json_optimized(player : SWFPlayer = null, file_name : String = ""):
	if !player: return
	
	var main_structure : Dictionary = {
		"Sprites" : {},
		"Shapes" : {},
		"AnimatedSpriteID" : player.animated_sprite_id,
		"ModelPlacement" : {x = player.model_placement.x, y = player.model_placement.y},
		"FPS" : player.fps,
	}

	for sp in player.sprites.keys():
		main_structure["Sprites"][sp] = player.sprites[sp].get_data()
		
	for sh in player.shapes.keys():
		main_structure["Shapes"][sh] = player.shapes[sh].get_data()

	var json := JSON.stringify(main_structure, "\t")
	var file := FileAccess.open(json_export_folder + "/" + file_name + ".json", FileAccess.WRITE)
	file.store_string(json)
	file.close()

#endregion

#region SKF Export

# SKF Export (Wip)
# small notes, yes, .skf is very much a renamed ZIP file format. it contains two main files, the image atlas (atlas{x}.png) and armature.json
func export_skelform(player: SWFPlayer, file_name: String = "", _data : Dictionary = {}):
	if player == null:
		push_error("Player is null")
		return
	var zip := ZIPPacker.new()
	var path := skf_export_folder + "/" + file_name + ".skf"
	print("EXPORT PATH:", path)
	
	if zip.open(path) != OK:
		push_error("Failed to create SKF")
		return
	
	# basic armature.json data structure
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

	# checks if the player has a root sprite.
	if !player.sprites.has(0):
		push_error("Sprite 0 missing")
		zip.close()
		return
	var bones_list = []
	
	# adds root bone
	var root_bone = {
		"id": 0,
		"parent_id": -1,
		"name": "Root",
		"pos": {"x": player.model_placement.x, "y": -player.model_placement.y},
		"scale": {"x": 1.0, "y": 1.0},
		"rot": 0.0,
		"tex": "",
		"zindex": 0,
		"ik_family_id": -1,
	}
	bones_list.append(root_bone)
	
	var _symbol_to_bone : Dictionary = {}
	build_bones_recursive(player, 0, 0, bones_list, _symbol_to_bone)
	
	# build animations for the skf export, i am very brain fried, this code is such a headache.
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

func build_animations(player: SWFPlayer, root_sprite_id: int, bones_list: Array) -> Array:
	var animations_list = []
	# check the player's main root sprite, since at least with the style of swf i am working with. 
	# it is mainly a standalone character rig where a root sprite usually holds all the animation data. 
	if !player.sprites.has(root_sprite_id):
		return animations_list

	var root_sprite : SWFClasses.SWFSprite = player.sprites[root_sprite_id]
	var symbol_to_bones_map = {}

	# checks the symbols and if their id/ data is valid.
	for b in bones_list:
		if b.name.begins_with("symbol_"):
			var parts = b.name.split("_")
			var sym_id = int(parts[1])
			if !symbol_to_bones_map.has(sym_id):
				symbol_to_bones_map[sym_id] = []
			symbol_to_bones_map[sym_id].append(b.id)

	# loops through the global animations of the character swf rig
	var anim_names = root_sprite.animations.keys()
	for anim_id in range(anim_names.size()):
		var anim_name = anim_names[anim_id]
		var frame_indices = root_sprite.animations[anim_name]
		if frame_indices.is_empty():
			continue

		var anim = {"name": anim_name, "id": anim_id, "fps": player.fps, "keyframes": []}

		var last_values = {}
		# creates placeholder data for the bones and stores them in the last_values dictionary
		for b in bones_list:
			last_values[b.id] = {
				"PositionX": 0.0,
				"PositionY": 0.0,
				"Rotation": 0.0,
				"ScaleX": 1.0,
				"ScaleY": 1.0,
				"Zindex": 0,
				"Hidden": 0.0
			}

		var frame_offset = frame_indices[0]
		for f_idx in frame_indices:
			var local_frame = f_idx - frame_offset
			if local_frame < 0 or f_idx >= root_sprite.frames.size():
				continue

			var frame_data = root_sprite.frames[f_idx]
			var frames = frame_data.keys()

			#loops through the frames of the current selected animation.
			for current_frame in frames:
				var ft = frame_data[current_frame]
				var target_bone_ids = symbol_to_bones_map.get(ft.symbol_id, [])
				
				# check visibility, for some reason skf uses floats instead of bools?
				var hidden_val = 0.0
				if !ft.visible:
					hidden_val = 1.0
					

				for bone_id in target_bone_ids:
					var local_pos = Vector2(ft.local_x, ft.local_y)
					var local_transform = Transform2D.IDENTITY
					local_transform = local_transform.scaled(Vector2(ft.scale_x, ft.scale_y))
					local_transform = local_transform.rotated(deg_to_rad(ft.rotation))
					local_transform = local_transform.translated(local_pos)

					var current_values = {
						"PositionX": local_transform.get_origin().x,
						"PositionY": local_transform.get_origin().y,
						"Rotation": local_transform.get_rotation(),
						"ScaleX": local_transform.get_scale().x,
						"ScaleY": local_transform.get_scale().y,
						"Zindex": ft.depth,
						"Hidden": hidden_val
					}

					# loop through each property and add a keyframe if it changed
					for element_str in current_values.keys():
						var val = current_values[element_str]
						var add_keyframe = true
						if last_values[bone_id].has(element_str):
							if last_values[bone_id][element_str] == val:
								add_keyframe = false

						if add_keyframe:
							last_values[bone_id][element_str] = val
							var element_index = match_element_keyframe(element_str)
							anim["keyframes"].append({
								"frame": local_frame,
								"bone_id": bone_id,
								"element": element_index,
								"element_str": element_str,
								"value": val,
								"transition": "Linear"
							})
						var tex_name = "shape_%d" % ft.symbol_id
						if player.shapes.has(ft.symbol_id):
							if last_values[bone_id].get("Texture", "") != tex_name:
								last_values[bone_id]["Texture"] = tex_name
								anim["keyframes"].append({
									"frame": local_frame,
									"bone_id": bone_id,
									"element": 6, # Texture
									"element_str": "Texture",
									"value_str": tex_name,
									"value": 0.0,
									"transition": "Linear"
								})

		animations_list.append(anim)

	# flip ScaleY for frames where rotation is beyond 90 deg
	# todo: make this a toggle, as not all SWFs may flip like this
	# todo: handle roundabouts (Partially fixed?)
	for anim in animations_list:
		var flip_state = {}
		var prev_rot = {}
		for k in range(anim["keyframes"].size()):
			var kf = anim["keyframes"][k]
			var key = str(kf.bone_id) + "_" + str(kf.frame)

			if kf.element == 2: # Rotation
				var bone_id = kf.bone_id
				var rot = kf.value
				if prev_rot.has(bone_id):
					var delta = calculate_shortest_angle(prev_rot[bone_id], rot)
					rot = prev_rot[bone_id] + delta
				kf.value = rot
				prev_rot[bone_id] = rot
				flip_state[key] = abs(rot) > PI * 0.5
				continue

			if kf.element == 4 and flip_state.get(key, false): # ScaleY
				kf.value = -kf.value

	return animations_list

func build_bones_recursive(player: SWFPlayer, sprite_id: int, parent_bone_idx: int, bones_list: Array, symbol_to_bone : Dictionary = {}):
	if !player.sprites.has(sprite_id):
		return

	var sprite : SWFClasses.SWFSprite = player.sprites[sprite_id]
	if sprite.frames.size() == 0:
		return
	
	# loop through all sprite's frames
	for h in sprite.frames.size():
		var frame_dict = sprite.frames[h]
		var frames = frame_dict.keys()

		for current_frame in frames:
			var ft = frame_dict[current_frame]

			# Use parent + sprite + symbol only to prevent duplicates (ignore current_frame)
			var bone_idx = bones_list.size()
			var bone_key = str(parent_bone_idx) + "_" + str(sprite_id) + "_" + str(ft.symbol_id)
			if symbol_to_bone.has(bone_key):
				# Already created a bone for this symbol under this parent
				bone_idx = symbol_to_bone[bone_key]
			else:
				# basic bone data
				var local_pos = Vector2(ft.x, -ft.y)
				var local_transform : Transform2D = Transform2D.IDENTITY
				var tex_name = ""
				
				if player.shapes.has(ft.symbol_id):
					tex_name = "shape_%d" % ft.symbol_id
					local_pos = get_local_shape(player, ft)
				
				# applying transformation
				local_transform = local_transform.scaled(Vector2(ft.scale_x, ft.scale_y))
				local_transform = local_transform.rotated(deg_to_rad(ft.rotation))
				local_transform = local_transform.translated(local_pos)

				# Create bone
				var bone = {
					"id": bone_idx,
					"parent_id": parent_bone_idx,
					"name": "symbol_%d" % ft.symbol_id,
					"pos": {"x": local_transform.get_origin().x, "y": local_transform.get_origin().y},
					"scale": {"x": local_transform.get_scale().x, "y": local_transform.get_scale().y},
					"rot": local_transform.get_rotation(),
					"tex": tex_name,
					"zindex": ft.depth,
					"ik_family_id": -1,
				}
				
				# Add bone to array
				bones_list.append(bone)
				symbol_to_bone[bone_key] = bone_idx

			# Recurse through the rest of the bones
			if player.sprites.has(ft.symbol_id):
				build_bones_recursive(player, ft.symbol_id, bone_idx, bones_list, symbol_to_bone)

# -- Helper 
func get_local_shape(player, ft):
	if ft == null or !is_instance_valid(ft): return Vector2.ZERO
	var shape = player.shapes.get(ft.symbol_id)
	var pos := Vector2(ft.x, ft.y)
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	if shape == null: return Vector2.ZERO
	for sp in shape.subpaths:
		for seg in sp["segments"]:
			for pt in [seg.Start, seg.End, seg.Control]:
				var pt_pos = Vector2(pt["X"], pt["Y"])
				if pt_pos != Vector2.ZERO:
					var transformed = pos + pt_pos
					min_pt = Vector2(min(min_pt.x, transformed.x), min(min_pt.y, transformed.y))
					max_pt = Vector2(max(max_pt.x, transformed.x), max(max_pt.y, transformed.y))
	var local_pos = (min_pt + max_pt) * 0.5

	# flip Y, since swf is -Y while skf is +Y
	local_pos.y = -local_pos.y
	return local_pos

func calculate_shortest_angle(from, to) -> float :
	var delta = to - from 
	delta = fposmod(delta - PI, TAU) - PI
	return delta

# returns the matched keyframe type, since again.. skf seems to have two checks??
func match_element_keyframe(element_str) -> int:
	var element_index : int = 0
	match element_str:
		"PositionX":
			element_index = 0
		"PositionY":
			element_index = 1
		"Rotation":
			element_index = 2
		"ScaleX":
			element_index = 3
		"ScaleY":
			element_index = 4
		"Zindex":
			element_index = 5
		"Texture":
			element_index = 6
		"Hidden":
			element_index = 8
		"TintR":
			element_index = 11
		"TintG":
			element_index = 12
		"TintB":
			element_index = 13
		"TintA":
			element_index = 14
	return element_index

# -- Misc functions
# Builds the texture atlas for the Skelform export.
# todo: more accurate resolution instead of a resized bone in the skf export. should help with the weird resolution issue?
func create_texture_atlas(player: SWFPlayer) -> Dictionary:
	var atlas_img : Image = Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0,0,0,0))
	
	var style_textures : Array = []
	var texture_map : Dictionary = {} 
	var cursor : Vector2 = Vector2(0, 0)
	var row_height : int = 0
	
	var shape_ids = player.shapes.keys()
	
	for sid in shape_ids:
		var s : SWFClasses.SWFShape = player.shapes[sid]
		
		if s.svg_text.is_empty():
			s.generate_svg()
		
		var img : Image = Image.new()
		if s.svg_text.is_empty(): continue
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
		"texture_map": texture_map}

#endregion

#region Misc import/ export
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

#endregion

func _on_fallback_gen_toggled(toggled_on: bool) -> void:
	use_fallback = toggled_on

func _on_hole_detection_toggled(toggled_on: bool) -> void:
	hollow_pieces = toggled_on

func regen_shapes(player : SWFPlayer, smooth : int):
	for sp in player.shapes.values():
		sp.build_geometry(use_fallback, smooth, hollow_pieces)
