class_name SoldierModel
extends Node3D
## Procedural guard body, built so each type reads at a glance by silhouette:
##   rifleman: helmet with night-vision mount, plate carrier, assault pack with a radio antenna, AK.
##   heavy:    bulky armour with shoulder plates, full visor helmet, belt-fed LMG.
##   breacher: soft cap and goggles, light chest rig, shotgun, no pack.
## Poses carry state too: weapon low at rest, shouldered when alert, a hand to the radio when
## they're calling you in.

var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var aim: Node3D
var gun: Node3D
var muzzle: Node3D
var flashlight: SpotLight3D
var legs: Array[Dictionary] = []
var support_arm: Node3D
var radio_arm: Node3D
var aim_pitch := 0.0
var _radio_k := 0.0
var _box_mesh := BoxMesh.new()
var _sph_mesh := SphereMesh.new()
var _cyl_mesh := CylinderMesh.new()

const LOOKS := {
	"rifleman": {"base": Color("6d6a50"), "blotch": Color("4a4a36"), "vest": Color("3f4433"), "camo": 0.55},
	"heavy": {"base": Color("4f555c"), "blotch": Color("3a3f45"), "vest": Color("26292c"), "camo": 0.35},
	"breacher": {"base": Color("6a5644"), "blotch": Color("4d3e31"), "vest": Color("3b3128"), "camo": 0.5},
}


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _cloth(look: Dictionary, base_key := "base") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/cloth.gdshader")
	m.set_shader_parameter("base", look[base_key])
	m.set_shader_parameter("blotch", look.blotch)
	m.set_shader_parameter("amount", look.camo)
	return m


