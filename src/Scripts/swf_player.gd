extends Node2D
class_name SWFPlayer

@export var playing : bool = false
@export var fps : int = 24
@export var draw_scale : Vector2 = Vector2.ONE
@export var current_animation : int = 0

var draw_debug_mode : bool = false
var model_placement : Vector2
var animated_sprite_id : int = 0

var shapes : Dictionary = {}
var sprites : Dictionary = {} 
var current_frame : int = 0
var sprite_current_frames : Dictionary = {} 
var sprite_current_animation : Dictionary = {}
var sprite_current_anim_frame : Dictionary = {} 
var frame_timer : float = 0.0
var file_loaded_right : bool = false

var timeline_baked = true 
var resolved_display_lists : Dictionary = {}
var prev_resolved_display_lists : Dictionary = {}
var interp_alpha : float = 1.0

func _physics_process(delta):
	if !playing or !file_loaded_right:
		return

	frame_timer += delta
	var frame_len := 1.0 / fps
	interp_alpha = clamp(frame_timer / frame_len, 0.0, 1.0)

	if frame_timer >= frame_len:
		frame_timer = 0.0
		advance_frames()
		queue_redraw()

func _draw():
	if !sprites.has(0):
		#printerr("Root sprite 0 missing")
		return
	draw_sprite_recursive(0, Transform2D.IDENTITY.scaled(draw_scale).translated(model_placement))

func advance_frames():
	if sprites.is_empty():
		return
	var sp_id = animated_sprite_id
	if !sprites.has(sp_id):
		return
	var root_sprite : SWFClasses.SWFSprite = sprites[sp_id]
	var anim_keys = root_sprite.animations.keys()
	if anim_keys.is_empty():
		return
	if current_animation >= anim_keys.size():
		current_animation = 0
	var anim_name = anim_keys[current_animation]
	var anim_frames : Array = root_sprite.animations[anim_name]

	var current = sprite_current_anim_frame.get(sp_id, 0)
	current += 1
	if current >= anim_frames.size():
		current = 0
	sprite_current_anim_frame[sp_id] = current
	sprite_current_frames[sp_id] = anim_frames[current]
	for id in sprites.keys():
		if id != sp_id:
			sprite_current_frames[id] = sprite_current_frames[sp_id]

	current_frame = sprite_current_frames[sp_id]

func compute_local_positions(sprite_id: int, parent_transform: Transform2D = Transform2D.IDENTITY):
	if not sprites.has(sprite_id):
		return
	
	var sprite : SWFClasses.SWFSprite = sprites[sprite_id]
	
	for frame_dict in sprite.frames:
		for ft in frame_dict.values():
			var local_pos = parent_transform.basis_xform(Vector2(ft.x, ft.y))
			ft.local_x = local_pos.x
			ft.local_y = local_pos.y

	for child in sprite.children:
		if sprites.has(child.id):
			var t = Transform2D.IDENTITY.translated(Vector2(sprite.local_x, sprite.local_y))
			compute_local_positions(child.id, parent_transform * t)

func draw_sprite_recursive(sprite_id, parent_transform: Transform2D):
	if !sprites.has(sprite_id):
		return
	var sprite : SWFClasses.SWFSprite = sprites[sprite_id]
	var frame_index = sprite_current_frames[sprite_id]
	if frame_index >= sprite.frames.size():
		frame_index = 0
	var frame_dict = sprite.frames[frame_index]
	var frame_items = frame_dict.values()
	frame_items.sort_custom(sort_frames)
	for item in frame_items:
		var ft : SWFClasses.SWFFrame = item
		if !ft.visible:
			continue
		var final_transform : Transform2D
		if ft.transform_matrix.size() == 6:
			var m = ft.transform_matrix
			var local = Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
			final_transform = parent_transform * local
		else:
			var local = Transform2D.IDENTITY.scaled(Vector2(ft.scale_x, ft.scale_y))
			local = local.rotated(-deg_to_rad(ft.rotation))
			local = local.translated(Vector2(ft.x, ft.y))
			final_transform = parent_transform * local
		if shapes.has(ft.symbol_id):
			draw_shape(shapes[ft.symbol_id], final_transform)
		elif sprites.has(ft.symbol_id):
			draw_sprite_recursive(ft.symbol_id, final_transform)

