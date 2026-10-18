class_name Fx
extends Node3D
## Pooled visual effects: bullet holes, tracers, muzzle flashes, particle bursts and light flashes.

const DECALS := 140
const TRACERS := 48
const LIGHTS := 4
const SPRITES := 10

var _decals: Array[Decal] = []
var _di := 0
var _tracers: Array[Dictionary] = []
var _ti := 0
var _lights: Array[Dictionary] = []
var _sprites: Array[Dictionary] = []
var _si := 0
var _emitters: Dictionary = {}
var _hole_tex: ImageTexture
var _scorch_tex: ImageTexture
var _flash_tex: ImageTexture


func _ready() -> void:
	_hole_tex = _radial(64, [Color(0, 0, 0, 1), Color(0.04, 0.04, 0.04, 0.9), Color(0.12, 0.12, 0.12, 0.35), Color(0, 0, 0, 0)])
	_scorch_tex = _radial(128, [Color(0, 0, 0, 0.85), Color(0.05, 0.04, 0.03, 0.6), Color(0, 0, 0, 0)])
	_flash_tex = _star(128)
	for i in DECALS:
		var d := Decal.new()
		d.texture_albedo = _hole_tex
		d.size = Vector3(0.11, 0.1, 0.11)
		d.visible = false
		d.cull_mask = 1
		add_child(d)
		_decals.append(d)
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tmat.albedo_color = Color(3.0, 2.3, 1.2)
	for i in TRACERS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.012, 0.012, 4.0)
		mi.mesh = bm
		mi.material_override = tmat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append({"mesh": mi, "from": Vector3.ZERO, "dir": Vector3.FORWARD, "len": 0.0, "s": 0.0, "on": false})
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 10.0
		l.visible = false
		add_child(l)
		_lights.append({"light": l, "t": 0.0, "dur": 1.0, "e": 0.0})
	for i in SPRITES:
		var s := Sprite3D.new()
		s.texture = _flash_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.modulate = Color(1.0, 0.85, 0.6)
		s.pixel_size = 0.005
		s.visible = false
		s.material_override = _additive_sprite_mat()
		add_child(s)
		_sprites.append({"sprite": s, "t": 0.0})
	_emitters["dust"] = _make_emitter(10, 0.7, Color(0.45, 0.43, 0.4, 0.6), 1.5, 0.08, 0.45, 2.0, Vector3(0, -0.5, 0), false)
	_emitters["spark"] = _make_emitter(8, 0.35, Color(3.0, 2.0, 1.0, 1.0), 6.0, 0.03, 0.01, 1.0, Vector3(0, -12, 0), true)
	_emitters["blood"] = _make_emitter(10, 0.5, Color(0.32, 0.02, 0.02, 0.85), 2.5, 0.07, 0.3, 3.0, Vector3(0, -4, 0), false)
	_emitters["fire"] = _make_emitter(40, 0.45, Color(4.0, 2.0, 0.6, 1.0), 9.0, 0.8, 0.2, 3.0, Vector3.ZERO, true)
	_emitters["smoke"] = _make_emitter(26, 2.6, Color(0.12, 0.115, 0.11, 0.9), 3.0, 1.2, 4.0, 1.2, Vector3(0, 0.4, 0), false)
	_emitters["puff"] = _make_emitter(5, 1.6, Color(0.55, 0.55, 0.55, 0.3), 0.35, 0.04, 0.22, 1.5, Vector3(0, 0.25, 0), false)
	_emitters["glass"] = _make_emitter(24, 0.8, Color(2.5, 2.4, 2.2, 1.0), 4.0, 0.03, 0.02, 0.5, Vector3(0, -9.8, 0), true)


func _additive_sprite_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _flash_tex
	m.albedo_color = Color(1.0, 0.85, 0.6)
	return m


func _radial(size: int, stops: Array) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			var d := clampf(Vector2(x - c, y - c).length() / c, 0.0, 1.0)
			var f := d * (stops.size() - 1)
			var i := mini(int(f), stops.size() - 2)
			img.set_pixel(x, y, (stops[i] as Color).lerp(stops[i + 1], f - i))
	return ImageTexture.create_from_image(img)


func _star(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			var v := Vector2(x - c, y - c)
			var r := v.length() / c
			var a := atan2(v.y, v.x)
			var spikes := 0.55 + 0.45 * pow(absf(cos(a * 3.0)), 6.0)
			var k := clampf(1.0 - r / spikes, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.85 + 0.15 * k, 0.6 + 0.4 * k, k * k))
	return ImageTexture.create_from_image(img)


