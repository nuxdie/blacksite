class_name Pickup
extends Node3D
## Medkits, ammo crates, dropped weapons and loose rounds, grenades, and the objective drive.

enum Kind { MEDKIT, AMMO, INTEL, ROUNDS, FRAG, WEAPON }

var kind: Kind
var amount := 1
var taken := false
var permanent := false
## ROUNDS: the ammunition family. WEAPON: rounds left in its magazine and its spare magazines.
var caliber := ""
var weapon: WeaponData
var mag_rounds := 0
var spares: Array = []


static func create(p_kind: Kind, pos: Vector3, p_amount := 1, p_permanent := false) -> Pickup:
	var p := Pickup.new()
	p.kind = p_kind
	p.amount = p_amount
	p.permanent = p_permanent
	p.position = pos
	return p


static func rounds(pos: Vector3, p_caliber: String, count: int) -> Pickup:
	var p := create(Kind.ROUNDS, pos, count)
	p.caliber = p_caliber
	return p


static func dropped_weapon(pos: Vector3, data: WeaponData, in_mag: int, p_spares: Array) -> Pickup:
	var p := create(Kind.WEAPON, pos)
	p.weapon = data
	p.mag_rounds = in_mag
	p.spares = p_spares.duplicate()
	return p


func _ready() -> void:
	_build()


## Collected by walking over it rather than by pressing interact.
func is_auto() -> bool:
	return kind == Kind.ROUNDS or kind == Kind.FRAG


func label() -> String:
	match kind:
		Kind.MEDKIT: return "Medkit"
		Kind.AMMO: return "Resupply"
		Kind.INTEL: return "Take the drive"
		Kind.WEAPON: return "Take %s  ·  %s" % [weapon.display_name, weapon.caliber]
	return ""


func _box(size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _build() -> void:
	var dark := Mats.plain(Color("1e1f22"), 0.6, 0.3)
	match kind:
		Kind.MEDKIT:
			_box(Vector3(0.4, 0.18, 0.28), Mats.plain(Color("d8d8d0"), 0.6), Vector3(0, 0.09, 0))
			var red := Mats.emissive(Color("ff2020"), 1.5)
			_box(Vector3(0.2, 0.01, 0.06), red, Vector3(0, 0.185, 0))
			_box(Vector3(0.06, 0.01, 0.2), red, Vector3(0, 0.185, 0))
		Kind.AMMO:
			_box(Vector3(0.6, 0.3, 0.35), Mats.plain(Color("3a4a2a"), 0.8), Vector3(0, 0.15, 0))
			_box(Vector3(0.62, 0.05, 0.1), Mats.plain(Color("c8a640"), 0.7), Vector3(0, 0.2, 0))
		Kind.INTEL:
			_box(Vector3(0.36, 0.02, 0.25), Mats.plain(Color("202224"), 0.4, 0.5), Vector3(0, 0.01, 0))
			_box(Vector3(0.36, 0.24, 0.015), Mats.emissive(Color("40ff90"), 1.6), Vector3(0, 0.13, -0.12), Vector3(-0.25, 0, 0))
		Kind.ROUNDS:
			var yaw := randf() * TAU
			if caliber == "12ga":
				_box(Vector3(0.12, 0.05, 0.08), Mats.plain(Color("8a2a20"), 0.7), Vector3(0, 0.025, 0), Vector3(0, yaw, 0))
			else:
				_box(Vector3(0.16, 0.05, 0.06), dark, Vector3(0, 0.03, 0), Vector3(0, yaw, 0))
				_box(Vector3(0.14, 0.05, 0.06), dark, Vector3(0.05, 0.03, 0.07), Vector3(0, yaw + 0.4, 0))
		Kind.FRAG:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.14
			mi.mesh = sm
			mi.material_override = Mats.plain(Color("3a4a30"), 0.7)
			mi.position = Vector3(0, 0.07, 0)
			add_child(mi)
		Kind.WEAPON:
			var root := Node3D.new()
			root.rotation = Vector3(0, randf() * TAU, PI / 2)
			root.position.y = 0.05
			add_child(root)
			var len := 0.95 if weapon.id == "lmg" else (0.85 if weapon.id == "shotgun" else 0.75)
			var body := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 0.11 if weapon.id == "lmg" else 0.08, len)
			body.mesh = bm
			body.material_override = dark
			root.add_child(body)
			var furn := Mats.plain(Color("5a3a22") if weapon.id == "ar7" else Color("2a2c2e"), 0.7)
			var stock := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.06, 0.1, 0.22)
			stock.mesh = sb
			stock.material_override = furn
			stock.position = Vector3(0, -0.02, len * 0.5 + 0.08)
			root.add_child(stock)
			var mag := MeshInstance3D.new()
			var mb := BoxMesh.new()
			mb.size = Vector3(0.05, 0.16, 0.12) if weapon.id == "lmg" else Vector3(0.035, 0.14, 0.06)
			mag.mesh = mb
			mag.material_override = dark
			mag.position = Vector3(0, -0.11, -0.05)
			if weapon.id != "shotgun":
				root.add_child(mag)


func take() -> void:
	taken = true
	visible = false
	Sfx.play("pickup")
