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
	var alpha : float = 1.0
	var color: Color = Color(1, 1, 1, 1) 
	var lumi : float = 1.0

	func _init(data : Dictionary):
		symbol_id = data.get("SymbolID", 0)
		depth = data.get("Depth", 0)
		x = data.get("X", 0.0)
		y = data.get("Y", 0.0)
		scale_x = data.get("ScaleX", 1.0)
		scale_y = data.get("ScaleY", 1.0)
		alpha = data.get("Alpha", 1.0)
		rotation = data.get("Rotation", 0.0)
		lumi = data.get("Lumi", 1.0)
		local_x = data.get("LocalX", 0)
		local_y = data.get("LocalY", 0)
		visible = data.get("Visible", true)
		is_dirty = true
		var test = data.get("EffectiveColor",  Color(1, 1, 1, 1) )
		#print(test)
		color = test
		
		if data.has("TransformMatrix"):
			transform_matrix = data["TransformMatrix"]

class SWFShape:
	var backup_subpaths: Array = []
	var subpaths: Array = []
	var stroke_paths: Array = []
	var offset: Vector2 = Vector2.ZERO
	var size: Vector2 = Vector2.ZERO
	var svg_text: String = ""
	var is_gradient : bool = false
	var texture : ImageTexture = null
	var raster_texture : ImageTexture = null
	var curve_subdivisions := 5

	func _init(data: Dictionary):
		if data.has("SubPaths"):
			for sp in data["SubPaths"]:
				var segments = sp.get("Segments", [])
				if segments.is_empty(): continue
				var c = sp.get("FillColor", {"R":255,"G":255,"B":255,"A":255})
				var color = Color(c["R"]/255.0, c["G"]/255.0, c["B"]/255.0, c["A"]/255.0)
				var subpath_data = {
					"segments": segments,
					"lines": [],
					"polygons": [],
					"triangles": {},
					"color": color,
					"gradient": null
				}
				if sp.has("Gradient"):
					if sp["Gradient"] != null:
						var grad_info = sp["Gradient"]
						var stops = []
						for stop in grad_info.get("Stops", []):
							var sc = stop.get("Color", {"R":1,"G":1,"B":1,"A":1})
							
							stops.append({
								"offset": stop.get("Offset", 0.0),
								"color": Color(sc["R"], sc["G"], sc["B"], sc["A"])
							})
						subpath_data["gradient"] = {
							"x1": grad_info.get("X1", 0),
							"y1": grad_info.get("Y1", 0),
							"x2": grad_info.get("X2", 0),
							"y2": grad_info.get("Y2", 0),
							"stops": stops
						}
						is_gradient = true
						
				subpaths.append(subpath_data)
				backup_subpaths.append(subpath_data.duplicate(true))

		if data.has("Strokes"):
			for st in data["Strokes"]:
				var segments = st.get("Segments", [])
				if segments.is_empty(): continue
				var c = st.get("StrokeColor", {"R":0,"G":0,"B":0,"A":255})
				var color = Color(c["R"]/255.0, c["G"]/255.0, c["B"]/255.0, c["A"]/255.0)
				stroke_paths.append({
					"segments": segments,
					"lines": [],
					"color": color,
					"width": st.get("Width", 1.0)
				})

	# I think this is one of the most complex json get data i ever made lmao
	func get_data() -> Dictionary:
		var dat : Dictionary = {
			"Subpaths" : [],
			"Offset" : { "x" : offset.x, "y" : offset.y},
			"Size" : { "x" : size.x, "y" : size.y},
			"Svg_text" : svg_text,
		}
		
		for i in subpaths:
			var dt : Dictionary = {
				"Segments": i["segments"],
				"Lines": [],
				"Polygons": [],
				"Triangles": {"Points": [], "Indices": []},
				"Color": {"R": 1.0, "G": 1.0, "B": 1.0, "A" : 1.0}
			}
			
			for l in i["lines"]:
				dt["Lines"].append({
					
					"Type": l["type"],
					"Start": { "x" : l["start"].x, "y" : l["start"].y},
					"End": { "x" : l["end"].x, "y" : l["end"].y},
					"Control":  { "x" : l["control"].x, "y" : l["control"].y}
					
				})
				
			for ply in i["polygons"]:
				var poly : Array = []
				for pl in ply:
					poly.append({ "x" : pl.x, "y" : pl.y})
				
				dt["Polygons"].append(poly)
			
			for p in i["triangles"]["points"]:
				dt["Triangles"]["Points"].append({ "x" : p.x, "y" : p.y})
			
			for p in i["triangles"]["indices"]:
				dt["Triangles"]["Indices"].append(p)
			
			dat["Subpaths"].append(dt)

		return dat

	func build_geometry(smooth_interation: int = 20, hollow_pieces: bool = false):
		subpaths = backup_subpaths.duplicate(true)
		var min_pt = Vector2(INF, INF)
		var max_pt = Vector2(-INF, -INF)
		var all_polygons := []
		var polygon_source_info := []

		for sp_idx in range(subpaths.size()):
			var sp = subpaths[sp_idx]
			var lines := []
			var polygons := []
			var poly := PackedVector2Array()
			var last_point = null

			for seg in sp["segments"]:
				if not seg.has("Start") or not seg.has("End") or not seg.has("Type"): continue
				var start_pt = Vector2(seg["Start"].get("X", 0), seg["Start"].get("Y", 0))
				var end_pt = Vector2(seg["End"].get("X", 0), seg["End"].get("Y", 0))
				
				if last_point and start_pt.distance_squared_to(last_point) > 0.01*0.01:
					poly = MathUtil.simplify_collinear(poly, 0.01)
					if poly.size() >= 3: polygons.append(poly)
					poly = PackedVector2Array()
				if poly.is_empty(): poly.append(start_pt)

				min_pt = min_pt.min(start_pt).min(end_pt)
				max_pt = max_pt.max(start_pt).max(end_pt)

				var line_data = {"type": seg["Type"], "start": start_pt, "end": end_pt, "control": Vector2.ZERO}
				if seg["Type"] == "curve" and seg.has("Control"):
					var ctrl = seg["Control"]
					if typeof(ctrl) == TYPE_DICTIONARY:
						var ctrl_pt = Vector2(ctrl.get("X",0), ctrl.get("Y",0))
						line_data["control"] = ctrl_pt
						min_pt = min_pt.min(ctrl_pt)
						max_pt = max_pt.max(ctrl_pt)
						var steps: int = int(max(smooth_interation, start_pt.distance_to(ctrl_pt)+ctrl_pt.distance_to(end_pt)/4))
						for p in MathUtil.subdivide_quadratic_bezier(start_pt, ctrl_pt, end_pt, steps):
							poly.append(p)
				else:
					var steps = max(smooth_interation, int(start_pt.distance_to(end_pt)/4))
					for s in range(1, steps+1):
						poly.append(start_pt.lerp(end_pt, s/float(steps)))

				lines.append(line_data)
				last_point = poly[poly.size()-1]

			poly = MathUtil.simplify_collinear(poly, 0.01)
			if poly.size() >= 3: polygons.append(poly)

			var normalized := []
			for p in polygons:
				if p.size() < 3: continue
				if MathUtil.compute_signed_area(p) > 0:
					normalized.append(MathUtil.ensure_ccw(p))
				else:
					normalized.append(MathUtil.ensure_cw(p))

			var classified = classify_polygons_with_holes(normalized)

			var tri_points := PackedVector2Array()
			var tri_indices := PackedInt32Array()
			var final_polygons_list := []

			for entry in classified:
				var outer = entry["outer"]
				var holes = entry["holes"]
				final_polygons_list.append(outer)
				final_polygons_list.append_array(holes)
				var bridged_poly = create_bridged_polygon(outer, holes)
				var local_indices = triangulate_polygon(outer, holes)
				var offset_idx = tri_points.size()
				tri_points.append_array(bridged_poly)
				for idx in local_indices:
					tri_indices.append(idx + offset_idx)

			sp["polygons"] = final_polygons_list 
			sp["triangles"] = {"points": tri_points, "indices": tri_indices}

			sp["lines"] = lines

			for poly_idx in range(final_polygons_list.size()):
				all_polygons.append(final_polygons_list[poly_idx])
				polygon_source_info.append({"sp_index": sp_idx, "poly_index": poly_idx})
		for sp in stroke_paths:
			var lines := []
			for seg in sp["segments"]:
				if not seg.has("Start") or not seg.has("End") or not seg.has("Type"): continue
				var s = Vector2(seg["Start"]["X"], seg["Start"]["Y"])
				var e = Vector2(seg["End"]["X"], seg["End"]["Y"])
				var c = seg.get("Control", {"X":0,"Y":0})
				lines.append({"type": seg["Type"], "start": s, "end": e, "control": Vector2(c["X"],c["Y"]) if seg["Type"]=="curve" else Vector2.ZERO})
				min_pt = min_pt.min(s).min(e)
				max_pt = max_pt.max(s).max(e)
			sp["lines"] = lines

		if min_pt.x != INF:
			offset = min_pt
			size = max_pt - min_pt

		if hollow_pieces and all_polygons.size() > 0:
			MathUtil.detect_global_overlaps(all_polygons, polygon_source_info)
			subtract_overlapping_geometry()

		generate_svg()

	func create_bridged_polygon(outer: PackedVector2Array, holes: Array) -> PackedVector2Array:
		outer = MathUtil.ensure_ccw(outer)
		var result = outer.duplicate()
		for hole in holes:
			if hole.size() < 3:
				continue
			hole = MathUtil.ensure_cw(hole)

			var min_dist = INF
			var outer_idx = 0
			var hole_idx = 0
			for o in range(result.size()):
				for h in range(hole.size()):
					var d = result[o].distance_squared_to(hole[h])
					if d < min_dist:
						min_dist = d
						outer_idx = o
						hole_idx = h

			var new_poly = PackedVector2Array()
			for i in range(result.size()):
				new_poly.append(result[(outer_idx + i) % result.size()])
			for i in range(hole.size()):
				new_poly.append(hole[(hole_idx + i) % hole.size()])
			new_poly.append(result[outer_idx])
			new_poly = MathUtil.remove_duplicate_points(new_poly)
			result = MathUtil.close_loop(new_poly)
		return result

	func triangulate_polygon(outer: PackedVector2Array, holes: Array) -> PackedInt32Array:
		var bridged_poly = create_bridged_polygon(outer, holes)
		return fallback_triangulate(bridged_poly)

	func classify_polygons_with_holes(polygons: Array) -> Array:
		var outers : Array = []
		var holes : Array = []
		for poly in polygons:
			if poly.size() < 3: continue
			if MathUtil.compute_signed_area(poly) > 0:
				outers.append(MathUtil.ensure_ccw(poly))
			else:
				holes.append(MathUtil.ensure_cw(poly))
		var result := []
		for outer in outers:
			result.append({"outer": outer, "holes": []})
		for hole in holes:
			var best_outer = -1
			var smallest_area_diff = INF
			var hole_area = abs(MathUtil.compute_signed_area(hole))
			for i in range(result.size()):
				var outer = result[i]["outer"]
				if MathUtil.is_polygon_inside(hole, outer):
					var outer_area = abs(MathUtil.compute_signed_area(outer))
					var area_diff = outer_area - hole_area
					if area_diff > 0 and area_diff < smallest_area_diff:
						smallest_area_diff = area_diff
						best_outer = i
			if best_outer != -1:
				result[best_outer]["holes"].append(hole)
			else:
				result.append({"outer": hole.duplicate(), "holes": []})

		return result

	func subtract_overlapping_geometry():
		if subpaths.is_empty(): return
		
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
			var poly_a = polys_a[0] 
			if poly_a.size() < 3:
				i += 1
				continue

			var j = i + 1
			while j < subpaths.size():
				if indices_to_remove.has(j):
					j += 1
					continue
					
				var sp_b = subpaths[j]
				if sp_a["color"] != sp_b["color"]:
					j += 1
					continue

				var polys_b = sp_b["polygons"]
				if polys_b.is_empty():
					j += 1
					continue
					
				var poly_b = polys_b[0]

				var min_a = poly_a[0]; var max_a = poly_a[0]
				for p in poly_a: min_a = min_a.min(p); max_a = max_a.max(p)
				var min_b = poly_b[0]; var max_b = poly_b[0]
				for p in poly_b: min_b = min_b.min(p); max_b = max_b.max(p)
				
				if max_a.x < min_b.x or min_a.x > max_b.x or max_a.y < min_b.y or min_a.y > max_b.y:
					j += 1
					continue

				var center_b = Vector2.ZERO
				for p in poly_b: center_b += p
				center_b /= poly_b.size()
				
				if Geometry2D.is_point_in_polygon(center_b, poly_a):
					var donut_polys = Geometry2D.exclude_polygons(poly_a, poly_b)
					
					if donut_polys.size() == 0:
						indices_to_remove.append(i)
						break
					donut_polys.sort_custom(func(a, b): return abs(MathUtil.compute_signed_area(a)) > abs(MathUtil.compute_signed_area(b)))
					var new_outer = donut_polys[0]
					var new_holes = []
					if donut_polys.size() > 1:
						for k in range(1, donut_polys.size()):
							new_holes.append(donut_polys[k])
					sp_a["polygons"] = [new_outer] + new_holes
					sp_a["lines"] = []
					var bridged = create_bridged_polygon(new_outer, new_holes)
					var indices = triangulate_polygon(new_outer, new_holes)
					sp_a["triangles"] = {"points": bridged, "indices": indices}
					poly_a = new_outer 
					indices_to_remove.append(j)
				else:
					j += 1
			i += 1
		indices_to_remove.sort()
		indices_to_remove.reverse()
		for idx in indices_to_remove:
			if idx < subpaths.size():
				subpaths.remove_at(idx)

	func fallback_triangulate(poly: PackedVector2Array) -> PackedInt32Array:
		var n := poly.size()
		if n < 3:
			return PackedInt32Array()

		var indices := []
		for i in range(n):
			indices.append(i)

		var triangles := PackedInt32Array()
		var safe_counter := 0

		while indices.size() > 3 and safe_counter < 5000:
			safe_counter += 1
			var found := false

			for i in range(indices.size()):
				var prev_idx = indices[(i - 1 + indices.size()) % indices.size()]
				var curr_idx = indices[i]
				var next_idx = indices[(i + 1) % indices.size()]

				if !MathUtil.is_convex(poly, prev_idx, curr_idx, next_idx):
					continue

				var has_inside := false
				for j in indices:
					if j in [prev_idx, curr_idx, next_idx]:
						continue
					if MathUtil.point_in_triangle(poly, j, prev_idx, curr_idx, next_idx):
						has_inside = true
						break

				var area = ((poly[prev_idx] - poly[curr_idx]).cross(poly[next_idx] - poly[curr_idx])) * 0.5
				if abs(area) < 1e-6:
					continue

				if !has_inside:
					triangles.append(prev_idx)
					triangles.append(curr_idx)
					triangles.append(next_idx)
					indices.remove_at(i)
					found = true
					break

			# fallback: if no ear found, make fan from first vertex
			if !found:
				for i in range(1, indices.size() - 1):
					triangles.append(indices[0])
					triangles.append(indices[i])
					triangles.append(indices[i + 1])
				break

		if indices.size() == 3:
			triangles.append(indices[0])
			triangles.append(indices[1])
			triangles.append(indices[2])

		return triangles

	func get_shape_bounds(polygons):
		var min_x = INF
		var min_y = INF
		var max_x = -INF
		var max_y = -INF

		for poly in polygons:
			for pt in poly:
				var p = MathUtil.sanitize_vector(pt) - offset
				min_x = min(min_x, p.x)
				min_y = min(min_y, p.y)
				max_x = max(max_x, p.x)
				max_y = max(max_y, p.y)

		return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

	func generate_svg():
		if subpaths.is_empty():
			svg_text = ""
			return

		var width = size.x
		var height = size.y
		if !is_finite(width) or width <= 0: width = 1.0
		if !is_finite(height) or height <= 0: height = 1.0

		var sb := []
		var defs := []
		sb.append('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
		sb.append('<svg width="%f" height="%f" viewBox="0 0 %f %f" xmlns="http://www.w3.org/2000/svg">' % [width, height, width, height])

		var has_content = false
		var gradient_counter = 0

		for sp in subpaths:
			if not sp.has("polygons") or sp["polygons"].is_empty():
				continue

			var d := ""
			for poly in sp["polygons"]:
				if poly.size() < 3: continue

				var start_pt = MathUtil.sanitize_vector(poly[0]) - offset
				d += "M %f %f " % [start_pt.x, start_pt.y]

				for k in range(1, poly.size()):
					var pt = MathUtil.sanitize_vector(poly[k]) - offset
					d += "L %f %f " % [pt.x, pt.y]

				d += "Z "

			if d.length() > 0:
				var fill_attr = ""
				var alpha = sp["color"].a
				var style_attr = ""

				if sp.has("gradient") and sp["gradient"] != null and sp["gradient"]["stops"].size() > 0:
					if !sp.has("gradient_id"):
						sp["gradient_id"] = gradient_counter
						gradient_counter += 1
					var grad_id = "grad%d" % sp["gradient_id"]
					fill_attr = "url(#%s)" % grad_id
					alpha = 1.0
					style_attr = "style='fill:url(#%s);fill-opacity:%f'" % [grad_id, alpha]

					var g = sp["gradient"]
					var bounds = get_shape_bounds(sp["polygons"])
					var bb_center = bounds.position + bounds.size * 0.5

					var x1 = g.x1 + bb_center.x
					var y1 = g.y1 + bb_center.y
					var x2 = g.x2 + bb_center.x
					var y2 = g.y2 + bb_center.y

					defs.append('<linearGradient id="%s" x1="%f" y1="%f" x2="%f" y2="%f" gradientUnits="userSpaceOnUse">' % [grad_id, x1, y1, x2, y2])

					for stop in g["stops"]:
						var c = stop["color"]
						var stop_hex = "#" + c.to_html(false)

						defs.append('<stop offset="%f" stop-color="%s" stop-opacity="%f"/>' % [stop["offset"], stop_hex, c.a])



					
					defs.append('</linearGradient>')
				else:
					fill_attr = "#%s" % sp["color"].to_html(false)
					style_attr = ""

				sb.append('<path d="%s" fill="%s" fill-opacity="%f" fill-rule="evenodd" stroke="none" %s/>' % [d, fill_attr, alpha, style_attr])
				has_content = true

		for sp in stroke_paths:
			if not sp.has("lines") or sp["lines"].is_empty():
				continue
			
			var d := ""
			var first := true
			
			for l in sp["lines"]:
				var s = MathUtil.sanitize_vector(l["start"]) - offset
				var e = MathUtil.sanitize_vector(l["end"]) - offset
				
				if first:
					d += "M %f %f " % [s.x, s.y]
					first = false
					
				if l["type"] == "curve":
					var c = MathUtil.sanitize_vector(l["control"]) - offset
					d += "Q %f %f %f %f " % [c.x, c.y, e.x, e.y]
				else:
					d += "L %f %f " % [e.x, e.y]
					
			if d.length() > 0:
				sb.append(
					'<path d="%s" fill="none" stroke="#%s" stroke-opacity="%f" stroke-width="%f" stroke-linecap="round" stroke-linejoin="round"/>' %
					[
						d,
						sp["color"].to_html(false),
						sp["color"].a,
						sp["width"]
					]
				)

		if defs.size() > 0:
			sb.append("<defs>%s</defs>" % "".join(defs))

		sb.append("</svg>")

		if has_content:
			svg_text = "".join(sb)
		else:
			svg_text = '<svg width="1" height="1" viewBox="0 0 1 1" xmlns="http://www.w3.org/2000/svg"></svg>'

		if is_gradient:
			var img : Image = Image.new()
			img.load_svg_from_string(to_svg())
			if img.is_empty():
				return
			raster_texture = ImageTexture.create_from_image(img)

	func to_svg() -> String:
		return svg_text


class SWFSprite:
	var children : Array = []
	var frames : Array = []
	var frame_names : Array = []
	var animations : Dictionary = {}
	var local_x : float = 0.0
	var local_y : float = 0.0
	var max_nesting_depth : int = 0
	var children_referenced : Array = []
	var sprite_name : String = ""
	var full_sprite_name : String = ""

	func _init(data : Dictionary):
		for c in data.get("Children", []):
			children.append(SWFChild.new(c))
		local_x = data.get("LocalX", 0)
		local_y = data.get("LocalY", 0)
		sprite_name =  data.get("SpriteName", "")
		
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

	func get_data() -> Dictionary:
		var dat : Dictionary = {
			"SpriteName" : sprite_name,
			"MaxDepth" : max_nesting_depth,
			"Frames" : [],
			"Animations" : animations,
			"Children" : [],
		}
		for ch in children:
			dat["Children"].append({
				"ID" : ch.id,
				"Type" : ch.type
			})
		
		for frame in frames:
			var frame_data : Dictionary = {}
			for fd in frame.keys():
				var f = frame[fd]
				frame_data[fd] = {
					"SymbolID" : f.symbol_id,
					"X" : f.x,
					"Y" : f.y,
					"ScaleX" : f.scale_x,
					"ScaleY" : f.scale_y,
					
					"Rotation" : f.rotation,
					"TransformMatrix" : f.transform_matrix,
					"Visible" : f.visible,
					"Alpha" : f.alpha,
					
					"LocalX" : f.local_x,
					"LocalY" : f.local_y,
					
					"IsDirty" : f.is_dirty,
					"Color" : {"R": f.color.r, "G": f.color.g, "B": f.color.b, "A" : f.color.a}
					
				}
			dat["Frames"].append(frame_data)
		
		return dat
