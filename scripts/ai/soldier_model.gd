class_name SoldierModel
extends Node3D
## Procedural guard body: two-segment legs, torso, helmet and goggles, and a weapon
## on an aiming pivot. Animated directly from the soldier's state.

var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var aim: Node3D
var gun: Node3D
var muzzle: Node3D
var flashlight: SpotLight3D
var legs: Array[Dictionary] = []
var visor_mat: StandardMaterial3D
var aim_pitch := 0.0
var _box_mesh := BoxMesh.new()
var _sph_mesh := SphereMesh.new()


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3, rot_x := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	mi.rotation.x = rot_x
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func build(profile: SoldierProfile) -> void:
	_sph_mesh.radius = 1.0
	_sph_mesh.height = 2.0
	var cloth := Mats.plain(profile.uniform_color, 0.9)
	var vest := Mats.plain(Color("1c1e1c"), 0.75, 0.1)
	var gear := Mats.plain(Color("111214"), 0.6, 0.4)
	var skin := Mats.plain(Color("2a2826"), 0.9)
	visor_mat = Mats.plain(Color("0c0e10"), 0.08, 0.6)
	body = _pivot(self, Vector3.ZERO)
	hips = _pivot(body, Vector3(0, 0.95, 0))
	for sx: float in [-1.0, 1.0]:
		var th := _pivot(hips, Vector3(sx * 0.11, 0, 0))
		_part(th, _box_mesh, cloth, Vector3(0, -0.22, 0), Vector3(0.16, 0.46, 0.18))
		var kn := _pivot(th, Vector3(0, -0.45, 0))
		_part(kn, _box_mesh, cloth, Vector3(0, -0.22, 0), Vector3(0.14, 0.45, 0.15))
		_part(kn, _box_mesh, gear, Vector3(0, -0.47, -0.04), Vector3(0.15, 0.08, 0.27))
		_part(kn, _box_mesh, vest, Vector3(0, -0.05, -0.08), Vector3(0.13, 0.12, 0.05))
		legs.append({"th": th, "kn": kn})
	torso = _pivot(hips, Vector3(0, 0.04, 0))
	_part(torso, _box_mesh, cloth, Vector3(0, 0.14, 0), Vector3(0.32, 0.28, 0.2))
	_part(torso, _box_mesh, cloth, Vector3(0, 0.42, 0), Vector3(0.42, 0.32, 0.24))
	_part(torso, _box_mesh, vest, Vector3(0, 0.38, -0.03), Vector3(0.45, 0.36, 0.3))
	for x: float in [-0.12, 0.0, 0.12]:
		_part(torso, _box_mesh, gear, Vector3(x, 0.27, -0.17), Vector3(0.09, 0.11, 0.05))
	if profile.id == "heavy":
		_part(torso, _box_mesh, gear, Vector3(0, 0.45, -0.03), Vector3(0.62, 0.2, 0.36))
		_part(torso, _box_mesh, vest, Vector3(0, 0.12, -0.05), Vector3(0.4, 0.2, 0.28))
	head = _pivot(torso, Vector3(0, 0.66, -0.01))
	_part(head, _box_mesh, skin, Vector3.ZERO, Vector3(0.19, 0.22, 0.21))
	_part(head, _sph_mesh, gear, Vector3(0, 0.07, 0.01), Vector3(0.15, 0.12, 0.16))
	_part(head, _box_mesh, gear, Vector3(0, -0.07, -0.07), Vector3(0.18, 0.09, 0.1))
	_part(head, _box_mesh, visor_mat, Vector3(0, 0.025, -0.105), Vector3(0.16, 0.035, 0.02))
	aim = _pivot(torso, Vector3(0, 0.5, 0))
	_part(aim, _box_mesh, cloth, Vector3(0.19, -0.1, -0.12), Vector3(0.11, 0.11, 0.32), -0.4)
	_part(aim, _box_mesh, cloth, Vector3(-0.17, -0.12, -0.2), Vector3(0.11, 0.11, 0.4), -0.6)
	_part(aim, _box_mesh, skin, Vector3(-0.05, -0.17, -0.38), Vector3(0.08, 0.08, 0.09))
	_part(aim, _box_mesh, skin, Vector3(0.1, -0.13, -0.14), Vector3(0.08, 0.09, 0.08))
	gun = _pivot(aim, Vector3(0.08, -0.08, -0.3))
	match profile.weapon_kind:
		"lmg":
			_part(gun, _box_mesh, gear, Vector3.ZERO, Vector3(0.1, 0.13, 0.72))
			_part(gun, _box_mesh, gear, Vector3(0, -0.1, -0.05), Vector3(0.12, 0.14, 0.14))
		"shotgun":
			_part(gun, _box_mesh, gear, Vector3.ZERO, Vector3(0.07, 0.08, 0.6))
			_part(gun, _box_mesh, vest, Vector3(0, -0.03, -0.1), Vector3(0.075, 0.06, 0.18))
		_:
			_part(gun, _box_mesh, gear, Vector3.ZERO, Vector3(0.06, 0.09, 0.62))
			_part(gun, _box_mesh, gear, Vector3(0, -0.09, -0.06), Vector3(0.04, 0.12, 0.06))
	muzzle = _pivot(gun, Vector3(0, 0, -0.42 if profile.weapon_kind == "lmg" else -0.34))
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0, 0.05, -0.32)
	flashlight.light_color = Color("dfe9ff")
	flashlight.light_energy = 4.0
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 20.0
	flashlight.spot_attenuation = 1.2
	flashlight.shadow_enabled = true
	flashlight.light_volumetric_fog_energy = 2.0
	flashlight.visible = false
	gun.add_child(flashlight)


