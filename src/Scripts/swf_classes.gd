extends RefCounted
class_name SWFClasses

class SWFChild:
	var id : int
	var type : String
	func _init(data : Dictionary):
		id = data.get("ID", 0)
		type = data.get("Type", "Shape")

class SWFFrame:
	var symbol_id : int
	var depth : int
	var x : float
	var y : float
	var scale_x : float
	var scale_y : float
	var rotation : float
	var transform_matrix : Array = []
	var visible : bool = true
	var is_dirty : bool = true 
	var local_x: float = 0.0
	var local_y: float = 0.0
	func _init(data : Dictionary):
		symbol_id = data.get("SymbolID", 0)
		depth = data.get("Depth", 0)
		x = data.get("X", 0.0)
		y = data.get("Y", 0.0)
		scale_x = data.get("ScaleX", 1.0)
		scale_y = data.get("ScaleY", 1.0)
		rotation = data.get("Rotation", 0.0)
		
		local_x = data.get("LocalX", 0)
		local_y = data.get("LocalY", 0)
		visible = data.get("Visible", true)
		is_dirty = true
		if data.has("TransformMatrix"):
			transform_matrix = data["TransformMatrix"]


class SWFShape:
	var subpaths: Array = []
	var offset: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2.ZERO
	var svg_text: String = ""
	var texture : ImageTexture = null

	var curve_subdivisions := 5
	
	func _init(data: Dictionary):
		if not data.has("SubPaths"):
			return

		for sp in data["SubPaths"]:
			var segments = sp.get("Segments", [])
			if segments == null or segments.is_empty():
				continue

			var c = sp.get("FillColor", {"R":255,"G":255,"B":255,"A":255})
			var color = Color(c["R"]/255.0, c["G"]/255.0, c["B"]/255.0, c["A"]/255.0)
			
			subpaths.append({
				"segments": segments,
				"lines": [],
				"polygons": [],
				"triangles": {},
				"color": color
			})

	func build_geometry(use_fallback: bool = false, smooth_interation: int = 20, hollow_pieces: bool = false):
		var min_pt = Vector2(INF, INF)
		var max_pt = Vector2(-INF, -INF)

		var all_polygons_in_shape := []
		var polygon_source_info := []

		for sp_idx in range(subpaths.size()):
			var sp = subpaths[sp_idx]
			var lines := []
			var polygons := []
			var poly := PackedVector2Array()
			var last_end := Vector2.INF

			for seg in sp["segments"]:
				if not seg.has("Start") or not seg.has("End") or not seg.has("Type"):
					continue

				var start_pt = Vector2(seg["Start"]["X"], seg["Start"]["Y"])
				var end_pt = Vector2(seg["End"]["X"], seg["End"]["Y"])

				# start a new polygon if discontinuity
				if poly.size() > 0 and last_end != Vector2.INF:
					if start_pt.distance_squared_to(last_end) > 0.0001:
						poly = _simplify_collinear(poly, 0.01)
						if poly.size() >= 3:
							polygons.append(poly)
						poly = PackedVector2Array()
				if poly.size() == 0:
					poly.append(start_pt)
				min_pt = min_pt.min(start_pt).min(end_pt)
				max_pt = max_pt.max(start_pt).max(end_pt)
				var line_data = {"type": seg["Type"], "start": start_pt, "end": end_pt, "control": Vector2.ZERO}
				if seg["Type"] == "curve" and seg.has("Control"):
					var ctrl = seg["Control"]
					if typeof(ctrl) == TYPE_DICTIONARY:
						var ctrl_pt = Vector2(ctrl.get("X", 0), ctrl.get("Y", 0))
						line_data["control"] = ctrl_pt
						min_pt = min_pt.min(ctrl_pt)
						max_pt = max_pt.max(ctrl_pt)
						var curve_len = start_pt.distance_to(ctrl_pt) + ctrl_pt.distance_to(end_pt)
						var steps = max(smooth_interation, int(curve_len / 6.0))
						var curve_points = _subdivide_quadratic_bezier(start_pt, ctrl_pt, end_pt, steps)
						for p in curve_points:
							poly.append(p)
				else:
					var line_len = start_pt.distance_to(end_pt)
					var steps = max(smooth_interation, int(line_len / 6))
					for s in range(1, steps + 1):
						poly.append(start_pt.lerp(end_pt, s / float(steps)))
				lines.append(line_data)
				last_end = end_pt
			poly = _simplify_collinear(poly, 0.01)
			if poly.size() >= 3:
				polygons.append(poly)
			for poly_idx in range(polygons.size()):
				all_polygons_in_shape.append(polygons[poly_idx])
				polygon_source_info.append({"sp_index": sp_idx, "poly_index": poly_idx})
			var final_polygons := []
			for i in range(polygons.size()):
				var base_poly = _ensure_ccw(polygons[i])
				for j in range(polygons.size()):
					if i == j:
						continue
					var inner_poly = _ensure_cw(polygons[j])
					var inside_count = 0
					for p in inner_poly:
						if Geometry2D.is_point_in_polygon(p, base_poly):
							inside_count += 1
					if inside_count > inner_poly.size() * 0.5:
						var result = Geometry2D.exclude_polygons(base_poly, inner_poly)
						if result.size() > 0:
							base_poly = result[0]
				final_polygons.append(base_poly)
			var tri_points := PackedVector2Array()
			var tri_indices := PackedInt32Array()
			var index_offset := 0
			for fpoly in final_polygons:
				if fpoly.size() < 3:
					continue
				var local_points = PackedVector2Array(fpoly)
				var local_indices = _triangulate_polygon(fpoly, use_fallback)
				for p in local_points:
					tri_points.append(p)
				for idx in local_indices:
					tri_indices.append(idx + index_offset)
				index_offset += local_points.size()

			sp["polygons"] = final_polygons
			sp["triangles"] = {"points": tri_points, "indices": tri_indices}
			sp["lines"] = lines
		if min_pt.x != INF:
			offset = min_pt
			size = max_pt - min_pt
		if hollow_pieces:
			_detect_global_overlaps(all_polygons_in_shape, polygon_source_info)
			subtract_overlapping_geometry()

	func close_loop(poly: PackedVector2Array) -> PackedVector2Array:
		if poly.size() < 3:
			return poly
		if poly[0] != poly[poly.size() - 1]:
			var closed = poly.duplicate()
			closed.append(poly[0])
			return closed
		return poly

	func subtract_overlapping_geometry():
		if subpaths.is_empty():
			return
		var indices_to_remove = []
		var i = 0
		while i < subpaths.size():
			if indices_to_remove.has(i):
				i += 1
				continue
			var sp_a = subpaths[i]
			var polys_a = sp_a["polygons"]
			if polys_a.is_empty():
				i += 1
				continue
			var j = i + 1
			while j < subpaths.size():
				if indices_to_remove.has(j):
					j += 1
					continue
				var sp_b = subpaths[j]
				var polys_b = sp_b["polygons"]
				if polys_b.is_empty():
					j += 1
					continue
				var poly_a = polys_a[0]
				var poly_b = polys_b[0]
				var min_a = poly_a[0]; var max_a = poly_a[0]
				for p in poly_a: min_a = min_a.min(p); max_a = max_a.max(p)
				var min_b = poly_b[0]; var max_b = poly_b[0]
				for p in poly_b: min_b = min_b.min(p); max_b = max_b.max(p)
				if max_a.x < min_b.x or min_a.x > max_b.x or max_a.y < min_b.y or min_a.y > max_b.y:
					j += 1
					continue
				var inside_count = 0
				for p in poly_b:
					if Geometry2D.is_point_in_polygon(p, poly_a):
						inside_count += 1
				var inside_ratio = float(inside_count) / float(poly_b.size())
				if inside_ratio < 0.9:
					j += 1
					continue
				var donut_polys = Geometry2D.exclude_polygons(poly_a, poly_b)
				if donut_polys.size() == 0:
					indices_to_remove.append(i)
					break
				var final_loops = []
				var outer = donut_polys[0]
				if outer.size() >= 3:
					outer = _simplify_collinear(outer, 0.001)
					outer = _ensure_ccw(outer)
					outer = close_loop(outer)
					final_loops.append(outer)
				for k in range(1, donut_polys.size()):
					var hole = donut_polys[k]
					if hole.size() >= 3:
						hole = _simplify_collinear(hole, 0.001)
						hole = _ensure_cw(hole)
						hole = close_loop(hole)
						final_loops.append(hole)
				if final_loops.size() > 0:
					sp_a["polygons"] = final_loops
					sp_a["lines"] = []
					var combined_poly_points = PackedVector2Array()
					for loop in final_loops:
						combined_poly_points.append_array(loop)
						if loop[0] != loop[loop.size() - 1]:
							combined_poly_points.append(loop[0])
					var local_indices = _triangulate_polygon(combined_poly_points, true)
					if local_indices.size() == 0:
						sp_a["polygons"] = [final_loops[0]]
						combined_poly_points = final_loops[0]
						local_indices = _triangulate_polygon(combined_poly_points, true)
					sp_a["triangles"] = {"points": combined_poly_points, "indices": local_indices}
					indices_to_remove.append(j)
				j += 1
			i += 1

		indices_to_remove.sort()
		indices_to_remove.reverse()
		for idx in indices_to_remove:
			if idx < subpaths.size():
				subpaths.remove_at(idx)

	func _detect_global_overlaps(all_polys: Array, source_info: Array):
		for i in range(all_polys.size()):
			for j in range(i + 1, all_polys.size()):
				var p1 = all_polys[i]
				var p2 = all_polys[j]
				var p1_min = p1[0]; var p1_max = p1[0]
				for p in p1: p1_min = p1_min.min(p); p1_max = p1_max.max(p)
				var p2_min = p2[0]; var p2_max = p2[0]
				for p in p2: p2_min = p2_min.min(p); p2_max = p2_max.max(p)
				if p1_max.x < p2_min.x or p1_min.x > p2_max.x or p1_max.y < p2_min.y or p1_min.y > p2_max.y:
					continue

				if Geometry2D.intersect_polygons(p1, p2).size() > 0:
					var _info1 = source_info[i]
					var _info2 = source_info[j]

	func _sanitize_vector(v: Vector2) -> Vector2:
		if !is_finite(v.x) or !is_finite(v.y):
			return Vector2.ZERO
		return v

	func _generate_svg():
		if subpaths.is_empty():
			svg_text = ""
			return

		var width = size.x
		var height = size.y

		if !is_finite(width) or width <= 0: width = 1.0
		if !is_finite(height) or height <= 0: height = 1.0

		var sb := []
		sb.append('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
		sb.append('<svg width="%f" height="%f" viewBox="0 0 %f %f" xmlns="http://www.w3.org/2000/svg">' % [width, height, width, height])

		var has_content = false

		for sp in subpaths:
			if not sp.has("polygons") or sp["polygons"].is_empty():
				continue

			var d := ""
			for poly in sp["polygons"]:
				if poly.size() < 3:
					continue

				# bake offset into polygon points
				var start_pt = _sanitize_vector(poly[0]) - offset
				d += "M %f %f " % [start_pt.x, start_pt.y]

				for k in range(1, poly.size()):
					var pt = _sanitize_vector(poly[k]) - offset
					d += "L %f %f " % [pt.x, pt.y]

				d += "Z "

			if d.length() > 0:
				var color_hex = sp["color"].to_html(false)
				var alpha = sp["color"].a
				sb.append('<path d="%s" fill="#%s" fill-opacity="%f" fill-rule="evenodd" stroke="none"/>' % [d, color_hex, alpha])
				has_content = true

		sb.append("</svg>")

		if has_content:
			svg_text = "".join(sb)
		else:
			svg_text = '<svg width="1" height="1" viewBox="0 0 1 1" xmlns="http://www.w3.org/2000/svg"></svg>'

	func to_svg() -> String:
		return svg_text

	func _ensure_ccw(poly: PackedVector2Array) -> PackedVector2Array:
		if _compute_signed_area(poly) < 0:
			poly.reverse()
		return poly

	func _ensure_cw(poly: PackedVector2Array) -> PackedVector2Array:
		if _compute_signed_area(poly) > 0:
			poly.reverse()
		return poly

	func _simplify_collinear(poly: PackedVector2Array, angle_eps: float = 0.01) -> PackedVector2Array:
		if poly.size() < 3:
			return poly
		var new_poly = PackedVector2Array()
		new_poly.append(poly[0])
		for i in range(1, poly.size() - 1):
			var a = poly[i - 1]
			var b = poly[i]
			var c = poly[i + 1]
			if abs((b - a).angle_to(c - b)) > angle_eps:
				new_poly.append(b)
		new_poly.append(poly[poly.size() - 1])
		return new_poly

	func _compute_signed_area(poly: PackedVector2Array) -> float:
		var area = 0.0
		for i in range(poly.size()):
			var p1 = poly[i]
			var p2 = poly[(i + 1) % poly.size()]
			area += (p1.x * p2.y - p2.x * p1.y)
		return area * 0.5

	func _triangulate_polygon(poly: PackedVector2Array, use_fallback : bool = false) -> PackedInt32Array:
		if poly.size() < 3:
			return PackedInt32Array()
		var tri := Geometry2D.triangulate_polygon(poly)
		var triangles := PackedInt32Array(tri)
		
		if triangles.size() == 0 && use_fallback:
			var delaunay_tri := Geometry2D.triangulate_delaunay(poly)
			return delaunay_tri

		return triangles

	func _subdivide_quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, steps: int) -> Array:
		var points := []
		for i in range(1, steps+1):
			var t = i/float(steps)
			var mt = 1 - t
			var pos = mt*mt*p0 + 2*mt*t*p1 + t*t*p2
			points.append(pos)
		return points

	func get_local_center() -> Vector2:
		if size == Vector2.ZERO:
			return Vector2.ZERO
		return offset + size * 0.5



