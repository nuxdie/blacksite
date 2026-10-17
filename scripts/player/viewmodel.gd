class_name ViewModel
extends Node3D
## Animates the first-person weapon: hip and aimed poses, sway, recoil, the bolt or slide cycling,
## reloads with the support hand, ejected brass, muzzle flash, and pulling the gun in near walls.
## Models come from GunModels; aiming puts each weapon's own sight line through the eye.

const CASES := 10

var kit := GunModels.new()
var rigs: Dictionary = {}
var flash: Node3D
var flash_t := 0.0
var light: OmniLight3D
var gadget: MeshInstance3D
var sway := Vector2.ZERO
var recoil := 0.0
var recoil_rot := 0.0
var sprint_k := 0.0
var wall_k := 0.0
## 0..1 progress of the action cycling after a shot (bolt carrier, slide, pump).
var cycle_t := 1.0
var _cycle_len := 0.1
var _cases: Array[Dictionary] = []
var _ci := 0
var _rest: Dictionary = {}
var _lean_roll := 0.0
var _move_tilt := 0.0


func _ready() -> void:
	for id: String in ["carbine", "smg", "dmr", "pistol", "ar7", "lmg", "shotgun"]:
		var rig := kit.build(id)
		var root: Node3D = rig.root
		root.visible = false
		add_child(root)
		rigs[id] = rig
		_rest[id] = {"mag": (rig.mag as Node3D).transform, "bolt": (rig.bolt as Node3D).position, "lhand": (rig.lhand as Node3D).position}
	_build_flash()
	_build_cases()
	gadget = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.03
	gm.bottom_radius = 0.03
	gm.height = 0.09
	gadget.mesh = gm
	gadget.material_override = kit.mat("od").duplicate()
	gadget.visible = false
	gadget.layers = GunModels.LAYER
	get_parent().add_child.call_deferred(gadget)
	var fill := OmniLight3D.new()
	fill.light_cull_mask = GunModels.LAYER
	fill.light_energy = 0.9
	fill.omni_range = 2.5
	fill.light_color = Color("c8d4ff")
	fill.position = Vector3(-0.4, 0.35, 0.1)
	get_parent().add_child.call_deferred(fill)
	light = OmniLight3D.new()
	light.light_energy = 0.0
	light.omni_range = 5.0
	light.light_color = Color("ffb060")
	light.position = Vector3(0.1, -0.05, -0.7)
	get_parent().add_child.call_deferred(light)


