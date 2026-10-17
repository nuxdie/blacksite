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
var extraction := Vector3(-44, 0, -31)
var intel_pos := Vector3(46, 5.0, 28.2)
var player_start := Vector3(-44, 0, -32)
var _moon_dir := MOON_DIR.normalized()


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
func ramp(x0: float, z0: float, x1: float, z1: float, base: float, top: float, axis: String, dir: int, mat: String) -> void:
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
	body.add_child(mi)
	body.set_meta("mat", "steel")
	body.set_meta("pen", 0.0)
	nav_region.add_child(body)


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
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("moon_dir", _moon_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("46566e")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color("a8b4c8")
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("9fb4ff")
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	moon.light_volumetric_fog_energy = 0.4
	add_child(moon)
	moon.look_at_from_position(_moon_dir * 80.0, Vector3.ZERO)


# ------------------------------------------------------------------ the compound

func _layout() -> void:
	box(-56, -1, -42, 56, 0, 42, "asphalt")
	wall("x", 36.5, -51, 51, 1, 4.5, [], "block")
	wall("x", -36.5, -51, 51, 1, 4.5, [], "block")
	wall("z", -50.5, -36, 36, 1, 4.5, [], "block")
	wall("z", 50.5, -36, 36, 1, 4.5, [], "block")
	for b: Array in [[-51, 36, 51, 37], [-51, -37, 51, -36], [-51, -36, -50, 36], [50, -36, 51, 36]]:
		blocker(b[0], 4.5, b[1], b[2], 40, b[3])
	wall("x", -20, -50, -14, 0.6, 2.4, [{"a": -48.0, "b": -44.5, "y0": 0.0, "y1": 2.4}], "block")
	wall("x", -20, -8, 10, 0.6, 2.4, [], "block")

	# warehouse (x 10..48, z -20..30)
	box(10.25, 0, -19.75, 47.75, 0.02, 29.75, "concrete", false)
	wall("z", 10, -20, 30, 0.5, 9, [{"a": 0.0, "b": 6.0, "y0": 0.0, "y1": 5.0}, {"a": 20.0, "b": 21.6, "y0": 0.0, "y1": 2.4}], "corrugated")
	wall("z", 48, -20, 30, 0.5, 9, [], "corrugated")
	wall("x", -20, 10, 48, 0.5, 9, [{"a": 28.0, "b": 29.6, "y0": 0.0, "y1": 2.4}], "corrugated")
	wall("x", 30, 10, 48, 0.5, 9, [], "corrugated")
	box(9.6, 9, -20.4, 48.4, 9.4, 30.4, "roof")
	box(10.25, 3.9, 22, 47.75, 4.2, 29.75, "grating")
	box(40, 3.9, -19.75, 47.75, 4.2, 22, "grating")
	for x: float in [20.0, 30.0]:
		box(x - 0.2, 0, 21.8, x + 0.2, 3.9, 22.2, "steel")
	for z: float in [-3.0, 6.0, 14.0]:
		box(39.8, 0, z - 0.2, 40.2, 3.9, z + 0.2, "steel")
	box(10.25, 4.2, 21.95, 12, 5.15, 22.05, "steel")
	box(15, 4.2, 21.95, 40, 5.15, 22.05, "steel")
	box(39.95, 4.2, -19.75, 40.05, 5.15, -9, "steel")
	box(39.95, 4.2, -6, 40.05, 5.15, 22, "steel")
	ramp(12, 10, 15, 22, 0, 4.2, "z", 1, "grating")
	ramp(37, -19, 40, -6, 0, 4.2, "z", 1, "grating")
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
	wall("z", -30, 12, 32, 0.4, 3.4, [door(20, 2.4), win(14), win(26)], "plaster")
	wall("z", 0, 12, 32, 0.4, 3.4, [door(20, 2.4), win(14), win(26)], "plaster")
	wall("x", 20, -30, 0, 0.2, 3.4, [door(-25), door(-8)], "plaster")
	wall("x", 22.4, -30, 0, 0.2, 3.4, [door(-26), door(-16), door(-6)], "plaster")
	wall("z", -12, 12, 20, 0.2, 3.4, [], "plaster")
	wall("z", -20, 22.4, 32, 0.2, 3.4, [], "plaster")
	wall("z", -10, 22.4, 32, 0.2, 3.4, [], "plaster")
	box(-30.2, 3.4, 11.8, 0.2, 3.7, 32.2, "concrete")
	box(-30.2, 3.7, 11.8, 0.2, 4.6, 12.1, "concrete")
	box(-30.2, 3.7, 31.9, -18, 4.6, 32.2, "concrete")
	box(-15.4, 3.7, 31.9, 0.2, 4.6, 32.2, "concrete")
	box(-30.2, 3.7, 12.1, -29.9, 4.6, 31.9, "concrete")
	box(-0.1, 3.7, 12.1, 0.2, 4.6, 31.9, "concrete")
	box(-22, 3.7, 20, -19, 5.0, 23, "metal")
	box(-8, 3.7, 26, -6.5, 4.5, 29, "metal")
	ramp(-28, 32.2, -16, 34.7, 0, 3.7, "x", 1, "grating")
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

	add_pickup(Pickup.Kind.MEDKIT, Vector3(-6, 0.78, 15.5))
	add_pickup(Pickup.Kind.MEDKIT, Vector3(35.5, 0.9, 15.5))
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-26.6, 0, -29))
	add_pickup(Pickup.Kind.AMMO, Vector3(14, 1.3, -17))
	add_pickup(Pickup.Kind.AMMO, Vector3(-26, 0.78, 16))
	add_pickup(Pickup.Kind.AMMO, Vector3(-19, 0, -3.9))
	add_pickup(Pickup.Kind.AMMO, Vector3(40.5, 4.2, 15))
	box(-13.6, 0, -18.95, -11.4, 0.8, -18.35, "wood")
	_device(Device.make(Device.Kind.TERMINAL, Vector3(-12.5, 0.8, -18.6), PI))
	_device(Device.make(Device.Kind.LAPTOP, intel_pos))
	_device(Device.make(Device.Kind.RELAY, Vector3(-26.5, 3.7, 29.0)))
	_device(Device.camera(Vector3(9.6, 6.0, -12.0), PI / 2, 0.7))
	_device(Device.camera(Vector3(-14.0, 3.0, -19.3), 0.3, 0.8))
	_device(Device.camera(Vector3(47.5, 7.5, 0.0), PI / 2, 0.8, -0.45))
	_device(Device.camera(Vector3(-0.5, 3.0, 21.2), PI / 2, 0.25, -0.2))
	_device(Device.camera(Vector3(9.6, 6.0, 28.5), PI * 0.6, 0.6))


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
		d.hack_progress = 0.0
		d.hacked = false
		d.offline = false
		d.looped = 0.0
		d.aware = 0.0
		d.alarm = false
		if d._cone:
			d._cone.visible = true
		if d._lens_mat:
			d._lens_mat.emission_energy_multiplier = 1.5
		if d.kind == Device.Kind.LAPTOP:
			d._led_mat.emission = Color("40ff90")
		elif d.kind == Device.Kind.TERMINAL:
			d._led_mat.emission = Color("4ad0ff")
	for l in lamps:
		l.hack_progress = 0.0
		l.dead = false
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


## How visible a point is: 0.22 in deep shadow, 1 under a lamp or flashlight.
func light_level(p: Vector3, flashlights: Array) -> float:
	var level := 0.22
	var space := get_world_3d().direct_space_state
	var from := p + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + _moon_dir * 60.0, Layers.WORLD)
	if space.intersect_ray(q).is_empty():
		level += 0.3
	for l in lamps:
		level += l.contribution(p) * 0.75
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
