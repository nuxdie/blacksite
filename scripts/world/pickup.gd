class_name Pickup
extends Node3D
## Medkits, ammo crates, dropped magazines and grenades, and the objective drive.

enum Kind { MEDKIT, AMMO, INTEL, MAG, FRAG }

var kind: Kind
var amount := 1
var taken := false
var permanent := false


static func create(p_kind: Kind, pos: Vector3, p_amount := 1, p_permanent := false) -> Pickup:
	var p := Pickup.new()
	p.kind = p_kind
	p.amount = p_amount
	p.permanent = p_permanent
	p.position = pos
	p._build()
	return p


## Picked up by walking over it rather than by pressing interact.
func is_auto() -> bool:
	return kind == Kind.MAG or kind == Kind.FRAG


func label() -> String:
	match kind:
		Kind.MEDKIT: return "Medkit"
		Kind.AMMO: return "Resupply"
		Kind.INTEL: return "Take the drive"
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
		Kind.MAG:
			_box(Vector3(0.16, 0.05, 0.06), Mats.plain(Color("1e1f22"), 0.6), Vector3(0, 0.03, 0), Vector3(0, randf() * TAU, 0))
		Kind.FRAG:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.07
			sm.height = 0.14
			mi.mesh = sm
			mi.material_override = Mats.plain(Color("3a4a30"), 0.7)
			mi.position = Vector3(0, 0.07, 0)
			add_child(mi)


func take() -> void:
	taken = true
	visible = false
	Sfx.play("pickup")
