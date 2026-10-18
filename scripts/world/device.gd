class_name Device
extends Node3D
## Facility electronics. Nothing is hacked through the air: cameras live on a wired security
## network reached from access points, lights hang off zone breakers, guard radio runs through a
## relay cabinet, and the data has to be copied off the laptop with a drive.

enum Kind { CAMERA, ACCESS, RELAY, BREAKER, LAPTOP, VENT }

const CAM_RANGE := 26.0
const CAM_HALF_ANGLE := 30.0
const LOOP_TIME := 90.0
const COPY_TIME := 35.0

var kind: Kind
var label := ""
## Zone name for breakers and the lamps they feed.
var zone := ""

# camera
var cam_id := 0
var base_yaw := 0.0
var sweep := 0.6
var pitch := -0.35
var aware := 0.0
var alarm := false
var looped := 0.0
var disabled := false
var destroyed := false
var sees_player := false

# access points
var locked := 0.0

# relay / breaker
var sabotaged := false
var repair_pending := false

# laptop: idle | copying | done | taken
var copy_state := "idle"
var _beeped := false
var copy_progress := 0.0

var _sweep_t := 0.0
var _check_t := 0.0
var _report_t := 0.0
var _lost_t := 0.0
var _yaw := 0.0
var _blink := 0.0
var head: Node3D
var _lens_mat: StandardMaterial3D
var _cone: SpotLight3D
var _led_mat: StandardMaterial3D
var _drive: MeshInstance3D
var _grille: StaticBody3D


static func camera(id: int, pos: Vector3, facing_yaw: float, sweep_range: float, tilt := -0.35) -> Device:
	var d := Device.new()
	d.kind = Kind.CAMERA
	d.cam_id = id
	d.label = "CAM %02d" % id
	d.position = pos
	d.base_yaw = facing_yaw
	d.sweep = sweep_range
	d.pitch = tilt
	d._sweep_t = randf() * TAU
	return d


static func make(p_kind: Kind, p_label: String, pos: Vector3, yaw := 0.0, p_zone := "") -> Device:
	var d := Device.new()
	d.kind = p_kind
	d.label = p_label
	d.position = pos
	d.rotation.y = yaw
	d.zone = p_zone
	return d


func _ready() -> void:
	_yaw = base_yaw
	match kind:
		Kind.CAMERA: _build_camera()
		Kind.ACCESS: _build_access()
		Kind.RELAY: _build_relay()
		Kind.BREAKER: _build_breaker()
		Kind.LAPTOP: _build_laptop()
		Kind.VENT: _build_vent()


func reset() -> void:
	aware = 0.0
	alarm = false
	looped = 0.0
	disabled = false
	destroyed = false
	sees_player = false
	locked = 0.0
	sabotaged = false
	repair_pending = false
	copy_state = "idle"
	copy_progress = 0.0
	if _cone:
		_cone.visible = true
	if _lens_mat:
		_lens_mat.emission_energy_multiplier = 1.5
	if head:
		head.visible = true
	if _drive:
		_drive.visible = false
	if _led_mat:
		_led_mat.emission_energy_multiplier = 1.4
	if kind == Kind.VENT and _grille:
		_set_grille(true)


func save_state() -> Dictionary:
	return {"looped": looped, "disabled": disabled, "destroyed": destroyed, "locked": locked, "sabotaged": sabotaged,
		"copy_state": copy_state, "copy_progress": copy_progress, "yaw": _yaw}


func load_state(d: Dictionary) -> void:
	reset()
	looped = d.looped
	disabled = d.disabled
	destroyed = d.destroyed
	locked = d.locked
	sabotaged = d.sabotaged
	copy_state = d.copy_state
	copy_progress = d.copy_progress
	_yaw = d.yaw
	if disabled or destroyed:
		_stand_down(true)
	if destroyed and head:
		head.visible = false
	if kind == Kind.BREAKER and sabotaged:
		_led_mat.emission = Color("ff4a3a")
	if kind == Kind.VENT:
		_set_grille(not sabotaged)
	if _drive:
		_drive.visible = copy_state == "copying" or copy_state == "done"


