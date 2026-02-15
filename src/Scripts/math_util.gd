extends Node
class_name MathUtil


static func is_convex(poly: PackedVector2Array, a: int, b: int, c: int) -> bool:
	return ((poly[b] - poly[a]).cross(poly[c] - poly[b])) > 0

static func point_in_triangle(poly: PackedVector2Array, p: int, a: int, b: int, c: int) -> bool:
	var v0 = poly[c] - poly[a]
	var v1 = poly[b] - poly[a]
	var v2 = poly[p] - poly[a]
	var dot00 = v0.dot(v0)
	var dot01 = v0.dot(v1)
	var dot02 = v0.dot(v2)
	var dot11 = v1.dot(v1)
	var dot12 = v1.dot(v2)
	var invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01)
	var u = (dot11 * dot02 - dot01 * dot12) * invDenom
	var v = (dot00 * dot12 - dot01 * dot02) * invDenom
	return (u >= 0) and (v >= 0) and (u + v <= 1)

static func subdivide_quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, steps: int) -> Array:
	var points := []
	for i in range(1, steps+1):
		var t = i/float(steps)
		var mt = 1 - t
		var pos = mt*mt*p0 + 2*mt*t*p1 + t*t*p2
		points.append(pos)
	return points

static func get_local_center(size : Vector2 = Vector2.ZERO, offset : Vector2 = Vector2.ZERO) -> Vector2:
	if size == Vector2.ZERO: return Vector2.ZERO
	return offset + size * 0.5

static func sanitize_vector(v: Vector2) -> Vector2:
	if !is_finite(v.x) or !is_finite(v.y): return Vector2.ZERO
	return v

static func close_loop(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	if poly[0] != poly[poly.size() - 1]:
		var closed = poly.duplicate()
		closed.append(poly[0])
		return closed
	return poly

static func ensure_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if compute_signed_area(poly) < 0:
		poly.reverse()
	return poly

static func ensure_cw(poly: PackedVector2Array) -> PackedVector2Array:
	if compute_signed_area(poly) > 0:
		poly.reverse()
	return poly

static func simplify_collinear(poly: PackedVector2Array, angle_eps: float = 0.01) -> PackedVector2Array:
	if poly.size() < 3: return poly
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

static func compute_signed_area(poly: PackedVector2Array) -> float:
	var area = 0.0
	for i in range(poly.size()):
		var p1 = poly[i]
		var p2 = poly[(i + 1) % poly.size()]
		area += (p1.x * p2.y - p2.x * p1.y)
	return area * 0.5

static func detect_global_overlaps(all_polys: Array, source_info: Array):
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

static func remove_duplicate_points(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() < 2:
		return poly
	var clean = PackedVector2Array()
	clean.append(poly[0])
	for i in range(1, poly.size()):
		if poly[i] != poly[i-1]:
			clean.append(poly[i])
	if clean[0] == clean[clean.size()-1] and clean.size() > 1:
		clean.remove_at(clean.size()-1)
	return clean

static func is_polygon_inside(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	if inner.size() < 3 or outer.size() < 3:
		return false
	var cx := 0.0
	var cy := 0.0
	var a := 0.0
	for i in range(inner.size()):
		var p0 = inner[i]
		var p1 = inner[(i + 1) % inner.size()]
		var cross = p0.x * p1.y - p1.x * p0.y
		a += cross
		cx += (p0.x + p1.x) * cross
		cy += (p0.y + p1.y) * cross
	if abs(a) < 0.00001: return false
	a *= 0.5
	cx /= (6.0 * a)
	cy /= (6.0 * a)
	return Geometry2D.is_point_in_polygon(Vector2(cx, cy) + Vector2(0.001, 0.001), outer)