## Model faces -Z. k = crouch amount, hs = horizontal speed.
func animate(dt: float, s: Soldier) -> void:
	var hs := Vector2(s.velocity.x, s.velocity.z).length()
	var k := s.crouch_k
	var sw := minf(1.0, hs / 3.0)
	var ph := s.anim * (3.0 + hs * 1.6)
	hips.position.y = lerpf(0.95, 0.58, k) + absf(sin(ph)) * 0.03 * sw
	for i in 2:
		var sn := sin(ph) * (1.0 if i == 1 else -1.0)
		(legs[i].th as Node3D).rotation.x = lerpf(-sn * 0.6 * sw, 1.35 if i == 1 else 0.7, k)
		(legs[i].kn as Node3D).rotation.x = lerpf(-maxf(0.0, -sn) * 0.9 * sw, -1.9 if i == 1 else -2.3, k)
	torso.rotation.x = lerpf(-0.05, -0.25, k)
	var pitch := 0.0
	if s.state == Soldier.State.COMBAT:
		var t := s.aim_point()
		pitch = atan2(t.y - (s.global_position.y + lerpf(1.45, 0.9, k)), Vector2(t.x - s.global_position.x, t.z - s.global_position.z).length())
	aim_pitch = lerpf(aim_pitch, pitch, minf(1.0, dt * 8.0))
	var lowered := 0.5 if s.state == Soldier.State.CALM else (0.8 if s.reloading > 0.0 else 0.0)
	if s.blind > 0.0:
		aim.rotation.x = 1.4
		head.rotation.x = -0.4
		head.rotation.y = sin(s.anim * 5.0) * 0.4
	else:
		aim.rotation.x = aim_pitch - torso.rotation.x - lowered
		head.rotation.x = aim_pitch * 0.5
		head.rotation.y = sin(s.anim * 0.5) * 0.25 if s.state == Soldier.State.CALM else 0.0
	aim.rotation.z = sin(s.anim * 6.0) * 0.1 if s.reloading > 0.0 else 0.0
	torso.rotation.z = sin(s.flinch * 30.0) * 0.08 if s.flinch > 0.0 else 0.0


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
	flashlight.visible = false