class SWFSprite:
	var children : Array = []
	var frames : Array = []
	var frame_names : Array = []
	var animations : Dictionary = {}
	var local_x : float = 0.0
	var local_y : float = 0.0
	var max_nesting_depth : int = 0

	func _init(data : Dictionary):
		for c in data.get("Children", []):
			children.append(SWFChild.new(c))
		local_x = data.get("LocalX", 0)
		local_y = data.get("LocalY", 0)
		max_nesting_depth =  data.get("MaxNestingDepth", 0)
		for idx in range(data.get("Frames", []).size()):
			var f = data["Frames"][idx]
			var frame_dict = {}
			for key in f.keys():
				frame_dict[int(key)] = SWFFrame.new(f[key])
			frames.append(frame_dict)

		if data.has("FrameNames"):
			frame_names = data["FrameNames"]

		_build_animations()

	func _build_animations():
		animations.clear()
		var current_anim = ""
		var current_frames := []
		
		for i in range(frames.size()):
			var name : String = ""
			if i < frame_names.size() and frame_names[i] != null:
				name = str(frame_names[i])

			if name != "":
				if current_frames.size() > 0 and current_anim != "":
					animations[current_anim] = current_frames.duplicate()
				current_anim = name
				current_frames = [i]
			else:
				current_frames.append(i)

		# Add last animation
		if current_frames.size() > 0 and current_anim != "":
			animations[current_anim] = current_frames.duplicate()
