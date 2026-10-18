class_name Facility
extends Node3D
## Builds the night-time compound: geometry, lighting, atmosphere, pickups and the navigation mesh.
## Level geometry lives under the navigation region so it can be baked at load time.

signal nav_ready

const MOON_DIR := Vector3(-0.45, 0.55, -0.7)

var nav_region: NavigationRegion3D
var lamps: Array[Lamp] = []
var pickups: Array[Pickup] = []
var devices: Array[Device] = []
var doors: Array[Door] = []
var searchlights: Array[SpotLight3D] = []
var ladders: Array[Ladder] = []
var drones: Array[Drone] = []
## Crawlspaces (axis-aligned boxes) where moving makes a racket on sheet metal.
var ducts: Array[AABB] = []
## Insertion and extraction: outside the west wall, through a breach in it.
var extraction := Vector3(-53.6, 0, -29.3)
var intel_pos := Vector3(46, 5.0, 28.2)
var player_start := Vector3(-54.2, 0, -26.5)
var player_start_yaw := -0.92
var _moon_dir := MOON_DIR.normalized()
var env: Environment
const EXPOSURE := 1.25


func build() -> void:
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	_environment()
	_layout()


# ------------------------------------------------------------------ primitives

func box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, mat: String, collide := true) -> void:
	var mn := Vector3(minf(x0, x1), y0, minf(z0, z1))
	var mx := Vector3(maxf(x0, x1), y1, maxf(z0, z1))
	var size := mx - mn
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Mats.get_mat(mat)
	if not collide:
		mi.position = (mn + mx) * 0.5
		add_child(mi)
		return
	var body := StaticBody3D.new()
	body.position = (mn + mx) * 0.5
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.add_child(mi)
	body.set_meta("mat", mat)
	body.set_meta("pen", Mats.PEN.get(mat, 0.0))
	body.set_meta("half", size * 0.5)
	nav_region.add_child(body)