# ------------------------------------------------------------------ models

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
	head = Node3D.new()
	add_child(head)
	_box(head, Vector3(0.18, 0.16, 0.38), body, Vector3(0, 0, -0.05))
	_box(head, Vector3(0.22, 0.03, 0.44), dark, Vector3(0, 0.095, -0.07))
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
	head.add_child(lens)
	_box(head, Vector3(0.025, 0.025, 0.01), Mats.emissive(Color("ff2a1a"), 3.0), Vector3(0.06, 0.05, -0.245))
	_cone = SpotLight3D.new()
	_cone.position = Vector3(0, 0, -0.3)
	_cone.spot_range = CAM_RANGE
	_cone.spot_angle = CAM_HALF_ANGLE
	_cone.light_energy = 0.35
	_cone.light_color = Color("ffd2c8")
	_cone.light_volumetric_fog_energy = 1.2
	_cone.shadow_enabled = true
	head.add_child(_cone)


func _build_access() -> void:
	var grey := Mats.plain(Color("5a5e62"), 0.55, 0.5)
	if label == "SECURITY TERMINAL":
		_box(self, Vector3(0.54, 0.36, 0.05), Mats.plain(Color("1a1b1d"), 0.6), Vector3(0, 0.24, 0))
		_led_mat = Mats.emissive(Color("4ad0ff"), 1.4)
		_box(self, Vector3(0.5, 0.32, 0.01), _led_mat, Vector3(0, 0.24, -0.03))
		_box(self, Vector3(0.45, 0.02, 0.16), Mats.plain(Color("2a2c2e"), 0.6), Vector3(0, 0.01, -0.18))
	elif label == "SERVER CABINET":
		_box(self, Vector3(0.6, 2.0, 0.8), Mats.plain(Color("1c1d20"), 0.5, 0.5), Vector3(0, 1.0, 0))
		_led_mat = Mats.emissive(Color("40ff90"), 1.4)
		for i in 8:
			_box(self, Vector3(0.4, 0.02, 0.01), _led_mat, Vector3(0, 0.4 + i * 0.18, -0.405))
	else:
		_box(self, Vector3(0.5, 0.6, 0.18), grey, Vector3(0, 0, 0))
		_led_mat = Mats.emissive(Color("40ff90"), 1.4)
		_box(self, Vector3(0.04, 0.04, 0.01), _led_mat, Vector3(0.17, 0.22, -0.095))
		_box(self, Vector3(0.3, 0.03, 0.01), Mats.plain(Color("c8a640"), 0.7), Vector3(0, -0.2, -0.095))


func _build_relay() -> void:
	var grey := Mats.plain(Color("6a6e72"), 0.5, 0.5)
	_box(self, Vector3(0.9, 1.1, 0.6), grey, Vector3(0, 0.55, 0))
	_box(self, Vector3(0.06, 2.2, 0.06), grey, Vector3(0.3, 2.2, 0))
	_box(self, Vector3(0.5, 0.04, 0.04), grey, Vector3(0.3, 2.9, 0))
	_box(self, Vector3(0.4, 0.04, 0.04), grey, Vector3(0.3, 2.5, 0))
	_led_mat = Mats.emissive(Color("ff2a1a"), 4.0)
	_box(self, Vector3(0.06, 0.06, 0.06), _led_mat, Vector3(0.3, 3.32, 0))


func _build_breaker() -> void:
	_box(self, Vector3(0.45, 0.6, 0.12), Mats.plain(Color("8a9096"), 0.5, 0.6), Vector3.ZERO)
	_box(self, Vector3(0.3, 0.08, 0.01), Mats.plain(Color("c8a640"), 0.7), Vector3(0, 0.2, -0.065))
	_led_mat = Mats.emissive(Color("40ff90"), 1.4)
	_box(self, Vector3(0.03, 0.03, 0.01), _led_mat, Vector3(0.15, -0.2, -0.065))


## A screwed-on duct grille: solid until you take it off.
func _build_vent() -> void:
	_grille = StaticBody3D.new()
	_grille.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.3, 1.25, 0.05)
	cs.shape = bs
	_grille.add_child(cs)
	var frame := Mats.plain(Color("6a6f74"), 0.5, 0.6)
	for i in 7:
		var slat := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.26, 0.05, 0.04)
		slat.mesh = bm
		slat.material_override = frame
		slat.position = Vector3(0, -0.54 + i * 0.18, 0)
		slat.rotation.x = 0.5
		_grille.add_child(slat)
	for sx: float in [-0.63, 0.63]:
		var side := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.04, 1.25, 0.05)
		side.mesh = sm
		side.material_override = frame
		side.position = Vector3(sx, 0, 0)
		_grille.add_child(side)
	add_child(_grille)