func build(profile: SoldierProfile) -> void:
	_sph_mesh.radius = 1.0
	_sph_mesh.height = 2.0
	_sph_mesh.radial_segments = 16
	_sph_mesh.rings = 8
	_cyl_mesh.top_radius = 1.0
	_cyl_mesh.bottom_radius = 1.0
	_cyl_mesh.height = 1.0
	_cyl_mesh.radial_segments = 10
	var kind := profile.id
	var look: Dictionary = LOOKS.get(kind, LOOKS.rifleman)
	var cloth := _cloth(look)
	var vest := Mats.plain(look.vest, 0.8, 0.05)
	var gear := Mats.plain(Color("1c1d1f"), 0.6, 0.3)
	var metal := Mats.plain(Color("2a2c2f"), 0.4, 0.7)
	var skin := Mats.plain(Color("8a6a55"), 0.75)
	var glove := Mats.plain(Color("232323"), 0.9)
	var boot := Mats.plain(Color("2b2622"), 0.85)
	var lens := Mats.plain(Color("101418"), 0.1, 0.6)
	body = _pivot(self, Vector3.ZERO)
	hips = _pivot(body, Vector3(0, 0.95, 0))
	_part(hips, _box_mesh, vest, Vector3(0, 0.0, 0), Vector3(0.36, 0.08, 0.22))
	for sx: float in [-1.0, 1.0]:
		var th := _pivot(hips, Vector3(sx * 0.11, 0, 0))
		_part(th, _box_mesh, cloth, Vector3(0, -0.22, 0), Vector3(0.16, 0.46, 0.18))
		_part(th, _box_mesh, vest, Vector3(sx * 0.09, -0.2, -0.01), Vector3(0.04, 0.16, 0.12))
		var kn := _pivot(th, Vector3(0, -0.45, 0))
		_part(kn, _box_mesh, cloth, Vector3(0, -0.21, 0), Vector3(0.14, 0.43, 0.15))
		_part(kn, _box_mesh, vest, Vector3(0, -0.02, -0.085), Vector3(0.13, 0.12, 0.04))
		_part(kn, _box_mesh, boot, Vector3(0, -0.45, -0.04), Vector3(0.15, 0.12, 0.28))
		legs.append({"th": th, "kn": kn})
	torso = _pivot(hips, Vector3(0, 0.04, 0))
	_part(torso, _box_mesh, cloth, Vector3(0, 0.15, 0), Vector3(0.34, 0.3, 0.2))
	_part(torso, _box_mesh, cloth, Vector3(0, 0.43, 0), Vector3(0.44, 0.3, 0.24))
	# plate carrier and its pouches
	var bulk := 1.25 if kind == "heavy" else (0.85 if kind == "breacher" else 1.0)
	_part(torso, _box_mesh, vest, Vector3(0, 0.38, -0.01), Vector3(0.42 * bulk, 0.38, 0.3 * bulk))
	var pouches := 4 if kind != "breacher" else 2
	for i in pouches:
		var x := (i - (pouches - 1) * 0.5) * 0.085
		_part(torso, _box_mesh, vest, Vector3(x, 0.26, -0.16 * bulk - 0.02), Vector3(0.075, 0.13, 0.06))
	if kind == "heavy":
		for sx: float in [-1.0, 1.0]:
			_part(torso, _box_mesh, vest, Vector3(sx * 0.29, 0.56, 0), Vector3(0.16, 0.08, 0.3), Vector3(0, 0, sx * -0.35))
		_part(torso, _box_mesh, vest, Vector3(0, 0.08, -0.05), Vector3(0.44, 0.16, 0.32))
		_part(torso, _box_mesh, gear, Vector3(0, 0.36, 0.2), Vector3(0.34, 0.3, 0.1))
	elif kind == "rifleman":
		# assault pack with the radio, antenna up: you can see who carries the net
		_part(torso, _box_mesh, vest, Vector3(0, 0.36, 0.22), Vector3(0.3, 0.36, 0.14))
		_part(torso, _cyl_mesh, gear, Vector3(0.1, 0.78, 0.24), Vector3(0.006, 0.42, 0.006))
	else:
		_part(torso, _box_mesh, gear, Vector3(0.12, 0.2, 0.15), Vector3(0.1, 0.12, 0.06))
		_part(torso, _cyl_mesh, gear, Vector3(-0.17, 0.6, 0.05), Vector3(0.005, 0.2, 0.005))
	# head and headgear
	head = _pivot(torso, Vector3(0, 0.68, -0.01))
	_part(head, _box_mesh, skin, Vector3(0, -0.01, 0), Vector3(0.17, 0.21, 0.19))
	match kind:
		"heavy":
			_part(head, _sph_mesh, gear, Vector3(0, 0.05, 0.01), Vector3(0.155, 0.15, 0.17))
			_part(head, _box_mesh, lens, Vector3(0, 0.0, -0.105), Vector3(0.2, 0.16, 0.03))
			_part(head, _box_mesh, gear, Vector3(0, -0.09, -0.08), Vector3(0.2, 0.07, 0.08))
		"breacher":
			_part(head, _box_mesh, Mats.plain(Color("26231f"), 0.95), Vector3(0, -0.03, 0), Vector3(0.18, 0.18, 0.2))
			_part(head, _sph_mesh, _cloth(look, "vest"), Vector3(0, 0.08, 0.01), Vector3(0.11, 0.07, 0.115))
			_part(head, _box_mesh, gear, Vector3(0, 0.1, -0.1), Vector3(0.13, 0.025, 0.06))
			_part(head, _box_mesh, lens, Vector3(0, 0.035, -0.1), Vector3(0.16, 0.05, 0.03))
		_:
			_part(head, _sph_mesh, Mats.plain(look.vest, 0.75), Vector3(0, 0.065, 0.01), Vector3(0.135, 0.12, 0.145))
			_part(head, _box_mesh, _cloth(look, "blotch"), Vector3(0, -0.06, -0.02), Vector3(0.175, 0.1, 0.17))
			_part(head, _box_mesh, gear, Vector3(0, 0.15, -0.11), Vector3(0.05, 0.04, 0.04))
			_part(head, _box_mesh, gear, Vector3(0, 0.115, -0.15), Vector3(0.07, 0.05, 0.07))
			for sx: float in [-1.0, 1.0]:
				_part(head, _box_mesh, gear, Vector3(sx * 0.13, 0.05, 0.0), Vector3(0.02, 0.03, 0.1))
	# arms and weapon on the aiming pivot
	aim = _pivot(torso, Vector3(0, 0.52, 0))
	_part(aim, _box_mesh, cloth, Vector3(0.2, -0.08, -0.03), Vector3(0.11, 0.12, 0.26), Vector3(-0.5, 0, 0))
	_part(aim, _box_mesh, cloth, Vector3(0.16, -0.17, -0.2), Vector3(0.09, 0.09, 0.22), Vector3(0.3, 0.3, 0))
	_part(aim, _box_mesh, glove, Vector3(0.1, -0.15, -0.3), Vector3(0.07, 0.08, 0.08))
	support_arm = _pivot(aim, Vector3.ZERO)
	_part(support_arm, _box_mesh, cloth, Vector3(-0.19, -0.1, -0.08), Vector3(0.11, 0.12, 0.28), Vector3(-0.5, -0.3, 0))
	_part(support_arm, _box_mesh, cloth, Vector3(-0.1, -0.14, -0.33), Vector3(0.09, 0.09, 0.24), Vector3(0.1, 0.45, 0))
	_part(support_arm, _box_mesh, glove, Vector3(-0.02, -0.12, -0.45), Vector3(0.07, 0.08, 0.08))
	# the other arm pose: hand to the shoulder radio
	radio_arm = _pivot(torso, Vector3(0, 0.52, 0))
	_part(radio_arm, _box_mesh, cloth, Vector3(-0.24, -0.05, -0.04), Vector3(0.11, 0.26, 0.12), Vector3(0.2, 0, 0.35))
	_part(radio_arm, _box_mesh, cloth, Vector3(-0.17, 0.08, -0.12), Vector3(0.09, 0.22, 0.09), Vector3(-0.9, 0, -0.5))
	_part(radio_arm, _box_mesh, glove, Vector3(-0.11, 0.16, -0.08), Vector3(0.07, 0.08, 0.08))
	radio_arm.visible = false
	gun = _pivot(aim, Vector3(0.06, -0.1, -0.32))
	match profile.weapon_kind:
		"lmg":
			_part(gun, _box_mesh, gear, Vector3(0, 0, 0.05), Vector3(0.09, 0.12, 0.46))
			_part(gun, _box_mesh, metal, Vector3(0, 0.01, -0.36), Vector3(0.035, 0.035, 0.36))
			_part(gun, _box_mesh, Mats.plain(Color("3b4030"), 0.85), Vector3(-0.04, -0.11, -0.02), Vector3(0.1, 0.14, 0.16))
			_part(gun, _box_mesh, gear, Vector3(0, -0.03, 0.4), Vector3(0.06, 0.12, 0.26))
			_part(gun, _box_mesh, metal, Vector3(0, 0.08, -0.12), Vector3(0.02, 0.04, 0.12))
		"shotgun":
			_part(gun, _box_mesh, gear, Vector3(0, 0, 0.0), Vector3(0.055, 0.075, 0.24))
			_part(gun, _box_mesh, metal, Vector3(0, 0.012, -0.32), Vector3(0.03, 0.03, 0.42))
			_part(gun, _box_mesh, gear, Vector3(0, -0.035, -0.26), Vector3(0.06, 0.05, 0.16))
			_part(gun, _box_mesh, gear, Vector3(0, -0.03, 0.27), Vector3(0.05, 0.1, 0.26))
		_:
			_part(gun, _box_mesh, metal, Vector3(0, 0, 0.0), Vector3(0.05, 0.075, 0.28))
			_part(gun, _box_mesh, Mats.plain(Color("5a3a22"), 0.6), Vector3(0, -0.005, -0.22), Vector3(0.056, 0.06, 0.18))
			_part(gun, _box_mesh, metal, Vector3(0, 0.01, -0.42), Vector3(0.022, 0.022, 0.22))
			_part(gun, _box_mesh, metal, Vector3(0, -0.11, -0.04), Vector3(0.035, 0.12, 0.06), Vector3(0.4, 0, 0))
			_part(gun, _box_mesh, Mats.plain(Color("5a3a22"), 0.6), Vector3(0, -0.03, 0.27), Vector3(0.045, 0.09, 0.26))
	muzzle = _pivot(gun, Vector3(0, 0.01, -0.54 if profile.weapon_kind == "lmg" else -0.53))
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.04, 0.02, -0.36)
	flashlight.light_color = Color("dfe9ff")
	flashlight.light_energy = 4.0
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 20.0
	flashlight.spot_attenuation = 1.2
	flashlight.shadow_enabled = true
	flashlight.light_volumetric_fog_energy = 2.0
	flashlight.visible = false
	gun.add_child(flashlight)
	var bulb := _part(gun, _cyl_mesh, Mats.emissive(Color("dfe9ff"), 3.0), Vector3(0.04, 0.02, -0.35), Vector3(0.02, 0.02, 0.02), Vector3(PI / 2, 0, 0))
	bulb.visible = false
	flashlight.set_meta("bulb", bulb)