## Invisible collision (keeps the player inside the compound).
func blocker(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(absf(x1 - x0), y1 - y0, absf(z1 - z0))
	cs.shape = sh
	body.add_child(cs)
	add_child(body)


## A sloped wedge (stairs). axis "x" or "z", dir +1 rises toward the max coordinate.
func ramp(x0: float, z0: float, x1: float, z1: float, base: float, top: float, axis: String, dir: int, mat: String, show := true) -> void:
	var p := func(t: float, w: int, y: float) -> Vector3:
		var lo := x0 if axis == "x" else z0
		var hi := x1 if axis == "x" else z1
		var along := lerpf(lo, hi, t) if dir > 0 else lerpf(hi, lo, t)
		if axis == "x":
			return Vector3(along, y, z1 if w else z0)
		return Vector3(x1 if w else x0, y, along)
	var pts: PackedVector3Array = [p.call(0, 0, base), p.call(0, 1, base), p.call(1, 0, base), p.call(1, 1, base), p.call(1, 0, top), p.call(1, 1, top)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := (pts[0] + pts[5]) * 0.5
	center.y = base + (top - base) * 0.3
	var quads := [[0, 1, 5, 4], [0, 2, 3, 1], [2, 4, 5, 3]]
	for q: Array in quads:
		_face(st, [pts[q[0]], pts[q[1]], pts[q[2]], pts[q[3]]], center)
	_face(st, [pts[0], pts[2], pts[4]], center)
	_face(st, [pts[1], pts[3], pts[5]], center)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Mats.get_mat(mat)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	body.add_child(cs)
	if show:
		body.add_child(mi)
	body.set_meta("mat", "steel")
	body.set_meta("pen", 0.0)
	nav_region.add_child(body)


## A visual-only box, optionally rotated (stair stringers, handrails, rungs).
func deco(center: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.rotation = rot
	add_child(mi)
	return mi


## Open steel stairs: a smooth invisible slope to walk and path on, with real treads, stringers
## and handrails on top of it. Same arguments as ramp().
func stairs(x0: float, z0: float, x1: float, z1: float, base: float, top: float, axis: String, dir: int, rails := true) -> void:
	ramp(x0, z0, x1, z1, base, top, axis, dir, "grating", false)
	var steel := Mats.plain(Color("5d6166"), 0.45, 0.6)
	var tread_mat := Mats.get_mat("grating")
	var run := (x1 - x0) if axis == "x" else (z1 - z0)
	var width := (z1 - z0) if axis == "x" else (x1 - x0)
	var rise := top - base
	var n := maxi(2, ceili(rise / 0.19))
	var step_run := run / n
	var along := (Vector3.RIGHT if axis == "x" else Vector3.BACK) * float(dir)
	var start := Vector3(x0 if (axis == "x") == (dir > 0) else x1, base, z0 if (axis != "x") == (dir > 0) else z1)
	if axis == "x":
		start.z = (z0 + z1) * 0.5
	else:
		start.x = (x0 + x1) * 0.5
	var across := Vector3.BACK if axis == "x" else Vector3.RIGHT
	for i in n:
		var c := start + along * step_run * (i + 0.5)
		c.y = base + rise * (i + 1) / n - 0.03
		var size := Vector3(step_run, 0.05, width) if axis == "x" else Vector3(width, 0.05, step_run)
		deco(c, size, tread_mat)
	var slope := atan2(rise, run)
	var length := sqrt(rise * rise + run * run)
	var mid := start + along * run * 0.5 + Vector3.UP * rise * 0.5
	# stringers and rails tilt about the horizontal axis across the flight
	var basis_rot := Basis(across, slope * (1.0 if dir > 0 else -1.0) * (-1.0 if axis == "x" else 1.0))
	for side: float in [-0.5, 0.5]:
		var off := across * width * side
		var str_mi := deco(mid + off - Vector3.UP * 0.08, Vector3(length, 0.22, 0.05) if axis == "x" else Vector3(0.05, 0.22, length), steel)
		str_mi.basis = basis_rot * str_mi.basis
		if rails:
			var rail := deco(mid + off + Vector3.UP * 0.92, Vector3(length, 0.04, 0.04) if axis == "x" else Vector3(0.04, 0.04, length), steel)
			rail.basis = basis_rot * rail.basis
			for k in 3:
				var t := (k + 0.5) / 3.0
				var pc := start + along * run * t + off + Vector3.UP * (rise * t + 0.46)
				deco(pc, Vector3(0.04, 0.92, 0.04), steel)


## A catwalk: grating deck at a height with handrails along the given open sides.
func catwalk(x0: float, z0: float, x1: float, z1: float, y: float, rail_sides: Array, gaps := []) -> void:
	box(x0, y - 0.1, z0, x1, y, z1, "grating")
	var steel := Mats.plain(Color("5d6166"), 0.45, 0.6)
	for side: String in rail_sides:
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		match side:
			"n": a = Vector3(x0, y, z0); b = Vector3(x1, y, z0)
			"s": a = Vector3(x0, y, z1); b = Vector3(x1, y, z1)
			"w": a = Vector3(x0, y, z0); b = Vector3(x0, y, z1)
			"e": a = Vector3(x1, y, z0); b = Vector3(x1, y, z1)
		_rail(a, b, steel, gaps)
	# hangers up to the roof trusses
	var lx := absf(x1 - x0)
	var lz := absf(z1 - z0)
	var count := int(maxf(lx, lz) / 4.0)
	for i in count + 1:
		var t := float(i) / maxf(1.0, count)
		var p := Vector3(lerpf(x0, x1, t) if lx > lz else x0 + 0.1, y, lerpf(z0, z1, t) if lz >= lx else z0 + 0.1)
		deco(p + Vector3.UP * (9.0 - y) * 0.5, Vector3(0.03, 9.0 - y, 0.03), steel)


func _rail(a: Vector3, b: Vector3, mat: Material, gaps: Array) -> void:
	var d := b - a
	var length := d.length()
	_rail_body(a, b, gaps)
	var n := int(length / 1.5) + 1
	for k in range(n + 1):
		var p := a + d * (float(k) / n)
		if gaps.any(func(g: Vector3) -> bool: return Vector2(g.x - p.x, g.z - p.z).length() < 0.7):
			continue
		deco(p + Vector3.UP * 0.5, Vector3(0.04, 1.0, 0.04), mat)
	for h: float in [0.5, 1.0]:
		var segs := [[0.0, 1.0]]
		for g: Vector3 in gaps:
			var t := clampf((g - a).dot(d) / (length * length), 0.0, 1.0)
			if (a + d * t).distance_to(Vector3(g.x, a.y, g.z)) > 0.3:
				continue
			var w := 0.55 / length
			var nxt := []
			for sg: Array in segs:
				if t - w > sg[0]:
					nxt.append([sg[0], minf(sg[1], t - w)])
				if t + w < sg[1]:
					nxt.append([maxf(sg[0], t + w), sg[1]])
			segs = nxt
		for sg: Array in segs:
			var pa := a + d * float(sg[0])
			var pb := a + d * float(sg[1])
			var c := (pa + pb) * 0.5 + Vector3.UP * h
			var sz := Vector3(maxf(0.04, absf(pb.x - pa.x)), 0.04, maxf(0.04, absf(pb.z - pa.z)))
			deco(c, sz, mat)


## Invisible collision along a handrail (with the same gaps), on the railing layer only.
func _rail_body(a: Vector3, b: Vector3, gaps: Array) -> void:
	var d := b - a
	var length := d.length()
	var segs := [[0.0, 1.0]]
	for g: Vector3 in gaps:
		var t := clampf((g - a).dot(d) / (length * length), 0.0, 1.0)
		if (a + d * t).distance_to(Vector3(g.x, a.y, g.z)) > 0.3:
			continue
		var w := 0.55 / length
		var nxt := []
		for sg: Array in segs:
			if t - w > sg[0]:
				nxt.append([sg[0], minf(sg[1], t - w)])
			if t + w < sg[1]:
				nxt.append([maxf(sg[0], t + w), sg[1]])
		segs = nxt
	for sg: Array in segs:
		var pa := a + d * float(sg[0])
		var pb := a + d * float(sg[1])
		var body := StaticBody3D.new()
		body.collision_layer = Layers.RAILING
		body.collision_mask = 0
		body.position = (pa + pb) * 0.5 + Vector3.UP * 0.55
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(maxf(0.08, absf(pb.x - pa.x)), 1.1, maxf(0.08, absf(pb.z - pa.z)))
		cs.shape = bs
		body.add_child(cs)
		add_child(body)


func ladder(bottom: Vector3, h: float, normal: Vector3, top_step := 0.8) -> Ladder:
	var l := Ladder.make(bottom, h, normal, top_step)
	add_child(l)
	ladders.append(l)
	return l


func _face(st: SurfaceTool, pts: Array, center: Vector3) -> void:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	var fc := Vector3.ZERO
	for v: Vector3 in pts:
		fc += v
	fc /= pts.size()
	# Godot's front faces wind clockwise: flip when the normal points outward
	if n.dot(fc - center) > 0.0:
		pts.reverse()
	for i in range(1, pts.size() - 1):
		st.add_vertex(pts[0])
		st.add_vertex(pts[i])
		st.add_vertex(pts[i + 1])


## A wall along an axis with door/window openings: {a, b, y0, y1} along its length.
func wall(axis: String, fixed: float, from: float, to: float, thick: float, h: float, openings: Array, mat: String, base := 0.0) -> void:
	var t := thick * 0.5
	var seg := func(a: float, b: float, y0: float, y1: float) -> void:
		if b - a < 0.01 or y1 - y0 < 0.01:
			return
		if axis == "x":
			box(a, base + y0, fixed - t, b, base + y1, fixed + t, mat)
		else:
			box(fixed - t, base + y0, a, fixed + t, base + y1, b, mat)
	openings.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.a < q.a)
	var cur := from
	for o: Dictionary in openings:
		seg.call(cur, o.a, 0.0, h)
		seg.call(o.a, o.b, 0.0, o.y0)
		seg.call(o.a, o.b, o.y1, h)
		cur = o.b
	seg.call(cur, to, 0.0, h)


func door(a: float, w := 1.4, h := 2.2) -> Dictionary:
	return {"a": a, "b": a + w, "y0": 0.0, "y1": h}


func win(a: float, w := 3.0, y0 := 1.05, y1 := 2.2) -> Dictionary:
	return {"a": a, "b": a + w, "y0": y0, "y1": y1}


func crate(x: float, z: float, s := 1.3, y := 0.0, h := -1.0) -> void:
	var hh := s if h < 0.0 else h
	box(x - s / 2, y, z - s / 2, x + s / 2, y + hh, z + s / 2, "wood")


func container(x0: float, z0: float, x1: float, z1: float, mat: String, y := 0.0) -> void:
	box(x0, y, z0, x1, y + 2.6, z1, mat)
	if absf(x1 - x0) > absf(z1 - z0):
		box(x1, y + 0.2, z0 + 0.3, x1 + 0.04, y + 2.4, z1 - 0.3, "steel", false)
	else:
		box(x0 + 0.3, y + 0.2, z1, x1 - 0.3, y + 2.4, z1 + 0.04, "steel", false)


func lamp(x: float, y: float, z: float, color: Color, energy: float, rng: float, pole := false, cool := false, flicker := false) -> void:
	if pole:
		box(x - 0.12, 0, z - 0.12, x + 0.12, y + 0.2, z + 0.12, "steel")
		box(x - 0.12, y + 0.05, z - 0.12, x + 0.9, y + 0.2, z + 0.12, "steel", false)
		x += 0.7
	var l := Lamp.new()
	l.position = Vector3(x, y - 0.03, z)
	add_child(l)
	l.setup(color, energy, rng, cool, flicker)
	lamps.append(l)


func place(p: Pickup) -> Pickup:
	add_child(p)
	pickups.append(p)
	return p


func add_pickup(kind: Pickup.Kind, pos: Vector3, amount := 1, permanent := true) -> Pickup:
	var p := Pickup.create(kind, pos, amount, permanent)
	add_child(p)
	pickups.append(p)
	return p


# ------------------------------------------------------------------ look

func _environment() -> void:
	env = Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("moon_dir", _moon_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# readable night: a cool moonlit fill so shapes always read, with lamps as warm pools
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a7ea3")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	apply_brightness()
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.011
	env.volumetric_fog_albedo = Color("a8b4c8")
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("a9bcff")
	moon.light_energy = 1.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	moon.light_volumetric_fog_energy = 0.4
	add_child(moon)
	moon.look_at_from_position(_moon_dir * 80.0, Vector3.ZERO)


func apply_brightness() -> void:
	if env:
		env.tonemap_exposure = EXPOSURE * Settings.brightness


# ------------------------------------------------------------------ the compound

func _layout() -> void:
	box(-56, -1, -42, 56, 0, 42, "asphalt")
	wall("x", 36.5, -51, 51, 1, 4.5, [{"a": -42.0, "b": -40.6, "y0": 0.0, "y1": 1.25}], "block")
	wall("x", -36.5, -51, 51, 1, 4.5, [], "block")
	wall("z", -50.5, -36, 36, 1, 4.5, [{"a": -30.3, "b": -28.3, "y0": 0.0, "y1": 4.5}], "block")
	wall("z", 50.5, -36, 36, 1, 4.5, [], "block")
	for b: Array in [[-51, 36, 51, 37], [-51, -37, 51, -36], [-51, -36, -50, -30.3], [-51, -28.3, -50, 36], [50, -36, 51, 36]]:
		blocker(b[0], 4.5, b[1], b[2], 40, b[3])
	blocker(-51, 2.2, -30.3, -50, 40, -28.3)
	_outside()
	_razor_wire()
	wall("x", -20, -50, -14, 0.6, 2.4, [{"a": -48.0, "b": -44.5, "y0": 0.0, "y1": 2.4}], "block")
	wall("x", -20, -8, 10, 0.6, 2.4, [], "block")

	# warehouse (x 10..48, z -20..30)
	box(10.25, 0, -19.75, 47.75, 0.02, 29.75, "concrete", false)
	wall("z", 10, -20, 30, 0.5, 9, [{"a": 0.0, "b": 6.0, "y0": 0.0, "y1": 5.0}, {"a": 20.0, "b": 21.6, "y0": 0.0, "y1": 2.4}], "corrugated")
	wall("z", 48, -20, 30, 0.5, 9, [{"a": 10.0, "b": 11.4, "y0": 4.2, "y1": 6.6}], "corrugated")
	wall("x", -20, 10, 48, 0.5, 9, [{"a": 28.0, "b": 29.6, "y0": 0.0, "y1": 2.4}], "corrugated")
	wall("x", 30, 10, 48, 0.5, 9, [{"a": 20.0, "b": 21.6, "y0": 0.0, "y1": 2.4}], "corrugated")
	# fire escape up the east alley to the mezzanine
	stairs(48.3, -4.0, 50.0, 9.4, 0, 4.2, "z", 1)
	box(48.3, 4.0, 9.4, 50.0, 4.2, 12.2, "grating")
	box(48.3, 4.2, 12.1, 50.0, 5.2, 12.2, "steel")
	box(9.6, 9, -20.4, 48.4, 9.4, 30.4, "roof")
	box(10.25, 3.9, 22, 47.75, 4.2, 29.75, "grating")
	box(40, 3.9, -19.75, 47.75, 4.2, 22, "grating")
	for x: float in [20.0, 30.0]:
		box(x - 0.2, 0, 21.8, x + 0.2, 3.9, 22.2, "steel")
	for z: float in [-3.0, 6.0, 14.0]:
		box(39.8, 0, z - 0.2, 40.2, 3.9, z + 0.2, "steel")
	box(12.0, 4.2, 21.95, 12.1, 5.15, 22.05, "steel")
	box(15, 4.2, 21.95, 40, 5.15, 22.05, "steel")
	box(39.95, 4.2, -19.75, 40.05, 5.15, -9, "steel")
	box(39.95, 4.2, -6, 40.05, 5.15, 6.0, "steel")
	box(39.95, 4.2, 7.6, 40.05, 5.15, 22, "steel")
	stairs(12, 10, 15, 22, 0, 4.2, "z", 1)
	stairs(37, -19, 40, -6, 0, 4.2, "z", 1)
	# catwalks: across the bay, and down the west wall to the north mezzanine
	catwalk(10.25, 6.0, 40.0, 7.6, 4.2, ["n", "s"], [Vector3(14.0, 4.2, 6.0)])
	catwalk(10.25, 7.6, 11.85, 22.0, 4.2, ["e"])
	ladder(Vector3(14.0, 0, 6.0), 4.2, Vector3.FORWARD, 0.9)
	wall("x", 24.5, 40.5, 47.75, 0.2, 2.6, [door(41, 1.4), win(44, 2.6, 1.0, 2.0)], "plaster", 4.2)
	wall("z", 40.5, 24.5, 29.75, 0.2, 2.6, [win(25.5, 2.8, 1.0, 2.0)], "plaster", 4.2)
	box(40.4, 6.8, 24.4, 47.75, 7.0, 29.75, "metal")
	box(44.8, 4.2, 27.4, 47.4, 5.0, 29.2, "wood")
	for r: Array in [[16, -14, 28, -12.8], [16, -6, 28, -4.8], [20, 8, 32, 9.2], [31, -14, 37, -12.8]]:
		box(r[0], 0, r[1], r[2], 3.6, r[3], "rack")
		for y: float in [1.2, 2.4]:
			box(r[0] + 0.1, y, r[1] - 0.02, r[2] - 0.1, y + 0.08, r[3] + 0.02, "steel", false)
	box(33, 0, -2, 34.2, 3.6, 6, "rack")
	crate(24, 1.5, 1.4)
	crate(24, 1.5, 1.2, 1.4)
	crate(18.5, 16)
	crate(19.9, 16.2)
	crate(19.2, 16.1, 1.2, 1.3)
	crate(35.5, 15.5, 1.6, 0, 0.9)
	crate(14, -17)
	crate(15.4, -17.4, 1.2)
	box(27, 0, 13, 28.4, 2.2, 15.4, "c_rust")
	crate(44, -14)
	crate(44, -12.6)
	crate(13.5, 27.5, 1.3, 4.2)
	lamp(22, 8.6, -9, Color("dfe8ff"), 2.4, 18, false, true)
	lamp(30, 8.6, 12, Color("dfe8ff"), 2.4, 18, false, true)
	lamp(44, 6.6, 27, Color("ffd8a0"), 1.2, 7)
	lamp(34, 8.6, -4, Color("dfe8ff"), 2.0, 16, false, true, true)

	# office block (x -30..0, z 12..32)
	box(-29.8, 0, 12.2, -0.2, 0.02, 31.8, "concrete", false)
	wall("x", 12, -30, 0, 0.4, 3.4, [door(-16), win(-27), win(-11), win(-5)], "plaster")
	wall("x", 32, -30, 0, 0.4, 3.4, [win(-15), win(-6)], "plaster")
	wall("z", -30, 12, 32, 0.4, 3.4, [door(20, 2.4), win(14), {"a": 27.8, "b": 29.0, "y0": 0.1, "y1": 1.35}], "plaster")
	_duct()
	wall("z", 0, 12, 32, 0.4, 3.4, [door(20, 2.4), win(14), win(26)], "plaster")
	wall("x", 20, -30, 0, 0.2, 3.4, [door(-25), door(-8)], "plaster")
	wall("x", 22.4, -30, 0, 0.2, 3.4, [door(-26), door(-16), door(-6)], "plaster")
	wall("z", -12, 12, 20, 0.2, 3.4, [], "plaster")
	wall("z", -20, 22.4, 32, 0.2, 3.4, [], "plaster")
	wall("z", -10, 22.4, 32, 0.2, 3.4, [], "plaster")
	# roof slab, with a hatch over the armoury
	box(-30.2, 3.4, 11.8, 0.2, 3.7, 30.8, "concrete")
	box(-30.2, 3.4, 30.8, -13.6, 3.7, 32.2, "concrete")
	box(-12.4, 3.4, 30.8, 0.2, 3.7, 32.2, "concrete")
	box(-13.6, 3.4, 31.8, -12.4, 3.7, 32.2, "concrete")
	box(-13.7, 3.7, 30.75, -12.3, 3.85, 30.8, "steel", false)
	ladder(Vector3(-13.0, 0, 31.8), 3.7, Vector3.FORWARD, -1.5)
	box(-30.2, 3.7, 11.8, 0.2, 4.6, 12.1, "concrete")
	box(-30.2, 3.7, 31.9, -18, 4.6, 32.2, "concrete")
	box(-15.4, 3.7, 31.9, 0.2, 4.6, 32.2, "concrete")
	box(-30.2, 3.7, 12.1, -29.9, 4.6, 31.9, "concrete")
	box(-0.1, 3.7, 12.1, 0.2, 4.6, 31.9, "concrete")
	box(-22, 3.7, 20, -19, 5.0, 23, "metal")
	box(-8, 3.7, 26, -6.5, 4.5, 29, "metal")
	stairs(-28, 32.2, -16, 34.7, 0, 3.7, "x", 1)
	for t: Array in [[-26, 16], [-20, 17.5], [-6, 15.5], [-25, 28], [-15, 29], [-5, 27]]:
		box(t[0] - 0.8, 0, t[1] - 0.45, t[0] + 0.8, 0.78, t[1] + 0.45, "wood")
	box(-29.6, 0, 13, -28.9, 1.9, 15.5, "metal")
	box(-11.6, 0, 17, -10.9, 1.9, 19.5, "metal")
	lamp(-21, 3.3, 16, Color("dfe8ff"), 0.9, 9, false, true)
	lamp(-15, 3.3, 21.2, Color("dfe8ff"), 0.8, 9, false, true, true)
	lamp(-5, 3.3, 27, Color("dfe8ff"), 0.8, 8, false, true)

	# courtyard
	container(-22, -7, -16, -4.6, "c_blue")
	container(-6, -14, -3.6, -8, "c_red")
	container(-6, -13, -3.6, -7, "c_green", 2.6)
	crate(-3, -8.4, 1.2)
	crate(-4.8, -13.5, 1.0, 2.6, 1.3)
	container(0, 3, 6, 5.4, "c_rust")
	for b: Array in [[-13.5, -2.3, -10.5, -1.7], [-20.3, 4.5, -19.7, 7.5], [0.5, -6.3, 3.5, -5.7], [-27, -12.3, -24, -11.7], [3.7, 9, 4.3, 12]]:
		box(b[0], 0, b[1], b[2], 1.1, b[3], "concrete")
	wall("x", -19, -14, -11, 0.2, 2.6, [win(-13.6, 2.2, 1.0, 2.2)], "plaster")
	wall("x", -16, -14, -11, 0.2, 2.6, [door(-12.6, 1.2)], "plaster")
	wall("z", -14, -19, -16, 0.2, 2.6, [win(-18.4, 1.8, 1.0, 2.2)], "plaster")
	wall("z", -11, -19, -16, 0.2, 2.6, [win(-18.4, 1.8, 1.0, 2.2)], "plaster")
	box(-14.2, 2.6, -19.2, -10.8, 2.8, -15.8, "metal")
	lamp(-24, 6.5, -14, Color("ffa040"), 2.6, 20, true)
	lamp(-3, 6.5, -1, Color("ffa040"), 2.6, 20, true)
	lamp(-17, 6.5, 8, Color("ffa040"), 2.2, 18, true)

	# north yard, west alley, loading yard
	crate(6, 22)
	crate(7.4, 22.3)
	crate(4, 30)
	box(2, 0, 16, 3.2, 1.1, 19, "concrete")
	lamp(5, 6.5, 27, Color("ffa040"), 2.0, 16, true)
	box(-46, 0, 8, -42, 3, 14, "steel")
	box(-40.5, 0, -1, -38.5, 1.3, 0.4, "c_green")
	box(-37, 0, 22, -35, 1.3, 23.4, "c_green")
	box(-48, 0, -10, -45, 1.2, -8, "metal")
	crate(-34, 6)
	crate(-44, 28)
	crate(-42.7, 28.3, 1.2)
	box(-38, 0, -30, -30, 3.6, -27.5, "c_blue")
	box(-30, 0, -30, -27.4, 2.9, -27.5, "metal")
	box(-24, 0, -33, -16, 3.6, -30.5, "c_red")
	box(-16, 0, -33, -13.4, 2.9, -30.5, "metal")
	box(22, 0, -31, 30, 3.6, -28.5, "c_rust")
	crate(4, -27)
	crate(5.4, -27.3, 1.2)
	crate(38, -26)
	for x in range(-40, 45, 6):
		box(x, 0.003, -24.1, x + 3, 0.012, -23.9, "paint", false)
	for x in range(-32, 6, 4):
		box(x, 0.003, -34.2, x + 0.15, 0.012, -26, "paint", false)
	lamp(-34, 6.5, -24, Color("ffa040"), 2.2, 18, true)
	lamp(30, 6.5, -24, Color("ffa040"), 2.0, 18, true)
	for c: Array in [[10.2, -20.2], [47.8, -20.2], [10.2, 30.2], [47.8, 30.2]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.2, 0.24)
		mi.mesh = bm
		mi.material_override = Mats.emissive(Color("ff2010"), 5.0)
		mi.position = Vector3(c[0], 9.5, c[1])
		add_child(mi)

	_vehicles()
	_furnish()
	_watchtower()
	_armory()
	_drones()
	_doors()
	# a crate against the loading yard wall: a way over into the main yard
	crate(-36.0, -21.0, 1.3)

	add_pickup(Pickup.Kind.MEDKIT, Vector3(-6, 0.78, 15.5))
	add_pickup(Pickup.Kind.MEDKIT, Vector3(35.5, 0.9, 15.5))
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-26.6, 0, -29))
	add_pickup(Pickup.Kind.AMMO, Vector3(14, 1.3, -17))
	add_pickup(Pickup.Kind.AMMO, Vector3(-26, 0.78, 16))
	add_pickup(Pickup.Kind.AMMO, Vector3(-19, 0, -3.9))
	add_pickup(Pickup.Kind.AMMO, Vector3(40.5, 4.2, 15))
	box(-13.6, 0, -18.95, -11.4, 0.8, -18.35, "wood")
	# security network: three access points and five cameras on the same wire
	_device(Device.make(Device.Kind.ACCESS, "SECURITY TERMINAL", Vector3(-12.5, 0.8, -18.6), PI))
	_device(Device.make(Device.Kind.ACCESS, "JUNCTION BOX", Vector3(32.0, 1.3, -20.34), 0.0))
	_device(Device.make(Device.Kind.ACCESS, "SERVER CABINET", Vector3(-29.35, 0, 30.6), -PI / 2))
	solid(-29.8, 0, 30.3, -28.95, 2.0, 30.9)
	_device(Device.camera(1, Vector3(9.6, 6.0, -12.0), PI / 2, 0.7))
	_device(Device.camera(2, Vector3(-14.0, 3.0, -19.3), 0.3, 0.8))
	_device(Device.camera(3, Vector3(47.5, 7.5, 0.0), PI / 2, 0.8, -0.45))
	_device(Device.camera(4, Vector3(-0.5, 3.0, 21.2), PI / 2, 0.25, -0.2))
	_device(Device.camera(5, Vector3(9.6, 6.0, 28.5), PI * 0.6, 0.6))
	# guard radio runs through one relay cabinet on the office roof
	_device(Device.make(Device.Kind.RELAY, "COMMS RELAY", Vector3(-26.5, 3.7, 29.0)))
	solid(-26.95, 3.7, 28.7, -26.05, 4.8, 29.3)
	# lighting circuits, one breaker panel per zone
	_device(Device.make(Device.Kind.BREAKER, "BREAKER", Vector3(-7.0, 1.3, -19.63), PI, "YARD"))
	_device(Device.make(Device.Kind.BREAKER, "BREAKER", Vector3(10.33, 1.4, -8.0), -PI / 2, "WAREHOUSE"))
	_device(Device.make(Device.Kind.BREAKER, "BREAKER", Vector3(-29.73, 1.4, 17.0), -PI / 2, "OFFICE"))
	_device(Device.make(Device.Kind.BREAKER, "BREAKER", Vector3(-30.0, 1.3, -20.37), 0.0, "LOADING YARD"))
	_device(Device.make(Device.Kind.LAPTOP, "LAPTOP", intel_pos))
	for l in lamps:
		l.zone = zone_of(l.position)


# ------------------------------------------------------------------ details

## The strip outside the west wall: dark scrub, the insertion vehicle, the breach.
func _outside() -> void:
	box(-56, 0.0, -42, -51, 0.015, 42, "dirt", false)
	box(-51, 0.0, 37, 56, 0.015, 42, "dirt", false)
	blocker(-56.5, 0, -42.5, -55.8, 40, 42.5)
	blocker(55.8, 0, -42.5, 56.5, 40, 42.5)
	blocker(-56, 0, -42.5, 56, 40, -41.8)
	blocker(-56, 0, 41.8, 56, 40, 42.5)
	blocker(-51, 0, -41.8, 56, 40, -37)
	blocker(51, 0, -37, 55.8, 40, 37)
	for r: Array in [[-50.9, -30.9, 0.5, 0.35], [-50.2, -27.9, 0.4, 0.3], [-51.6, -28.7, 0.3, 0.25], [-49.6, -30.6, 0.35, 0.2], [-51.3, -31.5, 0.25, 0.2]]:
		box(r[0] - r[2], 0, r[1] - r[2], r[0] + r[2], r[3], r[1] + r[2], "block", false)
	sedan(Vector2(-53.8, -21.0), false, "c_green")
	for z: float in [-38.0, -12.0, 3.0, 19.0, 33.0]:
		box(-55.2, 0, z, -54.0, 0.9, z + 1.6, "dirt", false)


## Concertina wire along the top of the perimeter wall, as one multimesh of coils.
func _razor_wire() -> void:
	var runs := [[Vector3(-50.5, 4.75, -36), Vector3(-50.5, 4.75, -30.6)], [Vector3(-50.5, 4.75, -28.0), Vector3(-50.5, 4.75, 36)],
		[Vector3(50.5, 4.75, -36), Vector3(50.5, 4.75, 36)], [Vector3(-51, 4.75, 36.5), Vector3(51, 4.75, 36.5)], [Vector3(-51, 4.75, -36.5), Vector3(51, 4.75, -36.5)]]
	var xf: Array[Transform3D] = []
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var d := (b - a).normalized()
		var n := int(a.distance_to(b) / 0.32)
		var basis := Basis(Vector3.UP.cross(d).normalized(), d, Vector3.UP.cross(d).normalized().cross(d))
		for i in n:
			xf.append(Transform3D(basis.rotated(d, randf_range(-0.1, 0.1)), a.lerp(b, float(i) / n)))
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.215
	tm.rings = 12
	tm.ring_segments = 3
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color("6a6e72")
	wire.metallic = 0.8
	wire.roughness = 0.4
	wire.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.material = wire
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## Box in a vehicle's frame: `a` runs along its length from the centre, `w` is the half width.
func _vbox(c: Vector2, along_x: bool, a0: float, a1: float, w: float, y0: float, y1: float, mat: String, collide := true) -> void:
	if along_x:
		box(c.x + a0, y0, c.y - w, c.x + a1, y1, c.y + w, mat, collide)
	else:
		box(c.x - w, y0, c.y + a0, c.x + w, y1, c.y + a1, mat, collide)


func _wheels(c: Vector2, along_x: bool, at: Array, w: float, r: float) -> void:
	var tire := Mats.plain(Color("151515"), 0.95)
	for a: float in at:
		for side: float in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 0.28
			mi.mesh = cm
			mi.material_override = tire
			if along_x:
				mi.position = Vector3(c.x + a, r, c.y + side * w)
				mi.rotation = Vector3(PI / 2, 0, 0)
			else:
				mi.position = Vector3(c.x + side * w, r, c.y + a)
				mi.rotation = Vector3(0, 0, PI / 2)
			add_child(mi)


## Steel bodies stop rifle rounds, so vehicles are real cover. Front faces +along.
func truck(c: Vector2, along_x: bool, cab: String) -> void:
	_vbox(c, along_x, -3.7, 3.7, 1.1, 0.5, 0.95, "steel")
	_vbox(c, along_x, -3.7, 1.3, 1.25, 0.95, 3.4, "metal")
	_vbox(c, along_x, 1.45, 3.7, 1.2, 0.95, 2.75, cab)
	_vbox(c, along_x, 3.68, 3.74, 1.0, 1.85, 2.55, "glass", false)
	_vbox(c, along_x, -3.76, -3.7, 1.2, 1.0, 3.3, "steel", false)
	_wheels(c, along_x, [-2.6, -1.5, 2.7], 1.1, 0.5)


func sedan(c: Vector2, along_x: bool, paint: String) -> void:
	_vbox(c, along_x, -2.3, 2.3, 0.9, 0.32, 1.0, paint)
	_vbox(c, along_x, -1.15, 0.95, 0.82, 1.0, 1.42, "glass")
	_wheels(c, along_x, [-1.45, 1.45], 0.82, 0.33)


func forklift(c: Vector2, along_x: bool) -> void:
	_vbox(c, along_x, -1.1, 0.75, 0.6, 0.15, 1.25, "rack")
	_vbox(c, along_x, 0.8, 0.92, 0.45, 0.0, 2.9, "steel")
	_vbox(c, along_x, 0.92, 2.0, 0.42, 0.08, 0.14, "steel", false)
	_vbox(c, along_x, -0.9, 0.7, 0.58, 2.1, 2.16, "steel", false)
	for a: float in [-0.85, 0.65]:
		for sw: float in [-0.52, 0.52]:
			if along_x:
				box(c.x + a - 0.03, 1.25, c.y + sw - 0.03, c.x + a + 0.03, 2.1, c.y + sw + 0.03, "steel", false)
			else:
				box(c.x + sw - 0.03, 1.25, c.y + a - 0.03, c.x + sw + 0.03, 2.1, c.y + a + 0.03, "steel", false)
	_wheels(c, along_x, [-0.75, 0.55], 0.58, 0.28)


func _vehicles() -> void:
	truck(Vector2(-6.0, -31.2), true, "c_blue")
	sedan(Vector2(-38.0, 15.5), false, "steel")
	sedan(Vector2(-38.0, 21.5), false, "c_red")
	sedan(Vector2(-11.0, -26.5), true, "metal")
	forklift(Vector2(22.0, -1.5), false)
	for p: Array in [[30.0, 18.0], [31.4, 18.0], [30.7, 19.3]]:
		box(p[0] - 0.6, 0, p[1] - 0.5, p[0] + 0.6, 0.14, p[1] + 0.5, "wood")
		box(p[0] - 0.55, 0.14, p[1] - 0.45, p[0] + 0.55, 1.1, p[1] + 0.45, "corrugated" if int(p[0]) % 2 == 0 else "wood")


## Desks get chairs and screens, the booth gets its monitor bank, walls get cabinets.
func _furnish() -> void:
	var screen := Mats.emissive(Color("9fc4ff"), 0.9)
	var dark := Mats.plain(Color("18191b"), 0.5, 0.2)
	var chair := Mats.plain(Color("232427"), 0.8)
	for t: Array in [[-26, 16], [-20, 17.5], [-6, 15.5], [-25, 28], [-15, 29], [-5, 27]]:
		var x: float = t[0]
		var z: float = t[1]
		box(x - 0.25, 0.78, z - 0.3, x + 0.25, 1.1, z - 0.27, "metal", false)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.46, 0.27, 0.005)
		mi.mesh = bm
		mi.material_override = screen
		mi.position = Vector3(x, 0.955, z - 0.265)
		add_child(mi)
		var cm := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.5, 0.08, 0.5)
		cm.mesh = cb
		cm.material_override = chair
		cm.position = Vector3(x + 0.1, 0.48, z + 0.75)
		cm.rotation.y = randf_range(-0.5, 0.5)
		add_child(cm)
		var back := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.48, 0.55, 0.06)
		back.mesh = bb
		back.material_override = chair
		back.position = Vector3(0, 0.3, 0.24)
		cm.add_child(back)
	# filing cabinets
	for c: Array in [[-29.5, 24.0], [-29.5, 25.0], [-0.5, 30.5], [-12.45, 13.0]]:
		box(c[0] - 0.3, 0, c[1] - 0.4, c[0] + 0.3, 1.35, c[1] + 0.4, "metal")
	# guard booth monitor bank, looking at the gate
	for i in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.42, 0.3, 0.05)
		mi.mesh = bm
		mi.material_override = dark
		mi.position = Vector3(-13.4 + i * 0.45, 1.0, -18.8)
		add_child(mi)
		var sc := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.38, 0.26, 0.005)
		sc.mesh = sm
		sc.material_override = screen
		sc.position = Vector3(0, 0, 0.03)
		mi.add_child(sc)