func frame_to_transform(ft):
	if ft.transform_matrix.size() == 6:
		var m = ft.transform_matrix
		return Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
	var t = Transform2D.IDENTITY
	t = t.scaled(Vector2(ft.scale_x, ft.scale_y))
	t = t.rotated(-deg_to_rad(ft.rotation))
	t = t.translated(Vector2(ft.x, ft.y))
	return t

func frame_to_transform_lerp(prev, curr, alpha: float) -> Transform2D:
	if prev == null:
		return frame_to_transform(curr)
	var pm : Array
	if prev.transform_matrix.size() == 6:
		pm = prev.transform_matrix
	else:
		pm = build_matrix_from_components(prev)
	var cm : Array
	if curr.transform_matrix.size() == 6:
		cm = curr.transform_matrix
	else:
		cm = build_matrix_from_components(curr)
	var m := []
	for i in range(6):
		m.append(lerp(pm[i], cm[i], alpha))

	return Transform2D(
		Vector2(m[0], m[1]),
		Vector2(m[2], m[3]),
		Vector2(m[4], m[5])
	)

func build_matrix_from_components(ft) -> Array:
	var t = Transform2D.IDENTITY
	t = t.scaled(Vector2(ft.scale_x, ft.scale_y))
	t = t.rotated(-deg_to_rad(ft.rotation))
	t = t.translated(Vector2(ft.x, ft.y))

	return [
		t.x.x, t.x.y,
		t.y.x, t.y.y,
		t.origin.x, t.origin.y
	]

func sort_frames(a, b):
	if a.depth != b.depth:
		return a.depth < b.depth
	if a.symbol_id != b.symbol_id:
		return a.symbol_id < b.symbol_id
	return int(a.get_instance_id()) < int(b.get_instance_id())

func center_model():
	if !sprites.has(0):
		return

	var root_sprite : SWFClasses.SWFSprite = sprites[0]
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for frame_dict in root_sprite.frames:
		for ft in frame_dict.values():
			var pos := Vector2(ft.x, ft.y)
			min_pt = Vector2(min(min_pt.x, pos.x), min(min_pt.y, pos.y))
			max_pt = Vector2(max(max_pt.x, pos.x), max(max_pt.y, pos.y))
			
			if shapes.has(ft.symbol_id):
				var shape = shapes[ft.symbol_id]
				for sp in shape.subpaths:
					for seg in sp["segments"]:
						for pt in [seg.Start, seg.End, seg.Control]:
							if pt != Vector2.ZERO:
								var transformed = pos + pt
								min_pt = Vector2(min(min_pt.x, transformed.x), min(min_pt.y, transformed.y))
								max_pt = Vector2(max(max_pt.x, transformed.x), max(max_pt.y, transformed.y))

	var center = (min_pt + max_pt) * 0.5
	model_placement = -center

func draw_shape(shape: SWFClasses.SWFShape, _transform: Transform2D):
	if shape.subpaths.is_empty():
		return
	draw_set_transform_matrix(_transform)
	for sp in shape.subpaths:
		# debug lines
		if draw_debug_mode:
			for line in sp["lines"]:
				if line["type"] == "line":
					draw_line(line["start"], line["end"], sp["color"], 1)
				elif line["type"] == "curve":
					draw_curve(line["start"], line["control"], line["end"], sp["color"])
		else:
			if sp["triangles"].has("points") and sp["triangles"].has("indices"):
				var points: PackedVector2Array = sp["triangles"]["points"]
				var indices: PackedInt32Array = sp["triangles"]["indices"]
				var colors: PackedColorArray = PackedColorArray()
				for i in range(points.size()):
					colors.append(sp["color"])
				
				RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),indices,points,colors)

func draw_curve(start_pt: Vector2, control_pt: Vector2, end_pt: Vector2, color: Color, steps := 10):
	var prev = start_pt
	for i in range(1, steps+1):
		var t = float(i)/float(steps)
		var curr = (1-t)*(1-t)*start_pt + 2*(1-t)*t*control_pt + t*t*end_pt
		draw_line(prev, curr, color, 1)
		prev = curr

func mark_frame_dirty(prev_frame: SWFClasses.SWFFrame, frame: SWFClasses.SWFFrame):
	frame.is_dirty = (prev_frame.x != frame.x or prev_frame.y != frame.y or prev_frame.scale_x != frame.scale_x or prev_frame.scale_y != frame.scale_y or prev_frame.rotation != frame.rotation or prev_frame.visible != frame.visible)