func _make_emitter(count: int, life: float, color: Color, speed: float, size0: float, size1: float, drag: float, gravity: Vector3, additive: bool) -> Array[GPUParticles3D]:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed
	pm.gravity = gravity
	pm.damping_min = drag
	pm.damping_max = drag
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, size1 / maxf(size0, 0.001)))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, color.a))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _radial(32, [Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var quad := QuadMesh.new()
	quad.size = Vector2(size0, size0)
	quad.material = mat
	var pool: Array[GPUParticles3D] = []
	for i in 6:
		var p := GPUParticles3D.new()
		p.amount = count
		p.lifetime = life
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.process_material = pm
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		add_child(p)
		pool.append(p)
	return pool


func burst(kind: String, pos: Vector3, normal := Vector3.UP) -> void:
	var pool: Array = _emitters[kind]
	var best: GPUParticles3D = pool[0]
	for p: GPUParticles3D in pool:
		if not p.emitting:
			best = p
			break
	var up := normal.normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(up).normalized()
	best.global_transform = Transform3D(Basis(x, up, x.cross(up)), pos)
	best.restart()


func hole(pos: Vector3, normal: Vector3, scale := 1.0, scorch := false) -> void:
	var d := _decals[_di]
	_di = (_di + 1) % DECALS
	var up := normal.normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(up).normalized().rotated(up, randf() * TAU)
	d.global_transform = Transform3D(Basis(x, up, x.cross(up)), pos)
	d.size = Vector3(0.11, 0.1, 0.11) * scale
	d.texture_albedo = _scorch_tex if scorch else _hole_tex
	d.visible = true


func tracer(from: Vector3, to: Vector3) -> void:
	var t := _tracers[_ti]
	_ti = (_ti + 1) % TRACERS
	t.from = from
	t.len = from.distance_to(to)
	t.dir = (to - from) / maxf(t.len, 0.001)
	t.s = 0.0
	t.on = true


func flash_light(pos: Vector3, color: Color, energy: float, dur: float, rng := 10.0) -> void:
	var best: Dictionary = _lights[0]
	for l: Dictionary in _lights:
		if l.t <= 0.0:
			best = l
			break
	var light: OmniLight3D = best.light
	light.global_position = pos
	light.light_color = color
	light.omni_range = rng
	light.visible = true
	best.t = dur
	best.dur = dur
	best.e = energy


func muzzle(pos: Vector3, size := 0.6) -> void:
	var s := _sprites[_si]
	_si = (_si + 1) % SPRITES
	var spr: Sprite3D = s.sprite
	spr.global_position = pos
	spr.pixel_size = 0.005 * size * randf_range(0.8, 1.2)
	spr.rotation.z = randf() * TAU
	spr.visible = true
	s.t = 0.05


func explosion(pos: Vector3) -> void:
	burst("fire", pos)
	burst("spark", pos)
	burst("smoke", pos)
	flash_light(pos, Color("ffa050"), 12.0, 0.35, 26.0)


func _process(delta: float) -> void:
	for t: Dictionary in _tracers:
		if not t.on:
			continue
		var mi: MeshInstance3D = t.mesh
		t.s += 260.0 * delta
		if t.s - 4.0 > t.len:
			t.on = false
			mi.visible = false
			continue
		var head: float = minf(t.s, t.len)
		var tail: float = maxf(0.0, t.s - 4.0)
		var mid: Vector3 = t.from + t.dir * (head + tail) * 0.5
		mi.visible = head - tail > 0.05
		if mi.visible:
			mi.global_position = mid
			mi.look_at(mid + t.dir, Vector3.UP if absf((t.dir as Vector3).y) < 0.99 else Vector3.RIGHT)
			mi.scale = Vector3(1, 1, (head - tail) / 4.0)
	for l: Dictionary in _lights:
		if l.t > 0.0:
			l.t -= delta
			var light: OmniLight3D = l.light
			light.light_energy = l.e * maxf(0.0, l.t / l.dur)
			if l.t <= 0.0:
				light.visible = false
	for s: Dictionary in _sprites:
		if s.t > 0.0:
			s.t -= delta
			if s.t <= 0.0:
				(s.sprite as Sprite3D).visible = false


func clear() -> void:
	for d in _decals:
		d.visible = false