## A crawl duct along the outside of the office's west wall into the server room. Too low to
## stand in, so guards never use it; crawling is loud on sheet metal.
func _duct() -> void:
	box(-31.5, 0, 16.9, -30.2, 0.1, 29.2, "metal")
	box(-31.5, 1.35, 16.9, -30.2, 1.45, 29.2, "metal")
	box(-31.6, 0, 16.9, -31.5, 1.45, 29.2, "metal")
	box(-31.6, 0, 29.2, -30.2, 1.45, 29.3, "metal")
	ducts.append(AABB(Vector3(-31.5, 0, 16.9), Vector3(1.7, 1.45, 12.4)))
	_device(Device.make(Device.Kind.VENT, "VENT GRILLE", Vector3(-30.85, 0.72, 16.88), 0.0))
	_device(Device.make(Device.Kind.VENT, "VENT GRILLE", Vector3(-29.78, 0.72, 28.4), PI / 2))
	# a ladder onto the blue container in the loading yard: a perch over the whole yard
	ladder(Vector3(-34.0, 0, -30.0), 3.6, Vector3.FORWARD, 0.9)


## Overwatch on the loading yard: a raised platform, waist-high walls for cover, a sweeping
## searchlight. Guards climb it by the stairs; so can you.
func _watchtower() -> void:
	var x0 := 6.0
	var x1 := 9.0
	var z0 := -35.8
	var z1 := -32.8
	var top := 4.5
	for c: Array in [[x0, z0], [x1, z0], [x0, z1], [x1, z1]]:
		var px: float = c[0]
		var pz: float = c[1]
		box(px - 0.1, 0, pz - 0.1, px + 0.1, 7.0, pz + 0.1, "steel")
	box(x0, top - 0.2, z0, x1, top, z1, "grating")
	box(x0, top, z0, x1, top + 1.0, z0 + 0.1, "metal")
	box(x0, top, z1 - 0.1, x1, top + 1.0, z1, "metal")
	box(x0, top, z0, x0 + 0.1, top + 1.0, z1, "metal")
	box(x1 - 0.1, top, z0 + 1.5, x1, top + 1.0, z1, "metal")
	box(x0 - 0.2, 7.0, z0 - 0.2, x1 + 0.2, 7.12, z1 + 0.2, "metal", false)
	stairs(x1, z0, x1 + 6.0, z0 + 1.4, 0, top, "x", -1)
	var sl := SpotLight3D.new()
	sl.light_color = Color("e8f0ff")
	sl.light_energy = 9.0
	sl.spot_range = 38.0
	sl.spot_angle = 9.0
	sl.spot_attenuation = 0.6
	sl.shadow_enabled = true
	sl.light_volumetric_fog_energy = 3.0
	sl.position = Vector3(x0 + 0.4, top + 1.3, z1 - 0.4)
	sl.set_meta("zone", "LOADING YARD")
	sl.set_meta("sweep", 0.0)
	add_child(sl)
	searchlights.append(sl)
	var housing := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.22
	hm.bottom_radius = 0.26
	hm.height = 0.45
	housing.mesh = hm
	housing.material_override = Mats.plain(Color("2a2c2f"), 0.5, 0.6)
	housing.rotation.x = PI / 2
	sl.add_child(housing)


