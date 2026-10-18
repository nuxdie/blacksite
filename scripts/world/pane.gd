class_name Pane
extends StaticBody3D
## A sheet of glass in a window. See-through for everyone, so it sits on its own physics layer:
## eyes and lamps ignore it, bodies and bullets don't. One round, one swing of an axe, and it's
## gone, and the opening behind it is just a hole to climb through.

var broken := false
var size := Vector3.ZERO
var game: Game
var _mesh: MeshInstance3D
var _shape: CollisionShape3D


static func make(center: Vector3, p_size: Vector3) -> Pane:
	var p := Pane.new()
	p.position = center
	p.size = p_size
	return p


func _ready() -> void:
	collision_layer = Layers.GLASS
	collision_mask = 0
	set_meta("mat", "glass")
	set_meta("pen", Mats.PEN["glass"])
	set_meta("half", size * 0.5)
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	_shape.shape = bs
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	_mesh.mesh = bm
	_mesh.material_override = Mats.get_mat("glass")
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## A bullet went through: that's enough.
func on_shot() -> void:
	shatter()


func shatter(quiet := false) -> void:
	if broken:
		return
	broken = true
	_mesh.visible = false
	_shape.set_deferred("disabled", true)
	if quiet or game == null:
		return
	game.fx.burst("glass", global_position, Vector3.UP)
	Sfx.play_at("glass", global_position, 2.0)
	# breaking glass carries
	game.hear_gunshot(global_position, 18.0, true)


func reset() -> void:
	broken = false
	_mesh.visible = true
	_shape.set_deferred("disabled", false)
