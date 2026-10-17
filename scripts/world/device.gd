class_name Device
extends Node3D
## Electronics the player can hack. Cameras watch and radio in what they see; the relay carries
## all guard radio traffic; the security terminal controls every camera; the laptop holds the data.
##
## Every hackable (this and Lamp) answers: hack_name, hack_time, hack_range, is_physical,
## can_hack, hack_point, on_hacked. hack_progress persists, so an interrupted hack resumes.

enum Kind { CAMERA, RELAY, TERMINAL, LAPTOP }

const LOOP_TIME := 90.0
const CAM_RANGE := 26.0
const CAM_HALF_ANGLE := 30.0

var kind: Kind
var hack_progress := 0.0
var hacked := false

# camera state
var base_yaw := 0.0
var sweep := 0.6
var pitch := -0.35
var aware := 0.0
var alarm := false
var looped := 0.0
var offline := false
var sees_player := false
var _sweep_t := 0.0
var _check_t := 0.0
var _report_t := 0.0
var _lost_t := 0.0
var _yaw := 0.0
var _head: Node3D
var _lens_mat: StandardMaterial3D
var _cone: SpotLight3D
var _led_mat: StandardMaterial3D
var _blink := 0.0


static func camera(pos: Vector3, facing_yaw: float, sweep_range: float, tilt := -0.35) -> Device:
	var d := Device.new()
	d.kind = Kind.CAMERA
	d.position = pos
	d.base_yaw = facing_yaw
	d.sweep = sweep_range
	d.pitch = tilt
	d._sweep_t = randf() * TAU
	return d


static func make(p_kind: Kind, pos: Vector3, yaw := 0.0) -> Device:
	var d := Device.new()
	d.kind = p_kind
	d.position = pos
	d.rotation.y = yaw
	return d


func _ready() -> void:
	_yaw = base_yaw
	match kind:
		Kind.CAMERA: _build_camera()
		Kind.RELAY: _build_relay()
		Kind.TERMINAL: _build_screen(Vector3(0.5, 0.32, 0.04), Color("4ad0ff"))
		Kind.LAPTOP: _build_laptop()


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_camera() -> void:
	var body := Mats.plain(Color("d8d8d0"), 0.5, 0.2)
	var dark := Mats.plain(Color("1a1b1d"), 0.6, 0.4)
	_box(self, Vector3(0.08, 0.08, 0.3), dark, Vector3(0, 0.12, 0.1))
	_head = Node3D.new()
	add_child(_head)
	_box(_head, Vector3(0.18, 0.16, 0.38), body, Vector3(0, 0, -0.05))
	_box(_head, Vector3(0.22, 0.03, 0.44), dark, Vector3(0, 0.095, -0.07))
	_lens_mat = Mats.emissive(Color("f0f4ff"), 1.5)
	var lens := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.05
	cm.height = 0.04
	lens.mesh = cm
	lens.material_override = _lens_mat
	lens.rotation.x = PI / 2
	lens.position = Vector3(0, 0, -0.25)
	_head.add_child(lens)
	_cone = SpotLight3D.new()
	_cone.position = Vector3(0, 0, -0.3)
	_cone.spot_range = CAM_RANGE
	_cone.spot_angle = CAM_HALF_ANGLE
	_cone.light_energy = 0.35
	_cone.light_color = Color("ffd2c8")
	_cone.light_volumetric_fog_energy = 1.2
	_cone.shadow_enabled = true
	_head.add_child(_cone)


func _build_relay() -> void:
	var grey := Mats.plain(Color("6a6e72"), 0.5, 0.5)
	_box(self, Vector3(0.9, 1.1, 0.6), grey, Vector3(0, 0.55, 0))
	_box(self, Vector3(0.06, 2.2, 0.06), grey, Vector3(0.3, 2.2, 0))
	_box(self, Vector3(0.5, 0.04, 0.04), grey, Vector3(0.3, 2.9, 0))
	_box(self, Vector3(0.4, 0.04, 0.04), grey, Vector3(0.3, 2.5, 0))
	_led_mat = Mats.emissive(Color("ff2a1a"), 4.0)
	_box(self, Vector3(0.06, 0.06, 0.06), _led_mat, Vector3(0.3, 3.32, 0))
	_box(self, Vector3(0.3, 0.12, 0.02), Mats.emissive(Color("40ff90"), 1.2), Vector3(-0.15, 0.85, -0.31))


func _build_screen(size: Vector3, color: Color) -> void:
	_box(self, Vector3(size.x + 0.04, size.y + 0.04, 0.05), Mats.plain(Color("1a1b1d"), 0.6), Vector3(0, size.y * 0.5 + 0.06, 0))
	_led_mat = Mats.emissive(color, 1.4)
	_box(self, size, _led_mat, Vector3(0, size.y * 0.5 + 0.06, -0.03))
	_box(self, Vector3(0.45, 0.02, 0.16), Mats.plain(Color("2a2c2e"), 0.6), Vector3(0, 0.01, -0.18))


