class_name ViewModel
extends Node3D
## First-person weapon models, built from primitives. Materials use Godot's viewmodel FOV
## override and depth squash so the gun never clips into walls.

const VM_FOV := 54.0

var models: Dictionary = {}
var flash: MeshInstance3D
var flash_t := 0.0
var light: OmniLight3D
var gadget: MeshInstance3D
var sway := Vector2.ZERO
var recoil := 0.0
var recoil_rot := 0.0
var sprint_k := 0.0

var _mats: Dictionary = {}


func _mat(key: String, color: Color, rough := 0.7, metal := 0.0, emissive := false) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.use_fov_override = true
	m.fov_override = VM_FOV
	m.use_z_clip_scale = true
	m.z_clip_scale = 0.2
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot := Vector3(PI / 2, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	parent.add_child(mi)
	return mi


func _ready() -> void:
	var poly := _mat("poly", Color("1e1f22"), 0.65, 0.2)
	var steel := _mat("steel", Color("34363a"), 0.4, 0.8)
	var tan := _mat("tan", Color("6b5d45"), 0.8)
	var od := _mat("od", Color("3e4434"), 0.75)
	var glove := _mat("glove", Color("181818"), 0.9)
	var sleeve := _mat("sleeve", Color("2c3328"), 0.95)
	var dot := _mat("dot", Color(3.0, 0.3, 0.2), 1.0, 0.0, true)

	var hands := func(parent: Node3D, fx: float, fz: float) -> void:
		_box(parent, Vector3(0.05, 0.045, 0.1), glove, Vector3(-0.012, -0.11, fz))
		_box(parent, Vector3(0.065, 0.065, 0.32), sleeve, Vector3(-0.08, -0.17, fz + 0.15), Vector3(0.25, 0.35, 0))
		_box(parent, Vector3(0.045, 0.06, 0.07), glove, Vector3(0.01, -0.13, fx))
		_box(parent, Vector3(0.07, 0.07, 0.3), sleeve, Vector3(0.07, -0.18, fx + 0.14), Vector3(-0.2, -0.3, 0))
	var reddot := func(parent: Node3D, z: float) -> void:
		_box(parent, Vector3(0.03, 0.016, 0.07), poly, Vector3(0, -0.03, z))
		_box(parent, Vector3(0.006, 0.04, 0.05), poly, Vector3(-0.021, -0.005, z))
		_box(parent, Vector3(0.006, 0.04, 0.05), poly, Vector3(0.021, -0.005, z))
		_box(parent, Vector3(0.048, 0.006, 0.05), poly, Vector3(0, 0.018, z))
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0022
		sm.height = 0.0044
		d.mesh = sm
		d.material_override = dot
		d.position = Vector3(0, 0, z - 0.02)
		d.layers = 2
		parent.add_child(d)

	var carbine := Node3D.new()
	_box(carbine, Vector3(0.05, 0.07, 0.3), poly, Vector3(0, -0.068, 0.02))
	_box(carbine, Vector3(0.056, 0.062, 0.25), tan, Vector3(0, -0.064, -0.25))
	for i in 4:
		_box(carbine, Vector3(0.06, 0.008, 0.03), poly, Vector3(0, -0.03, -0.17 - i * 0.05))
	_cyl(carbine, 0.011, 0.16, steel, Vector3(0, -0.058, -0.45))
	_cyl(carbine, 0.016, 0.05, steel, Vector3(0, -0.058, -0.53))
	var cmag := _box(carbine, Vector3(0.034, 0.15, 0.07), poly, Vector3(0, -0.16, -0.05), Vector3(0.22, 0, 0))
	_box(carbine, Vector3(0.032, 0.095, 0.04), poly, Vector3(0, -0.14, 0.1), Vector3(-0.35, 0, 0))
	_box(carbine, Vector3(0.04, 0.07, 0.22), tan, Vector3(0, -0.075, 0.27))
	reddot.call(carbine, 0.0)
	hands.call(carbine, 0.08, -0.25)
	carbine.set_meta("info", {"mag": cmag, "mag_y": cmag.position.y, "muzzle": Vector3(0, -0.058, -0.56), "ads": Vector3(0, 0, -0.17), "hip": Vector3(0.19, -0.16, -0.4)})

	var smg := Node3D.new()
	_box(smg, Vector3(0.05, 0.07, 0.22), poly, Vector3(0, -0.066, 0.0))
	_box(smg, Vector3(0.05, 0.05, 0.1), od, Vector3(0, -0.064, -0.15))
	_cyl(smg, 0.024, 0.25, steel, Vector3(0, -0.058, -0.32))
	var smag := _box(smg, Vector3(0.03, 0.17, 0.045), poly, Vector3(0, -0.17, -0.06))
	_box(smg, Vector3(0.032, 0.09, 0.04), poly, Vector3(0, -0.13, 0.07), Vector3(-0.3, 0, 0))
	_box(smg, Vector3(0.012, 0.05, 0.2), steel, Vector3(0.018, -0.075, 0.2))
	_box(smg, Vector3(0.012, 0.05, 0.2), steel, Vector3(-0.018, -0.075, 0.2))
	reddot.call(smg, 0.02)
	hands.call(smg, 0.07, -0.16)
	smg.set_meta("info", {"mag": smag, "mag_y": smag.position.y, "muzzle": Vector3(0, -0.058, -0.46), "ads": Vector3(0, 0, -0.19), "hip": Vector3(0.18, -0.15, -0.37)})

	var dmr := Node3D.new()
	_box(dmr, Vector3(0.05, 0.08, 0.34), steel, Vector3(0, -0.078, 0.02))
	_box(dmr, Vector3(0.046, 0.09, 0.3), od, Vector3(0, -0.088, 0.3))
	_box(dmr, Vector3(0.056, 0.064, 0.3), od, Vector3(0, -0.072, -0.29))
	_cyl(dmr, 0.012, 0.32, steel, Vector3(0, -0.066, -0.58))
	_cyl(dmr, 0.019, 0.06, steel, Vector3(0, -0.066, -0.75))
	var dmag := _box(dmr, Vector3(0.042, 0.11, 0.075), poly, Vector3(0, -0.15, -0.02), Vector3(0.1, 0, 0))
	_box(dmr, Vector3(0.032, 0.095, 0.04), poly, Vector3(0, -0.14, 0.11), Vector3(-0.35, 0, 0))
	_cyl(dmr, 0.019, 0.26, poly, Vector3(0, 0, 0))
	_cyl(dmr, 0.028, 0.07, poly, Vector3(0, 0, -0.16))
	_cyl(dmr, 0.024, 0.05, poly, Vector3(0, 0, 0.14))
	_box(dmr, Vector3(0.03, 0.03, 0.02), steel, Vector3(0, -0.03, -0.07))
	_box(dmr, Vector3(0.03, 0.03, 0.02), steel, Vector3(0, -0.03, 0.07))
	hands.call(dmr, 0.09, -0.3)
	dmr.set_meta("info", {"mag": dmag, "mag_y": dmag.position.y, "muzzle": Vector3(0, -0.066, -0.79), "ads": Vector3(0, 0, -0.26), "hip": Vector3(0.19, -0.16, -0.43)})

	var pistol := Node3D.new()
	_box(pistol, Vector3(0.03, 0.03, 0.17), steel, Vector3(0, -0.022, -0.06))
	_box(pistol, Vector3(0.028, 0.025, 0.15), poly, Vector3(0, -0.048, -0.055))
	_box(pistol, Vector3(0.028, 0.1, 0.045), poly, Vector3(0, -0.1, 0.0), Vector3(-0.25, 0, 0))
	var pmag := _box(pistol, Vector3(0.022, 0.08, 0.035), steel, Vector3(0, -0.12, 0.005), Vector3(-0.25, 0, 0))
	_cyl(pistol, 0.015, 0.13, poly, Vector3(0, -0.022, -0.21))
	_box(pistol, Vector3(0.004, 0.008, 0.004), dot, Vector3(0, -0.003, -0.13))
	_box(pistol, Vector3(0.008, 0.009, 0.004), steel, Vector3(-0.008, -0.003, 0.02))
	_box(pistol, Vector3(0.008, 0.009, 0.004), steel, Vector3(0.008, -0.003, 0.02))
	_box(pistol, Vector3(0.05, 0.07, 0.07), glove, Vector3(0, -0.1, 0.02))
	_box(pistol, Vector3(0.07, 0.07, 0.3), sleeve, Vector3(0.02, -0.15, 0.18), Vector3(-0.4, -0.1, 0))
	_box(pistol, Vector3(0.05, 0.06, 0.06), glove, Vector3(-0.03, -0.1, 0.0), Vector3(0, 0.3, 0))
	pistol.set_meta("info", {"mag": pmag, "mag_y": pmag.position.y, "muzzle": Vector3(0, -0.022, -0.28), "ads": Vector3(0, 0, -0.3), "hip": Vector3(0.16, -0.14, -0.38)})

	var wood := _mat("wood", Color("5a3a22"), 0.7)
	var ar7 := Node3D.new()
	_box(ar7, Vector3(0.052, 0.075, 0.3), steel, Vector3(0, -0.07, 0.02))
	_box(ar7, Vector3(0.058, 0.06, 0.22), wood, Vector3(0, -0.066, -0.24))
	_cyl(ar7, 0.012, 0.22, steel, Vector3(0, -0.058, -0.45))
	_box(ar7, Vector3(0.008, 0.03, 0.008), steel, Vector3(0, -0.035, -0.53))
	var amag := _box(ar7, Vector3(0.034, 0.16, 0.06), steel, Vector3(0, -0.17, -0.06), Vector3(0.35, 0, 0))
	_box(ar7, Vector3(0.032, 0.095, 0.04), wood, Vector3(0, -0.14, 0.1), Vector3(-0.35, 0, 0))
	_box(ar7, Vector3(0.042, 0.08, 0.24), wood, Vector3(0, -0.085, 0.28))
	_box(ar7, Vector3(0.016, 0.02, 0.02), steel, Vector3(0, -0.02, 0.06))
	hands.call(ar7, 0.08, -0.24)
	ar7.set_meta("info", {"mag": amag, "mag_y": amag.position.y, "muzzle": Vector3(0, -0.058, -0.57), "ads": Vector3(0, 0.03, -0.2), "hip": Vector3(0.19, -0.16, -0.4)})

	var lmg := Node3D.new()
	_box(lmg, Vector3(0.07, 0.1, 0.36), poly, Vector3(0, -0.08, 0.0))
	_box(lmg, Vector3(0.075, 0.03, 0.3), steel, Vector3(0, -0.02, -0.02))
	_cyl(lmg, 0.016, 0.36, steel, Vector3(0, -0.07, -0.42))
	_cyl(lmg, 0.022, 0.05, steel, Vector3(0, -0.07, -0.62))
	var lbox := _box(lmg, Vector3(0.06, 0.12, 0.14), od, Vector3(-0.04, -0.17, -0.04))
	_box(lmg, Vector3(0.035, 0.1, 0.045), poly, Vector3(0, -0.15, 0.12), Vector3(-0.3, 0, 0))
	_box(lmg, Vector3(0.05, 0.09, 0.24), poly, Vector3(0, -0.09, 0.3))
	_box(lmg, Vector3(0.012, 0.18, 0.012), steel, Vector3(0.03, -0.16, -0.5), Vector3(0.3, 0, 0.2))
	_box(lmg, Vector3(0.012, 0.18, 0.012), steel, Vector3(-0.03, -0.16, -0.5), Vector3(0.3, 0, -0.2))
	reddot.call(lmg, 0.04)
	hands.call(lmg, 0.1, -0.28)
	lmg.set_meta("info", {"mag": lbox, "mag_y": lbox.position.y, "muzzle": Vector3(0, -0.07, -0.66), "ads": Vector3(0, 0, -0.21), "hip": Vector3(0.2, -0.18, -0.42)})

	var shotgun := Node3D.new()
	_box(shotgun, Vector3(0.05, 0.07, 0.24), steel, Vector3(0, -0.068, 0.02))
	_cyl(shotgun, 0.015, 0.5, steel, Vector3(0, -0.05, -0.33))
	_cyl(shotgun, 0.013, 0.42, poly, Vector3(0, -0.082, -0.29))
	var pump := _box(shotgun, Vector3(0.05, 0.05, 0.14), poly, Vector3(0, -0.082, -0.25))
	_box(shotgun, Vector3(0.032, 0.095, 0.04), poly, Vector3(0, -0.13, 0.1), Vector3(-0.35, 0, 0))
	_box(shotgun, Vector3(0.042, 0.075, 0.24), poly, Vector3(0, -0.08, 0.27))
	_box(shotgun, Vector3(0.006, 0.012, 0.006), dot, Vector3(0, -0.032, -0.57))
	hands.call(shotgun, 0.08, -0.25)
	shotgun.set_meta("info", {"mag": pump, "mag_y": pump.position.y, "muzzle": Vector3(0, -0.05, -0.6), "ads": Vector3(0, 0.035, -0.25), "hip": Vector3(0.19, -0.16, -0.4)})

	models = {"carbine": carbine, "smg": smg, "dmr": dmr, "pistol": pistol, "ar7": ar7, "lmg": lmg, "shotgun": shotgun}
	for m: Node3D in models.values():
		m.visible = false
		add_child(m)

	gadget = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.03
	gm.bottom_radius = 0.03
	gm.height = 0.09
	gadget.mesh = gm
	gadget.material_override = _mat("gadget", Color("3a4a30"), 0.7)
	gadget.visible = false
	gadget.layers = 2
	get_parent().add_child.call_deferred(gadget)
	var fill := OmniLight3D.new()
	fill.light_cull_mask = 2
	fill.light_energy = 0.7
	fill.omni_range = 2.5
	fill.light_color = Color("c8d4ff")
	fill.position = Vector3(-0.4, 0.3, 0.2)
	get_parent().add_child.call_deferred(fill)

	flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.8, 0.5)
	fm.use_fov_override = true
	fm.fov_override = VM_FOV
	fm.use_z_clip_scale = true
	fm.z_clip_scale = 0.2
	flash.material_override = fm
	flash.visible = false
	flash.layers = 2
	add_child(flash)

	light = OmniLight3D.new()
	light.light_energy = 0.0
	light.omni_range = 4.0
	light.light_color = Color("ffb060")
	light.position = Vector3(0.1, -0.05, -0.6)
	get_parent().add_child.call_deferred(light)