func _set_grille(on: bool) -> void:
	_grille.visible = on
	(_grille.get_child(0) as CollisionShape3D).set_deferred("disabled", not on)


func _build_laptop() -> void:
	_box(self, Vector3(0.36, 0.02, 0.25), Mats.plain(Color("202224"), 0.4, 0.5), Vector3(0, 0.01, 0))
	_led_mat = Mats.emissive(Color("40ff90"), 1.6)
	_box(self, Vector3(0.36, 0.24, 0.015), _led_mat, Vector3(0, 0.13, -0.12), Vector3(-0.25, 0, 0))
	_drive = _box(self, Vector3(0.05, 0.015, 0.02), Mats.emissive(Color("ffb84a"), 2.0), Vector3(0.2, 0.012, 0.05))
	_drive.visible = false


# ------------------------------------------------------------------ interaction (physical)

## What pressing/holding interact does here; "" when there is nothing to do.
func use_label(game: Game) -> String:
	match kind:
		Kind.ACCESS:
			if locked > 0.0:
				return "Port locked  ·  %ds" % ceili(locked)
			return "Log in with badge" if game.has_badge else "Clip the implant  ·  guest shell, leaves a trace"
		Kind.RELAY:
			return "" if sabotaged else "Sabotage relay"
		Kind.BREAKER:
			return "" if sabotaged else "Cut power  ·  %s" % zone
		Kind.VENT:
			return "" if sabotaged else "Unscrew the vent grille"
		Kind.LAPTOP:
			match copy_state:
				"idle": return "Plug in drive"
				"done": return "Retrieve drive"
	return ""


func use_time(game: Game) -> float:
	match kind:
		Kind.ACCESS: return 1.5 if game.has_badge else 15.0
		Kind.RELAY: return 6.0
		Kind.BREAKER: return 1.0
		Kind.VENT: return 2.5
	return 0.8


func can_use(game: Game) -> bool:
	if kind == Kind.ACCESS and locked > 0.0:
		return false
	return use_label(game) != ""


func use_point() -> Vector3:
	match kind:
		Kind.ACCESS: return global_position + Vector3.UP * (0.25 if label == "SECURITY TERMINAL" else (1.0 if label == "SERVER CABINET" else 0.0))
		Kind.RELAY: return global_position + Vector3.UP * 0.7
		Kind.LAPTOP: return global_position + Vector3.UP * 0.1
		Kind.VENT: return global_position
	return global_position


func on_used(game: Game) -> void:
	match kind:
		Kind.VENT:
			sabotaged = true
			_set_grille(false)
			Sfx.play_at("impact_metal", global_position, -10.0)
		Kind.ACCESS:
			game.open_tablet(self, not game.has_badge)
		Kind.RELAY:
			sabotaged = true
			_led_mat.emission_energy_multiplier = 0.0
			game.jam_comms(self)
		Kind.BREAKER:
			sabotaged = true
			_led_mat.emission = Color("ff4a3a")
			game.set_zone_power(self, false)
		Kind.LAPTOP:
			if copy_state == "idle":
				copy_state = "copying"
				copy_progress = 0.0
				_drive.visible = true
				Sfx.play("pickup")
				game.hud.toast("COPYING  ·  STAY CLOSE, STAY HIDDEN")
			elif copy_state == "done":
				copy_state = "taken"
				_drive.visible = false
				game.data_downloaded()


## A guard put things back the way they were.
func repaired(game: Game) -> void:
	repair_pending = false
	match kind:
		Kind.RELAY:
			sabotaged = false
			game.comms_restored(self)
		Kind.BREAKER:
			sabotaged = false
			_led_mat.emission = Color("40ff90")
			game.set_zone_power(self, true)
		Kind.CAMERA:
			disabled = false
			_cone.visible = true
			_lens_mat.emission_energy_multiplier = 1.5
			Sfx.play_at("power_up", head.global_position, -10.0)
		Kind.ACCESS:
			game.restore_cameras()


## A guard found the drive in the laptop and pulled it; the copy has to start over.
func drive_pulled() -> void:
	copy_state = "idle"
	Sfx.play_at("deny", global_position + Vector3.UP * 0.3, -6.0)
	copy_progress = 0.0
	_drive.visible = false


# ------------------------------------------------------------------ cameras