## Searchlights sweep the yard in a slow arc.
func tick_searchlights(dt: float) -> void:
	for sl in searchlights:
		var t: float = sl.get_meta("sweep") + dt
		sl.set_meta("sweep", t)
		var target := Vector3(-14.0 + sin(t * 0.25) * 20.0, 0.0, -27.0 + sin(t * 0.17) * 6.0)
		sl.look_at(target, Vector3.UP)


## The armoury behind the office: ammunition, a medkit and grenades, behind a security door.
func _armory() -> void:
	for r: Array in [[-19.6, 23.0, -19.0, 31.6], [-10.9, 23.0, -10.4, 31.6]]:
		box(r[0], 0, r[1], r[2], 2.0, r[3], "rack")
	add_pickup(Pickup.Kind.AMMO, Vector3(-19.3, 0.9, 27.0))
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-10.65, 0.9, 25.0))
	add_pickup(Pickup.Kind.FRAG, Vector3(-10.65, 0.9, 29.0))


## Two security quadrotors on automated patrols: one over the yards, one over the warehouse.
func _drones() -> void:
	_drone(Drone.make("DRONE-1", [[-24, -14], [-3, -1], [2, 16], [-20, 10], [-34, -8]], 5.6))
	_drone(Drone.make("DRONE-2", [[16, -14], [36, -14], [36, 20], [18, 16]], 7.2))