func show_weapon(id: String) -> void:
	for k: String in models:
		(models[k] as Node3D).visible = k == id


func set_gadget_color(c: Color) -> void:
	(gadget.material_override as StandardMaterial3D).albedo_color = c


func fire_kick(strong: float, suppressed: bool) -> void:
	recoil = minf(0.07, recoil + 0.02 * strong)
	recoil_rot = minf(0.14, recoil_rot + 0.04 * strong)
	if not suppressed:
		flash_t = 0.04
		flash.visible = true
		flash.rotation.z = randf() * TAU
		light.light_energy = 3.0
	else:
		light.light_energy = 0.4


## p: the player; w: current weapon data; state: weapon manager.
func animate(dt: float, p: Player, w: WeaponData, st: Weapons) -> void:
	sway *= exp(-dt * 10.0)
	recoil *= exp(-dt * 14.0)
	recoil_rot *= exp(-dt * 12.0)
	var m: Node3D = models[w.id]
	var info: Dictionary = m.get_meta("info")
	var bob := p.bob * (1.0 - p.ads * 0.85)
	var ph := p.step_phase * PI
	var lower := 0.0
	if st.switch_t > 0.0:
		lower = sin((1.0 - st.switch_t / 0.45) * PI) * 0.3
	if st.aiming_throw:
		lower = maxf(lower, 0.22)
	if st.throw_t > 0.0:
		lower = maxf(lower, sin(st.throw_t / 0.45 * PI) * 0.25)
	if p.drag_body:
		lower = maxf(lower, 0.4)
	if p.vault_t >= 0.0:
		lower = maxf(lower, 0.3)
	sprint_k = lerpf(sprint_k, 1.0 if p.sprinting else 0.0, minf(1.0, dt * 8.0))
	var reload_k := 0.0
	if st.reload_t > 0.0:
		reload_k = sin((1.0 - st.reload_t / st.reload_dur) * PI)
	var base: Vector3 = (info.hip as Vector3).lerp(info.ads, p.ads)
	var keep := 1.0 - p.ads * 0.7
	position = Vector3(
		base.x + sin(ph) * 0.012 * bob - clampf(sway.x, -0.04, 0.04) * keep + sprint_k * 0.05,
		base.y - absf(cos(ph)) * 0.01 * bob + clampf(sway.y, -0.03, 0.03) * keep - lower - p.land * 0.2 - sprint_k * 0.04 - reload_k * 0.05,
		base.z + recoil)
	rotation = Vector3(
		recoil_rot * (1.0 - p.ads * 0.5) + clampf(sway.y, -0.08, 0.08) * 0.4 - sprint_k * 0.35 + reload_k * 0.25,
		(1.0 - p.ads) * 0.03 - clampf(sway.x, -0.08, 0.08) * 0.5 + sprint_k * 0.6,
		sprint_k * 0.3 + reload_k * 0.45 - p.lean_k * 0.05)
	var mag: MeshInstance3D = info.mag
	var k := 0.0
	if st.reload_t > 0.0:
		k = 1.0 - st.reload_t / st.reload_dur
	var out := sin((k - 0.15) / 0.45 * PI) if k > 0.15 and k < 0.6 else 0.0
	mag.position.y = float(info.mag_y) - out * 0.25
	mag.visible = not (k > 0.3 and k < 0.45)
	gadget.visible = st.aiming_throw or st.throw_t > 0.3
	gadget.position = Vector3(-0.17, -0.15 if st.aiming_throw else -0.1, -0.4 if st.aiming_throw else -0.5)
	if flash_t > 0.0:
		flash_t -= dt
		flash.position = info.muzzle
		if flash_t <= 0.0:
			flash.visible = false
	light.light_energy *= exp(-dt * 35.0)
	visible = p.alive and not p.is_scoped()