func camera_live() -> bool:
	return kind == Kind.CAMERA and not disabled and not destroyed and looped <= 0.0


func loop_feed() -> void:
	looped = LOOP_TIME
	_stand_down(false)


func disable() -> void:
	disabled = true
	Sfx.play_at("cam_dead", head.global_position, -4.0)
	_stand_down(true)


func shoot_out() -> void:
	destroyed = true
	_stand_down(true)
	head.visible = false
	Sfx.play_at("glass", global_position)


func _stand_down(dark: bool) -> void:
	aware = 0.0
	alarm = false
	sees_player = false
	if dark:
		_lens_mat.emission_energy_multiplier = 0.0
		_cone.visible = false


func tick(dt: float, game: Game) -> void:
	_blink += dt
	if kind == Kind.RELAY:
		_led_mat.emission_energy_multiplier = 0.0 if sabotaged else (4.0 if fmod(_blink, 1.2) < 0.15 else 0.2)
		return
	if kind == Kind.ACCESS:
		locked = maxf(0.0, locked - dt)
		_led_mat.emission = Color("ff4a3a") if locked > 0.0 else (Color("4ad0ff") if label == "SECURITY TERMINAL" else Color("40ff90"))
		return
	if kind == Kind.LAPTOP:
		if copy_state == "copying":
			copy_progress = minf(1.0, copy_progress + dt / COPY_TIME)
			_led_mat.emission = Color("40ff90") if fmod(_blink, 0.6) < 0.3 else Color("1a6a3a")
			if copy_progress >= 1.0:
				copy_state = "done"
				_led_mat.emission = Color("ffb84a")
				game.hud.banner("COPY COMPLETE")
				Sfx.play("objective", -4.0, 0.0)
		return
	if kind != Kind.CAMERA or disabled or destroyed:
		if kind == Kind.CAMERA:
			Sfx.stop_loop("cam%d" % cam_id)
		return
	# the pan motor is audible up close; a camera that is interested in you beeps once
	var pd := head.global_position.distance_to(game.player.global_position)
	if pd < 14.0 and not alarm:
		Sfx.loop_at("cam%d" % cam_id, "cam_servo", head.global_position, -16.0, 1.2, 14.0)
	else:
		Sfx.stop_loop("cam%d" % cam_id)
	if aware > 0.3 and not _beeped:
		_beeped = true
		Sfx.play_at("cam_notice", head.global_position, -6.0, false, 0.0)
	elif aware < 0.1:
		_beeped = false
	if looped > 0.0:
		looped -= dt
		if looped <= 0.0:
			Sfx.play_at("hint", global_position, -6.0)
	var p := game.player
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.1
		# a looped camera still moves; it just isn't really watching
		sees_player = looped <= 0.0 and (_can_see(game, p.eye_pos()) or _can_see(game, p.chest_pos()))
	if sees_player and p.alive:
		var d := head.global_position.distance_to(p.global_position)
		var stance := 0.5 if p.crouched else 1.0
		var motion := 0.5 if p.speed_2d() < 0.5 else 1.0
		aware = minf(1.2, aware + 1.6 / (1.0 + d / 10.0) * stance * motion * game.player_light * dt)
		_lost_t = 0.0
		var to := p.chest_pos() - head.global_position
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), minf(1.0, dt * 3.0))
	else:
		aware = maxf(0.0, aware - dt * (0.05 if alarm else 0.12))
		_lost_t += dt
		if alarm and _lost_t > 8.0:
			alarm = false
		if not alarm:
			_sweep_t += dt * 0.45
			_yaw = lerp_angle(_yaw, base_yaw + sin(_sweep_t) * sweep, minf(1.0, dt * 2.0))
	head.rotation = Vector3(pitch, _yaw - rotation.y, 0)
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
	var fwd := -head.global_basis.z
	var from := head.global_position + fwd * 0.32
	var to := target - from
	var d := to.length()
	if d > CAM_RANGE or fwd.dot(to / d) < cos(deg_to_rad(CAM_HALF_ANGLE)):
		return false
	return game.los(from, target) and not game.smoke_blocks(from, target)


func sees_point(game: Game, target: Vector3) -> bool:
	return camera_live() and _can_see(game, target)


## Transform for the CCTV feed camera.
func feed_transform() -> Transform3D:
	return head.global_transform.translated_local(Vector3(0, 0, -0.32))