## Model faces -Z. k = crouch amount, hs = horizontal speed.
func animate(dt: float, s: Soldier) -> void:
	var hs := Vector2(s.velocity.x, s.velocity.z).length()
	var k := s.crouch_k
	if not s.climb.is_empty():
		var c := sin(s.global_position.y * 10.0)
		for i in 2:
			(legs[i].th as Node3D).rotation.x = 0.6 + c * 0.5 * (1.0 if i == 0 else -1.0)
			(legs[i].kn as Node3D).rotation.x = -0.9
		aim.rotation.x = -1.2
		torso.rotation.x = 0.05
		return
	var sw := minf(1.0, hs / 3.0)
	var ph := s.anim * (3.0 + hs * 1.6)
	var breathe := sin(s.anim * 1.7) * 0.006
	hips.position.y = lerpf(0.95, 0.58, k) + absf(sin(ph)) * 0.03 * sw
	for i in 2:
		var sn := sin(ph) * (1.0 if i == 1 else -1.0)
		(legs[i].th as Node3D).rotation.x = lerpf(-sn * 0.6 * sw, 1.35 if i == 1 else 0.7, k)
		(legs[i].kn as Node3D).rotation.x = lerpf(-maxf(0.0, -sn) * 0.9 * sw, -1.9 if i == 1 else -2.3, k)
	torso.rotation.x = lerpf(-0.05, -0.25, k) + breathe
	torso.rotation.y = sin(ph) * 0.06 * sw
	var pitch := 0.0
	if s.state == Soldier.State.COMBAT:
		var t := s.aim_point()
		pitch = atan2(t.y - (s.global_position.y + lerpf(1.45, 0.9, k)), Vector2(t.x - s.global_position.x, t.z - s.global_position.z).length())
	aim_pitch = lerpf(aim_pitch, pitch, minf(1.0, dt * 8.0))
	# at rest the weapon hangs low across the body; alert, it comes up to the shoulder
	var lowered := 0.75 if s.state == Soldier.State.CALM else (0.9 if s.reloading > 0.0 else (0.25 if s.state == Soldier.State.SUSPICIOUS else 0.0))
	_radio_k = move_toward(_radio_k, 1.0 if s.radio_t > 0.0 else 0.0, dt * 6.0)
	radio_arm.visible = _radio_k > 0.5
	support_arm.visible = not radio_arm.visible
	if s.blind > 0.0:
		aim.rotation.x = 1.4
		head.rotation.x = -0.4
		head.rotation.y = sin(s.anim * 5.0) * 0.4
	else:
		aim.rotation.x = aim_pitch - torso.rotation.x - lowered
		aim.rotation.y = lowered * 0.5
		head.rotation.x = aim_pitch * 0.5
		head.rotation.y = sin(s.anim * 0.5) * 0.35 if s.state == Soldier.State.CALM else 0.0
		head.rotation.z = _radio_k * 0.25
	aim.rotation.z = sin(s.anim * 6.0) * 0.1 if s.reloading > 0.0 else 0.0
	torso.rotation.z = sin(s.flinch * 30.0) * 0.08 if s.flinch > 0.0 else 0.0
	(flashlight.get_meta("bulb") as Node3D).visible = flashlight.visible


## Falls away from the shot. t runs 0..1.
func animate_death(dt: float, t: float, side: float) -> void:
	var ease_t := t * t * (3.0 - 2.0 * t)
	body.rotation.x = -ease_t * 1.5
	body.rotation.z = side * ease_t
	body.position.y = 0.1 * ease_t
	for i in 2:
		var th: Node3D = legs[i].th
		var kn: Node3D = legs[i].kn
		th.rotation.x = lerpf(th.rotation.x, 0.3 * i, dt * 6.0)
		kn.rotation.x = lerpf(kn.rotation.x, -0.4, dt * 6.0)
	hips.position.y = lerpf(hips.position.y, 0.55, dt * 5.0)
	aim.rotation.x = lerpf(aim.rotation.x, -1.4, dt * 5.0)
	radio_arm.visible = false
	support_arm.visible = true
	flashlight.visible = false
	(flashlight.get_meta("bulb") as Node3D).visible = false