func _build_laptop() -> void:
	_box(self, Vector3(0.36, 0.02, 0.25), Mats.plain(Color("202224"), 0.4, 0.5), Vector3(0, 0.01, 0))
	_led_mat = Mats.emissive(Color("40ff90"), 1.6)
	_box(self, Vector3(0.36, 0.24, 0.015), _led_mat, Vector3(0, 0.13, -0.12), Vector3(-0.25, 0, 0))


# ------------------------------------------------------------------ hackable interface

func hack_name() -> String:
	match kind:
		Kind.CAMERA: return "camera"
		Kind.RELAY: return "comms relay"
		Kind.TERMINAL: return "security terminal"
	return "drive"


func hack_time() -> float:
	match kind:
		Kind.CAMERA: return 2.5
		Kind.RELAY: return 4.0
		Kind.TERMINAL: return 4.0
	return 9.0


func hack_range() -> float:
	return 2.2 if is_physical() else (24.0 if kind == Kind.CAMERA else 22.0)


func is_physical() -> bool:
	return kind == Kind.TERMINAL or kind == Kind.LAPTOP


func can_hack() -> bool:
	if kind == Kind.CAMERA:
		return not offline and looped <= 0.0
	return not hacked


func hack_point() -> Vector3:
	match kind:
		Kind.CAMERA: return _head.global_position
		Kind.RELAY: return global_position + Vector3.UP * 0.7
	return global_position + Vector3.UP * 0.15


func on_hacked(game: Game) -> void:
	hack_progress = 0.0
	match kind:
		Kind.CAMERA:
			looped = LOOP_TIME
			_stand_down()
			game.hud.toast("CAMERA FEED LOOPED  ·  %ds" % int(LOOP_TIME))
		Kind.RELAY:
			hacked = true
			game.jam_comms(120.0)
		Kind.TERMINAL:
			hacked = true
			_led_mat.emission = Color("ff4a3a")
			game.cameras_offline()
		Kind.LAPTOP:
			hacked = true
			_led_mat.emission = Color("ffb84a")
			game.data_downloaded()


func set_offline() -> void:
	offline = true
	_stand_down()


func _stand_down() -> void:
	aware = 0.0
	alarm = false
	sees_player = false
	if _lens_mat:
		_lens_mat.emission_energy_multiplier = 0.0
	if _cone:
		_cone.visible = false


# ------------------------------------------------------------------ behaviour

func tick(dt: float, game: Game) -> void:
	_blink += dt
	if kind == Kind.RELAY and _led_mat:
		_led_mat.emission_energy_multiplier = (4.0 if fmod(_blink, 1.2) < 0.15 else 0.2) if not hacked else 0.0
		return
	if kind != Kind.CAMERA:
		return
	if offline:
		return
	if looped > 0.0:
		looped -= dt
		if looped <= 0.0:
			_cone.visible = true
			Sfx.play_at("hint", global_position, -6.0)
		return
	var p := game.player
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.1
		sees_player = _can_see(game, p.eye_pos()) or _can_see(game, p.chest_pos())
	if sees_player and p.alive:
		var d := _head.global_position.distance_to(p.global_position)
		var stance := 0.5 if p.crouched else 1.0
		var motion := 0.5 if p.speed_2d() < 0.5 else 1.0
		aware = minf(1.2, aware + 1.6 / (1.0 + d / 10.0) * stance * motion * game.player_light * dt)
		_lost_t = 0.0
		var to := p.chest_pos() - _head.global_position
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), minf(1.0, dt * 3.0))
	else:
		aware = maxf(0.0, aware - dt * (0.05 if alarm else 0.12))
		_lost_t += dt
		if alarm and _lost_t > 8.0:
			alarm = false
		if not alarm:
			_sweep_t += dt * 0.45
			_yaw = lerp_angle(_yaw, base_yaw + sin(_sweep_t) * sweep, minf(1.0, dt * 2.0))
	_head.rotation = Vector3(pitch, _yaw - rotation.y, 0)
	if aware >= 1.0 and not alarm:
		alarm = true
		game.camera_alarm(self)
	if alarm and sees_player:
		_report_t -= dt
		if _report_t <= 0.0:
			_report_t = 1.5
			game.camera_report(self)
	var c := Color("f0f4ff")
	if alarm:
		c = Color("ff3a2a") if fmod(_blink, 0.5) < 0.3 else Color("400806")
	elif aware > 0.05:
		c = Color("ffb84a")
	_lens_mat.emission = c
	_cone.light_color = c.lerp(Color.WHITE, 0.6)


func _can_see(game: Game, target: Vector3) -> bool:
	var from := _head.global_position + (-_head.global_basis.z) * 0.32
	var to := target - from
	var d := to.length()
	if d > CAM_RANGE:
		return false
	if (-_head.global_basis.z).dot(to / d) < cos(deg_to_rad(CAM_HALF_ANGLE)):
		return false
	return game.los(from, target) and not game.smoke_blocks(from, target)


## Cameras also notice bodies left in their view.
func sees_point(game: Game, target: Vector3) -> bool:
	if kind != Kind.CAMERA or offline or looped > 0.0:
		return false
	return _can_see(game, target)