func _drone(d: Drone) -> void:
	add_child(d)
	drones.append(d)


func _doors() -> void:
	var M := Door.Lock.MAGLOCK
	var S := Door.Lock.STRIKE
	_door(Door.make("SERVER ROOM", Vector3(-25.3, 0, 22.4), "x", 1.4, "office", M, "OFFICE"))
	_door(Door.make("ARMOURY", Vector3(-15.3, 0, 22.4), "x", 1.4, "security", S, "OFFICE"))
	_door(Door.make("WAREHOUSE SOUTH", Vector3(28.8, 0, -20.0), "x", 1.6, "warehouse", S, "WAREHOUSE", 2.4))
	_door(Door.make("WAREHOUSE NORTH", Vector3(20.8, 0, 30.0), "x", 1.6, "warehouse", M, "WAREHOUSE", 2.4))
	_door(Door.make("FIRE ESCAPE", Vector3(48.0, 4.2, 10.7), "z", 1.4, "warehouse", M, "WAREHOUSE", 2.4))
	_door(Door.make("DATA OFFICE", Vector3(41.7, 4.2, 24.5), "x", 1.4, "secure", S, "WAREHOUSE"))


func _door(d: Door) -> void:
	add_child(d)
	doors.append(d)


## Where you are, for the HUD.
func area_name(p: Vector3) -> String:
	if p.x < -50.5 or p.x > 50.5 or absf(p.z) > 36.5:
		return "OUTSIDE THE WIRE"
	if p.x > 5.5 and p.x < 9.5 and p.z > -36.0 and p.z < -32.5 and p.y > 3.5:
		return "WATCHTOWER"
	if p.x > 10.0 and p.x < 48.0 and p.z > -20.0 and p.z < 30.0:
		if p.y > 3.5:
			return "DATA OFFICE" if p.x > 40.5 and p.z > 24.5 else "MEZZANINE"
		return "WAREHOUSE"
	if p.x > -30.5 and p.x < 0.5 and p.z > 11.5 and p.z < 32.5:
		if p.y > 3.0:
			return "OFFICE ROOF"
		if p.z > 22.4 and p.x < -20.0:
			return "SERVER ROOM"
		if p.z > 22.4 and p.x < -10.0:
			return "ARMOURY"
		return "OFFICE"
	if p.z < -20.0:
		return "LOADING YARD"
	if p.x > -16.0 and p.x < -9.0 and p.z > -21.0 and p.z < -14.0:
		return "GATEHOUSE"
	if p.x < -30.0:
		return "WEST ALLEY"
	if p.z > 12.0 or (p.x > 10.0 and p.z > 30.0):
		return "NORTH YARD"
	return "MAIN YARD"


