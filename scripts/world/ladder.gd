class_name Ladder
extends Node3D
## A fixed steel ladder against a wall or through a hatch.
## You get on with the interact key and climb with forward and back; guards use it as a
## navigation link and climb it the same way, hands busy and weapon slung.

const CLIMB_SPEED := 1.7

var height := 4.0
## Points away from the wall, toward where you stand to climb.
var normal := Vector3.BACK
## Where you step off at the top, onto the platform.
var top_exit := Vector3.ZERO


static func make(bottom: Vector3, p_height: float, p_normal: Vector3, top_step := 0.8) -> Ladder:
	var l := Ladder.new()
	l.position = bottom
	l.height = p_height
	l.normal = p_normal.normalized()
	l.top_exit = bottom + Vector3.UP * p_height - l.normal * top_step
	return l


func bottom_exit() -> Vector3:
	return global_position + normal * 0.7


func top_y() -> float:
	return global_position.y + height


## Where a climber's feet are at a given height.
func climb_point(y: float) -> Vector3:
	var p := global_position + normal * 0.4
	p.y = clampf(y, global_position.y, top_y())
	return p


func _ready() -> void:
	var steel := Mats.plain(Color("6a6f74"), 0.4, 0.7)
	var side := normal.cross(Vector3.UP).normalized()
	for s: float in [-0.22, 0.22]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, height + 0.9, 0.05)
		rail.mesh = bm
		rail.material_override = steel
		rail.position = side * s + normal * 0.08 + Vector3.UP * (height + 0.9) * 0.5
		add_child(rail)
	var n := int(height / 0.3)
	for i in range(1, n + 1):
		var rung := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.44, 0.03, 0.03) if absf(side.x) > 0.5 else Vector3(0.03, 0.03, 0.44)
		rung.mesh = rm
		rung.material_override = steel
		rung.position = normal * 0.08 + Vector3.UP * i * 0.3
		add_child(rung)
	var link := NavigationLink3D.new()
	link.bidirectional = true
	link.start_position = normal * 0.7
	link.end_position = top_exit - position
	link.set_meta("ladder", self)
	add_child(link)
