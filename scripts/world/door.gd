class_name Door
extends Node3D
## A sliding security door with an RFID reader.
##
## Guards badge through without thinking; you need a credential with the right access level, or
## a way around the lock. Lock hardware matters when power is cut:
##   MAGLOCK  fails safe: no power, no hold, the door opens for anyone.
##   STRIKE   fails secure: no power, the reader is dead and the door stays locked.
## Doors sit outside the navigation region, so the navmesh runs straight through them and guards
## path as if they were open; you can follow one through before it closes.

enum Lock { STRIKE, MAGLOCK }

const SPEED := 1.8

var label := ""
var access := ""
var lock := Lock.STRIKE
var zone := ""
var axis := "x"
var width := 1.4
var height := 2.2
var open_k := 0.0
var powered := true
## Held open from a security console.
var unlocked := false
## Set each tick: the player is at this door and it won't open for them.
var refused := false
var _body: StaticBody3D
var _shape: CollisionShape3D
var _panel: MeshInstance3D
var _led: StandardMaterial3D
var _was_open := false
var _deny_t := 0.0


static func make(p_label: String, bottom_center: Vector3, p_axis: String, p_width: float, p_access: String, p_lock: Lock, p_zone: String, p_height := 2.2) -> Door:
	var d := Door.new()
	d.label = p_label
	d.position = bottom_center
	d.axis = p_axis
	d.width = p_width
	d.access = p_access
	d.lock = p_lock
	d.zone = p_zone
	d.height = p_height
	return d


func _ready() -> void:
	var along := Vector3.RIGHT if axis == "x" else Vector3.BACK
	var size := Vector3(width, height, 0.1) if axis == "x" else Vector3(0.1, height, width)
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.WORLD
	_body.set_meta("mat", "metal")
	_body.set_meta("pen", Mats.PEN["metal"])
	_body.set_meta("half", size * 0.5)
	_body.position.y = height * 0.5
	add_child(_body)
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	_shape.shape = bs
	_body.add_child(_shape)
	_panel = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	_panel.mesh = bm
	_panel.material_override = Mats.get_mat("metal")
	_panel.position.y = height * 0.5
	add_child(_panel)
	var window := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.3, 0.5, 0.11) if axis == "x" else Vector3(0.11, 0.5, 0.3)
	window.mesh = wm
	window.material_override = Mats.get_mat("glass")
	window.position = Vector3(0, 0.45, 0)
	_panel.add_child(window)
	# the reader, on the wall beside the frame, both faces
	var side := along * (width * 0.5 + 0.18)
	for f: float in [-1.0, 1.0]:
		var reader := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.08, 0.13, 0.03) if axis == "x" else Vector3(0.03, 0.13, 0.08)
		reader.mesh = rm
		reader.material_override = Mats.plain(Color("1a1b1d"), 0.5, 0.3)
		var normal := Vector3.BACK if axis == "x" else Vector3.RIGHT
		reader.position = side + Vector3.UP * 1.2 + normal * f * 0.17
		add_child(reader)
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.03, 0.012, 0.035) if axis == "x" else Vector3(0.035, 0.012, 0.03)
		led.mesh = lm
		if _led == null:
			_led = Mats.emissive(Color("ff3020"), 3.0)
		led.material_override = _led
		led.position = Vector3(0, 0.045, 0)
		reader.add_child(led)


func reset() -> void:
	open_k = 0.0
	powered = true
	unlocked = false
	_apply()


## Does the door currently demand a credential?
func secured() -> bool:
	if unlocked:
		return false
	return not (lock == Lock.MAGLOCK and not powered)


## Can this be opened from the reader right now (strike locks die without power)?
func reader_live() -> bool:
	return powered or lock == Lock.MAGLOCK


func access_name() -> String:
	return access.to_upper()


func tick(dt: float, game: Game) -> void:
	var want := false
	refused = false
	var c := global_position
	for s in game.soldiers:
		if s.alive and _near(s.global_position, 1.9):
			want = true
			break
	var p := game.player
	if p.alive and _near(p.global_position, 1.5):
		if not secured() or (reader_live() and game.has_access(access)):
			want = true
		else:
			refused = true
			if _deny_t <= 0.0 and (p.global_position - c).dot(p.view_dir()) < 0.0:
				_deny_t = 1.2
				Sfx.play_at("deny", c + Vector3.UP * 1.2, -8.0)
	_deny_t -= dt
	open_k = move_toward(open_k, 1.0 if want else 0.0, dt * SPEED)
	var open := open_k > 0.05
	if open != _was_open:
		_was_open = open
		Sfx.play_at("door", c + Vector3.UP, -6.0)
	_apply()


func _near(pos: Vector3, r: float) -> bool:
	var d := pos - global_position
	return absf(d.y) < 1.6 and Vector2(d.x, d.z).length() < r


func _apply() -> void:
	var along := Vector3.RIGHT if axis == "x" else Vector3.BACK
	_panel.position = Vector3.UP * height * 0.5 + along * width * 0.95 * open_k
	_body.position = _panel.position
	_shape.set_deferred("disabled", open_k > 0.6)
	if _led:
		if not reader_live():
			_led.emission_energy_multiplier = 0.0
		else:
			_led.emission = Color("40ff90") if (open_k > 0.05 or not secured()) else Color("ff3020")
			_led.emission_energy_multiplier = 3.0