func in_duct(p: Vector3) -> bool:
	for a in ducts:
		if a.has_point(p + Vector3.UP * 0.3):
			return true
	return false


func zone_of(p: Vector3) -> String:
	if p.x > 10.0 and p.x < 48.0 and p.z > -20.0 and p.z < 30.0:
		return "WAREHOUSE"
	if p.x > -30.5 and p.x < 0.5 and p.z > 11.5 and p.z < 32.5:
		return "OFFICE"
	if p.z < -20.0:
		return "LOADING YARD"
	return "YARD"


## Invisible collision that still shapes the navigation mesh.
func solid(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(absf(x1 - x0), y1 - y0, absf(z1 - z0))
	cs.shape = sh
	body.add_child(cs)
	body.set_meta("mat", "metal")
	body.set_meta("pen", 0.0)
	nav_region.add_child(body)


func _device(d: Device) -> void:
	add_child(d)
	devices.append(d)


# ------------------------------------------------------------------ navigation

func bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nav_region.navigation_mesh = nm
	nav_region.bake_finished.connect(func() -> void: nav_ready.emit(), CONNECT_ONE_SHOT)
	nav_region.bake_navigation_mesh(true)


func reset_props() -> void:
	for d in devices:
		d.reset()
	for d in doors:
		d.reset()
	for sl in searchlights:
		sl.visible = true
	for d in drones:
		d.reset()
	for l in lamps:
		l.dead = false
		l.powered = true
		l.light.visible = true
		l.light.light_energy = l.energy
		l.fixture_mat.emission_energy_multiplier = 6.0
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		if p.permanent:
			p.taken = false
			p.visible = true
		else:
			p.queue_free()
			pickups.remove_at(i)


## How much one lamp lights a person standing at p: only if it can actually reach them, with
## their chest or head in its line of sight. Walls stop it.
func lamp_light(l: Lamp, p: Vector3) -> float:
	var c := l.contribution(p)
	if c <= 0.0:
		return 0.0
	var space := get_world_3d().direct_space_state
	for h: float in [1.0, 1.55]:
		var q := PhysicsRayQueryParameters3D.create(l.light.global_position, p + Vector3.UP * h, Layers.WORLD)
		if space.intersect_ray(q).is_empty():
			return c
	return 0.0


## How visible a point is: 0.22 in deep shadow, 1 under a lamp or flashlight.
func light_level(p: Vector3, flashlights: Array) -> float:
	var level := 0.22
	var space := get_world_3d().direct_space_state
	var from := p + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + _moon_dir * 60.0, Layers.WORLD)
	if space.intersect_ray(q).is_empty():
		level += 0.3
	for l in lamps:
		level += lamp_light(l, p) * 0.75
	for f: SpotLight3D in flashlights:
		if not f.visible:
			continue
		var to := p + Vector3.UP - f.global_position
		var d := to.length()
		if d > f.spot_range:
			continue
		var cosang := (-f.global_basis.z).dot(to / d)
		if cosang > cos(deg_to_rad(f.spot_angle)):
			var q2 := PhysicsRayQueryParameters3D.create(f.global_position, p + Vector3.UP, Layers.WORLD)
			if space.intersect_ray(q2).is_empty():
				level += 0.8 * (1.0 - d / f.spot_range)
	return clampf(level, 0.22, 1.0)
