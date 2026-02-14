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
var sprite_frame_timers : Dictionary = {} 
var sprite_current_frames : Dictionary = {} 
var sprite_current_anim_frame : Dictionary = {} 
var sprite_current_animation : Dictionary = {} 

var frame_timer : float = 0.0
var file_loaded_right : bool = false

var timeline_baked = true 
var resolved_display_lists : Dictionary = {}
var prev_resolved_display_lists : Dictionary = {}
var interp_alpha : float = 1.0

func _physics_process(delta):
	if !playing or !file_loaded_right:
		return

	# Accumulate delta for root only
	frame_timer += delta
	var frame_len := 1.0 / fps
	interp_alpha = clamp(frame_timer / frame_len, 0.0, 1.0)

	if frame_timer >= frame_len:
		frame_timer -= frame_len
		advance_frames()
		advance_children(animated_sprite_id, frame_len)
		queue_redraw()

func _draw():
	if !sprites.has(0):
		#printerr("Root sprite 0 missing")
		return
	draw_sprite_recursive(0, Transform2D.IDENTITY.scaled(draw_scale).translated(model_placement))

func advance_frames():
	var sp_id = animated_sprite_id
	if !sprites.has(sp_id):
		return
	var sprite : SWFClasses.SWFSprite = sprites[sp_id]

	var anim_keys = sprite.animations.keys()
	if anim_keys.size() > 0:
		if current_animation >= anim_keys.size():
			current_animation = 0
		var anim_name = anim_keys[current_animation]
		var anim_frames = sprite.animations[anim_name]

		var current = int(sprite_current_anim_frame.get(sp_id, 0))
		current += 1
		if current >= anim_frames.size():
			current = 0
		sprite_current_anim_frame[sp_id] = current
		sprite_current_frames[sp_id] = anim_frames[current]
	else:
		# fallback to raw frames
		if sprite.frames.size() > 0:
			var current = int(sprite_current_frames.get(sp_id, 0)) + 1
			if current >= sprite.frames.size():
				current = 0
			sprite_current_frames[sp_id] = current

func advance_children(sprite_id, dt):
	if !sprites.has(sprite_id):
		return
	var sprite = sprites[sprite_id]

	for child in sprite.children:
		var child_sprite = sprites.get(child.id, null)
		if child_sprite == null:
			continue

		if child.id != animated_sprite_id:
			# Determine visibility in parent frame
			var parent_frame_index = sprite_current_frames.get(sprite_id, 0)
			var parent_frame = sprite.frames[parent_frame_index]
			var child_visible := false
			for ft in parent_frame.values():
				if ft.symbol_id == child.id and ft.visible:
					child_visible = true
					break

			if !child_visible:
				sprite_frame_timers[child.id] = 0.0
				sprite_current_anim_frame[child.id] = 0
				sprite_current_frames[child.id] = 0
				
			else:
				if !sprite_frame_timers.has(child.id):
					sprite_frame_timers[child.id] = 0.0
				sprite_frame_timers[child.id] += dt

				var anim_keys = child_sprite.animations.keys()
				var anim_index = int(sprite_current_animation.get(child.id, 0))
				var anim_frames : Array = []

				if anim_keys.size() > 0:
					if anim_index >= anim_keys.size():
						anim_index = 0
					var anim_name = anim_keys[anim_index]
					anim_frames = child_sprite.animations[anim_name]
					sprite_current_animation[child.id] = anim_index

					while sprite_frame_timers[child.id] >= 1.0/fps:
						sprite_frame_timers[child.id] -= 1.0/fps
						var current = int(sprite_current_anim_frame.get(child.id, 0)) + 1
						if current >= anim_frames.size():
							current = 0
						sprite_current_anim_frame[child.id] = current
						sprite_current_frames[child.id] = anim_frames[current]
				else:
					while sprite_frame_timers[child.id] >= 1.0/fps:
						sprite_frame_timers[child.id] -= 1.0/fps
						var current = int(sprite_current_frames.get(child.id, 0)) + 1
						if current >= child_sprite.frames.size():
							current = 0
						sprite_current_frames[child.id] = current

		advance_children(child.id, dt)

func fall_back_advance_frames(root : SWFClasses.SWFSprite = null):
	if root == null:
		return
		
	var sp_id = animated_sprite_id
	if root.frames.is_empty():
		return
		
	var total_frames := root.frames.size()
	var current = sprite_current_frames.get(sp_id, 0)
	current += 1
	
	if current >= total_frames:
		current = 0
	sprite_current_frames[sp_id] = current
	
	for id in sprites.keys():
		if id != sp_id:
			sprite_current_frames[id] = current
	current_frame = current

func draw_sprite_recursive(sprite_id, parent_transform: Transform2D, parent_color: Color = Color(1,1,1,1), frame_lumi : float = 1.0):
	if !sprites.has(sprite_id):
		return

	var sprite : SWFClasses.SWFSprite = sprites[sprite_id]
	var frame_index = sprite_current_frames[sprite_id]
	if frame_index >= sprite.frames.size():
		frame_index = 0
	var frame_dict = sprite.frames[frame_index]
	var frame_items = frame_dict.values()
	frame_items.sort_custom(sort_frames)

	for ft in frame_items:
		if !ft.visible:
			continue

		# Compute final transform
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

		# Combine parent color with frame color
		var combined_color = ft.color * parent_color
		var combined_lumi = ft.lumi * frame_lumi

		if shapes.has(ft.symbol_id):
			draw_shape(shapes[ft.symbol_id], final_transform, combined_color, combined_lumi)
		elif sprites.has(ft.symbol_id):
			draw_sprite_recursive(ft.symbol_id, final_transform, combined_color, combined_lumi)

func draw_shape(shape: SWFClasses.SWFShape, _transform: Transform2D, frame_color: Color, frame_lumi : float = 1.0):
	if shape.subpaths.is_empty():
		return

	draw_set_transform_matrix(_transform)

	for sp in shape.subpaths:
		if draw_debug_mode:
			for line in sp["lines"]:
				var color = sp["color"] * frame_color
				if line["type"] == "line":
					draw_line(line["start"], line["end"], color, 1)
				elif line["type"] == "curve":
					draw_curve(line["start"], line["control"], line["end"], color)
		else:
			if sp["triangles"].has("points") and sp["triangles"].has("indices"):
				var points: PackedVector2Array = sp["triangles"]["points"]
				var indices: PackedInt32Array = sp["triangles"]["indices"]
				var colors: PackedColorArray = PackedColorArray()
				for i in range(points.size()):
					var final : Color = frame_color * sp["color"]
					final.lightened(frame_lumi)
					colors.append(final)
				if indices.is_empty() or points.is_empty(): continue
				RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)

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

func draw_curve(start_pt: Vector2, control_pt: Vector2, end_pt: Vector2, color: Color, steps := 10):
	var prev = start_pt
	for i in range(1, steps+1):
		var t = float(i)/float(steps)
		var curr = (1-t)*(1-t)*start_pt + 2*(1-t)*t*control_pt + t*t*end_pt
		draw_line(prev, curr, color, 1)
		prev = curr

func mark_frame_dirty(prev_frame: SWFClasses.SWFFrame, frame: SWFClasses.SWFFrame):
	frame.is_dirty = (prev_frame.x != frame.x or prev_frame.y != frame.y or prev_frame.scale_x != frame.scale_x or prev_frame.scale_y != frame.scale_y or prev_frame.rotation != frame.rotation or prev_frame.visible != frame.visible)