func _build_flash() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	grad.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	grad.add_point(0.25, Color(1.0, 0.75, 0.35, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = tex
	fm.albedo_color = Color(2.0, 1.6, 1.2)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.use_fov_override = true
	fm.fov_override = GunModels.VM_FOV
	fm.use_z_clip_scale = true
	fm.z_clip_scale = 0.2
	flash = Node3D.new()
	flash.visible = false
	add_child(flash)
	# a disc facing the eye plus two crossed petals that read from the side
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.13, 0.13) if i == 0 else Vector2(0.07, 0.2)
		q.mesh = qm
		q.material_override = fm
		q.layers = GunModels.LAYER
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i > 0:
			q.rotation = Vector3(PI / 2, 0, 0) if i == 1 else Vector3(PI / 2, 0, PI / 2)
			q.position.z = -0.07
		flash.add_child(q)


func _build_cases() -> void:
	var looks := {
		"rifle": [Vector3(0.009, 0.009, 0.045), kit.mat("brass")],
		"steel": [Vector3(0.0095, 0.0095, 0.039), kit.mat("lacquer")],
		"pistol": [Vector3(0.0095, 0.0095, 0.019), kit.mat("brass")],
		"shell": [Vector3(0.021, 0.021, 0.065), kit.mat("hull")],
	}
	for i in CASES:
		var parts := {}
		for k: String in looks:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = looks[k][0]
			mi.mesh = bm
			mi.material_override = looks[k][1]
			mi.layers = GunModels.LAYER
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			add_child(mi)
			parts[k] = mi
		_cases.append({"parts": parts, "t": 0.0, "v": Vector3.ZERO, "spin": Vector3.ZERO, "node": null})


func show_weapon(id: String) -> void:
	for k: String in rigs:
		(rigs[k].root as Node3D).visible = k == id
	cycle_t = 1.0


func set_gadget_color(c: Color) -> void:
	(gadget.material_override as StandardMaterial3D).albedo_color = c


func fire_kick(strong: float, suppressed: bool, w: WeaponData = null) -> void:
	recoil = minf(0.07, recoil + 0.02 * strong)
	recoil_rot = minf(0.14, recoil_rot + 0.04 * strong)
	if w:
		var rig: Dictionary = rigs[w.id]
		_cycle_len = clampf(60.0 / w.rpm * 0.8, 0.05, 0.12)
		cycle_t = 0.0
		if not rig.get("pump", false):
			_eject(rig)
	if not suppressed:
		flash_t = 0.045
		flash.visible = true
		flash.rotation.z = randf() * TAU
		flash.scale = Vector3.ONE * randf_range(0.8, 1.25) * (1.5 if w and w.pellets > 1 else 1.0)
		light.light_energy = 3.0
	else:
		light.light_energy = 0.3


## Throws a spent case out of the ejection port, right and slightly back.
func _eject(rig: Dictionary) -> void:
	var c: Dictionary = _cases[_ci]
	_ci = (_ci + 1) % CASES
	for k: String in c.parts:
		(c.parts[k] as Node3D).visible = false
	var node: MeshInstance3D = c.parts[rig.case]
	node.visible = true
	node.position = rig.eject
	node.rotation = Vector3(0, randf() * 0.4, 0)
	c.node = node
	c.t = 0.6
	c.v = Vector3(randf_range(1.4, 2.0), randf_range(0.9, 1.5), randf_range(0.2, 0.6))
	c.spin = Vector3(randf_range(-20, 20), randf_range(10, 25), randf_range(-8, 8))


func eject_shell() -> void:
	_eject({"case": "shell", "eject": Vector3(0.02, -0.004, -0.04)})


func _tick_cases(dt: float) -> void:
	for c in _cases:
		if c.t <= 0.0:
			continue
		c.t -= dt
		c.v += Vector3(0, -9.0, 0) * dt
		var n: Node3D = c.node
		n.position += c.v * dt
		n.rotation += c.spin * dt
		if c.t <= 0.0:
			n.visible = false


static func _win(k: float, a: float, b: float) -> float:
	return smoothstep(a, b, k)


## Parent space of a part that hangs off the gun root (or off another part, like the pump).
static func _local(node: Node3D, root: Node3D, p: Vector3) -> Vector3:
	var par := node.get_parent() as Node3D
	return p if par == root else par.transform.affine_inverse() * p


## p: the player; w: current weapon data; st: weapon manager.
func animate(dt: float, p: Player, w: WeaponData, st: Weapons) -> void:
	sway *= exp(-dt * 10.0)
	recoil *= exp(-dt * 14.0)
	recoil_rot *= exp(-dt * 12.0)
	cycle_t = minf(1.0, cycle_t + dt / _cycle_len)
	_tick_cases(dt)
	var rig: Dictionary = rigs[w.id]
	var root: Node3D = rig.root
	var rest: Dictionary = _rest[w.id]
	var ads := smoothstep(0.0, 1.0, p.ads)
	var t := Time.get_ticks_msec() / 1000.0

	var lower := 0.0
	if st.switch_t > 0.0:
		lower = sin((1.0 - st.switch_t / Weapons.SWITCH_TIME) * PI) * 0.3
	if st.aiming_throw:
		lower = maxf(lower, 0.22)
	if st.throw_t > 0.0:
		lower = maxf(lower, sin(st.throw_t / 0.45 * PI) * 0.25)
	if p.drag_body:
		lower = maxf(lower, 0.4)
	if p.hacking or p.in_tablet:
		lower = maxf(lower, 0.32)
	if p.vault_t >= 0.0:
		lower = maxf(lower, 0.3)
	sprint_k = lerpf(sprint_k, 1.0 if p.sprinting else 0.0, minf(1.0, dt * 8.0))
	wall_k = lerpf(wall_k, _wall_block(p), minf(1.0, dt * 10.0))
	var lateral := p.right().dot(p.velocity) / Player.WALK
	_move_tilt = lerpf(_move_tilt, clampf(lateral, -1.0, 1.0), minf(1.0, dt * 6.0))
	_lean_roll = lerpf(_lean_roll, p.lean_k, minf(1.0, dt * 8.0))

	# reload: cant the gun, swap the magazine with the support hand, run the bolt if it was empty
	var k := 0.0
	var reloading := st.reload_t > 0.0 and not st.tube_loading
	if reloading:
		k = 1.0 - st.reload_t / st.reload_dur
	var tilt := 0.0
	var mag: Node3D = rig.mag
	var lh: Node3D = rig.lhand
	var bolt: Node3D = rig.bolt
	var mag_rest: Transform3D = rest.mag
	var lh_rest: Vector3 = rest.lhand
	var bolt_rest: Vector3 = rest.bolt
	var travel: Vector3 = rig.bolt_travel
	var lh_target := lh_rest
	mag.transform = mag_rest
	mag.visible = not rig.get("pump", false)
	var bolt_k := 0.0
	if reloading:
		tilt = _win(k, 0.0, 0.12) * (1.0 - _win(k, 0.86, 1.0))
		var down := mag_rest.basis.y.normalized()
		var drop := _win(k, 0.1, 0.3)
		var rise := 1.0 - _win(k, 0.32, 0.56)
		var off := 0.0
		if k < 0.31:
			off = drop * 0.3
			mag.visible = k < 0.29
		else:
			off = rise * 0.22
		mag.position = mag_rest.origin - down * off
		var at_mag := _local(lh, root, mag.position - down * 0.06 + Vector3(-0.025, 0, 0))
		var pouch := _local(lh, root, Vector3(-0.12, -0.3, 0.05))
		if k < 0.08:
			lh_target = lh_rest.lerp(at_mag, _win(k, 0.0, 0.08))
		elif k < 0.3:
			lh_target = at_mag.lerp(pouch, _win(k, 0.12, 0.3))
		elif k < 0.6:
			lh_target = pouch.lerp(at_mag, _win(k, 0.3, 0.52))
		else:
			lh_target = at_mag.lerp(lh_rest, _win(k, 0.6, 0.72))
		var empty := st.reload_dur > w.reload_time
		if empty:
			var handle := _local(lh, root, bolt_rest + Vector3(-0.03, 0.0, 0.0) if bolt.get_parent() == root else bolt_rest)
			if k > 0.62 and k < 0.92:
				var to_h := _win(k, 0.62, 0.72) * (1.0 - _win(k, 0.84, 0.92))
				lh_target = lh_target.lerp(handle + travel * _win(k, 0.74, 0.8) * (1.0 - _win(k, 0.8, 0.84)), to_h)
			bolt_k = _win(k, 0.74, 0.8) * (1.0 - _win(k, 0.8, 0.84))
			if rig.get("slide_lock", false):
				bolt_k = 1.0 - _win(k, 0.78, 0.82)
		if rig.has("cover"):
			(rig.cover as Node3D).rotation.x = _win(k, 0.08, 0.2) * (1.0 - _win(k, 0.7, 0.82)) * 1.2
	elif rig.has("cover"):
		(rig.cover as Node3D).rotation.x = 0.0
	if st.tube_loading and st.reload_t > 0.0:
		var sk := 1.0 - st.reload_t / st.reload_dur
		tilt = 0.6
		var port := _local(lh, root, Vector3(0, -0.06, -0.04))
		var belt := _local(lh, root, Vector3(-0.1, -0.24, 0.02))
		lh_target = belt.lerp(port, _win(sk, 0.15, 0.7)) if sk < 0.75 else port.lerp(lh_rest, _win(sk, 0.8, 1.0))
		mag.visible = sk > 0.2 and sk < 0.78
		mag.position = Vector3(0, -0.06, -0.05) + Vector3(-0.02, -0.18, 0.06) * (1.0 - _win(sk, 0.2, 0.7))
	# the action: bolt or slide cycling after a shot, the pump being worked, the slide locked open
	if rig.cycles and cycle_t < 1.0:
		bolt_k = maxf(bolt_k, sin(cycle_t * PI))
	if rig.get("pump", false) and st.pump_t > 0.0:
		var pk := 1.0 - st.pump_t / Weapons.PUMP_TIME
		bolt_k = sin(clampf(pk, 0.0, 1.0) * PI)
	if rig.get("slide_lock", false) and st.mag[st.cur] == 0 and not reloading:
		bolt_k = 1.0
	bolt.position = bolt_rest + travel * bolt_k
	lh.position = lh.position.lerp(lh_target, minf(1.0, dt * 22.0)) if reloading or st.tube_loading else lh_target

	# pose
	var base: Vector3 = (rig.hip as Vector3).lerp(rig.ads, ads)
	var free := 1.0 - ads * 0.92
	var bob := p.bob * (1.0 - ads * 0.85)
	var ph := p.step_phase * PI
	var breathe := sin(t * 1.6) * 0.0016 * free
	position = Vector3(
		base.x + sin(ph) * 0.011 * bob - clampf(sway.x, -0.04, 0.04) * free * 0.8 + sprint_k * 0.04 - tilt * 0.02,
		base.y - absf(cos(ph)) * 0.009 * bob + clampf(sway.y, -0.03, 0.03) * free + breathe - lower - p.land * 0.2 - sprint_k * 0.05 - tilt * 0.035 - wall_k * 0.03,
		base.z + recoil * (1.0 - ads * 0.4) + wall_k * 0.1)
	rotation = Vector3(
		recoil_rot * (1.0 - ads * 0.65) + clampf(sway.y, -0.08, 0.08) * 0.4 * free - sprint_k * 0.55 + tilt * 0.12 + wall_k * 0.85,
		(1.0 - ads) * 0.04 - clampf(sway.x, -0.08, 0.08) * 0.5 * free + sprint_k * 0.65 - wall_k * 0.25,
		(1.0 - ads) * -0.02 + sprint_k * 0.25 + tilt * 0.55 - _lean_roll * 0.04 - _move_tilt * 0.025 * free)

	gadget.visible = st.aiming_throw or st.throw_t > 0.3
	gadget.position = Vector3(-0.17, -0.15 if st.aiming_throw else -0.1, -0.4 if st.aiming_throw else -0.5)
	if flash_t > 0.0:
		flash_t -= dt
		flash.position = rig.muzzle
		if flash_t <= 0.0:
			flash.visible = false
	light.light_energy *= exp(-dt * 35.0)
	visible = p.alive and not p.is_scoped()


## 0 when the muzzle has room, 1 when a wall is right in front of it.
func _wall_block(p: Player) -> float:
	var o := p.eye_pos()
	var q := PhysicsRayQueryParameters3D.create(o, o + p.view_dir() * 0.8, Layers.WORLD)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	return clampf((0.8 - o.distance_to(hit.position)) / 0.45, 0.0, 1.0)
