class_name Drone
extends Node3D
## A small security quadrotor on an automated patrol. It scans the ground like a moving camera:
## builds awareness of a lit, moving target in its cone and radios position to HQ. It runs on the
## security network, so comms-down grounds it (returns to base) and an EMP drops it for a while.
## It is shootable; a destroyed drone that was watching you is itself a report.

enum Mode { PATROL, INVESTIGATE, TRACK, RETURN, DOWN, DIVE }

const SPEED := 5.5
const DIVE_SPEED := 13.0
const SCAN_RANGE := 22.0
const SCAN_HALF := 26.0
const EYE_DROP := 0.0

var game: Game
var label := "DRONE"
var route: Array[Vector3] = []
var home := Vector3.ZERO
var mode := Mode.PATROL
var aware := 0.0
var _ping_t := 0.0
var sees_player := false
var destroyed := false
var down_t := 0.0
var hp := 18.0
## A wreck that has hit the ground, and the fall before it.
var landed := false
var _vy := 0.0
var _dive_t := 0.0

var _i := 0
var _wait := 0.0
var _yaw := 0.0
var _spin := 0.0
var _target := Vector3.ZERO
var _lost := 0.0
var _check_t := 0.0
var _report_t := 0.0
var _bob := 0.0
var _body: Node3D
var _cone: SpotLight3D
var _led: StandardMaterial3D
var _rotors: Array[Node3D] = []
var _hum: AudioStreamPlayer3D


static func make(p_label: String, p_route: Array, altitude := 5.4) -> Drone:
	var d := Drone.new()
	d.label = p_label
	for w in p_route:
		d.route.append(Vector3(w[0], altitude, w[1]))
	d.home = d.route[0]
	d.position = d.home
	return d


func _ready() -> void:
	_yaw = randf() * TAU
	_target = route[0]
	_build()
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sfx.bank.get("drone_hum")
	_hum.bus = "World"
	_hum.unit_size = 2.5
	_hum.max_distance = 38.0
	_hum.volume_db = -3.0
	add_child(_hum)
	if _hum.stream:
		_hum.play()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var dark := Mats.plain(Color("1a1b1e"), 0.5, 0.4)
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.22
	shell.mesh = sm
	shell.material_override = dark
	_body.add_child(shell)
	# camera ball underneath, with the status LED
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.07
	bm.height = 0.14
	ball.mesh = bm
	ball.material_override = Mats.plain(Color("0a0b0d"), 0.1, 0.6)
	ball.position = Vector3(0, -0.14, 0)
	_body.add_child(ball)
	_led = Mats.emissive(Color("40ff90"), 3.0)
	var lens := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.03
	lm.height = 0.06
	lens.mesh = lm
	lens.material_override = _led
	lens.position = Vector3(0, -0.18, 0.05)
	_body.add_child(lens)
	var arm := Mats.plain(Color("26282c"), 0.6, 0.3)
	for i in 4:
		var a := PI / 4 + i * PI / 2
		var dir := Vector3(cos(a), 0, sin(a))
		var boom := MeshInstance3D.new()
		var bmm := BoxMesh.new()
		bmm.size = Vector3(0.015, 0.015, 0.26)
		boom.mesh = bmm
		boom.material_override = arm
		boom.position = dir * 0.17
		boom.look_at_from_position(boom.position, Vector3.ZERO, Vector3.UP)
		_body.add_child(boom)
		var hub := Node3D.new()
		hub.position = dir * 0.28
		_body.add_child(hub)
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(0.3, 0.004, 0.025)
		blade.mesh = blm
		blade.material_override = Mats.plain(Color("3a3d42"), 0.4)
		hub.add_child(blade)
		_rotors.append(hub)
	_cone = SpotLight3D.new()
	_cone.light_color = Color("f0f4ff")
	_cone.light_energy = 2.2
	_cone.spot_range = SCAN_RANGE + 4.0
	_cone.spot_angle = SCAN_HALF
	_cone.spot_attenuation = 1.0
	_cone.light_volumetric_fog_energy = 1.2
	_cone.rotation.x = -PI / 2
	add_child(_cone)


func reset() -> void:
	destroyed = false
	down_t = 0.0
	hp = 18.0
	mode = Mode.PATROL
	aware = 0.0
	_i = 0
	_target = route[0]
	position = home
	visible = true
	_body.visible = true
	_body.rotation = Vector3.ZERO
	_cone.visible = true
	landed = false
	_vy = 0.0
	_dive_t = 0.0
	if _hum and _hum.stream and not _hum.playing:
		_hum.play()


func head_pos() -> Vector3:
	return global_position + Vector3(0, -0.14, 0)


func scanning() -> bool:
	return not destroyed and down_t <= 0.0 and mode != Mode.RETURN


func grounded() -> bool:
	return destroyed or down_t > 0.0


# ------------------------------------------------------------------ hit

func take_hit(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		var was_watching := sees_player
		destroyed = true
		aware = 0.0
		_cone.visible = false
		_vy = 0.0
		if _hum:
			_hum.stop()
		game.fx.burst("spark", head_pos())
		game.fx.flash_light(global_position, Color("ffd080"), 4.0, 0.2, 10.0)
		Sfx.play_at("impact_metal", global_position, 2.0)
		game.drone_destroyed(self, was_watching)
	elif not grounded() and mode != Mode.DIVE:
		# hit but flying: it stops scanning and comes for you
		_start_dive()


func _start_dive() -> void:
	mode = Mode.DIVE
	_dive_t = 0.0
	aware = 1.3
	sees_player = true
	_lost = 0.0
	game.drone_dive(self)


## Dive at the player's chest and go off on contact, or on whatever it hits on the way.
func _dive(dt: float) -> void:
	_dive_t += dt
	var p := game.player
	var goal := p.chest_pos()
	if p.alive and (game.los(head_pos(), goal) or _dive_t < 1.0):
		_target = goal
		_lost = 0.0
	else:
		_lost += dt
	if _lost > 4.0 or not p.alive:
		# lost you for good: back to hunting from above
		mode = Mode.TRACK
		_target = Vector3(p.global_position.x, home.y, p.global_position.z)
		return
	var to := _target - global_position
	var d := to.length()
	var step := to / maxf(d, 0.001) * minf(d, DIVE_SPEED * dt)
	var next := global_position + step
	# the world in the way, or close enough: boom
	var q := PhysicsRayQueryParameters3D.create(global_position, next + step.normalized() * 0.25, Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_explode(hit.position)
		return
	global_position = next
	_yaw = atan2(-to.x, -to.z)
	if d < 1.1 or (p.alive and global_position.distance_to(p.chest_pos()) < 1.1):
		_explode(global_position)


func _explode(at: Vector3) -> void:
	var was_watching := sees_player
	destroyed = true
	landed = true
	aware = 0.0
	sees_player = false
	_cone.visible = false
	_body.visible = false
	if _hum:
		_hum.stop()
	global_position = at
	game.drone_exploded(self, at, was_watching)


## Knocked out by an EMP for a while, then it reboots.
func emp(seconds: float) -> void:
	if destroyed:
		return
	down_t = maxf(down_t, seconds)
	aware = 0.0
	mode = Mode.DOWN
	Sfx.play_at("emp", global_position, 0.0, false)
	Sfx.play_at("drone_down", global_position, -4.0, false)


# ------------------------------------------------------------------ think

func tick(dt: float, game_ref: Game) -> void:
	game = game_ref
	if destroyed:
		_fall(dt)
		return
	for r in _rotors:
		r.rotation.y += dt * (6.0 if down_t <= 0.0 else 1.0) * 40.0
	_bob += dt
	if down_t > 0.0:
		down_t -= dt
		_fall(dt, true)
		if down_t <= 0.0:
			mode = Mode.RETURN
			position.y = home.y
		return
	if game.comms_down and mode != Mode.RETURN and mode != Mode.DIVE:
		mode = Mode.RETURN
	if mode == Mode.DIVE:
		_dive(dt)
		if not destroyed:
			_apply_visual(dt)
		return
	_scan(dt)
	match mode:
		Mode.PATROL: _patrol(dt)
		Mode.INVESTIGATE: _investigate(dt)
		Mode.TRACK: _track(dt)
		Mode.RETURN: _return(dt)
	_apply_visual(dt)


func _apply_visual(dt: float) -> void:
	var tilt := clampf((_target - global_position).length(), 0.0, 3.0) / 3.0 * 0.2
	if mode == Mode.DIVE:
		tilt = 0.9
	_body.rotation.y = _yaw
	_body.rotation.x = lerp_angle(_body.rotation.x, tilt, minf(1.0, dt * 4.0))
	_body.position.y = sin(_bob * 2.3) * 0.04
	var c := Color("40ff90")
	if mode == Mode.DIVE:
		c = Color("ff3020") if fmod(_bob, 0.16) < 0.08 else Color("400806")
	elif mode == Mode.TRACK or (aware > 0.95):
		c = Color("ff3020") if fmod(_bob, 0.4) < 0.25 else Color("400806")
	elif aware > 0.1 or mode == Mode.INVESTIGATE:
		c = Color("ffb84a")
	_led.emission = c
	_cone.light_color = c.lerp(Color.WHITE, 0.5)
	if _hum:
		_hum.pitch_scale = 1.0 + tilt * 0.3 + (0.5 if mode == Mode.DIVE else 0.0)


func _scan(dt: float) -> void:
	if not scanning():
		sees_player = false
		return
	var p := game.player
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.1
		sees_player = _can_see(p.eye_pos()) or _can_see(p.chest_pos())
	if sees_player and p.alive:
		var d := head_pos().distance_to(p.global_position)
		var stance := 0.6 if p.crouched else 1.0
		var motion := 0.5 if p.speed_2d() < 0.5 else 1.0
		# overhead view sees through the dark better than a ground camera, but light still helps
		aware = minf(1.3, aware + 1.7 / (1.0 + d / 10.0) * stance * motion * maxf(0.5, game.player_light) * dt)
		_target = Vector3(p.global_position.x, home.y, p.global_position.z)
		_lost = 0.0
		if aware >= 1.0 and mode != Mode.TRACK:
			mode = Mode.TRACK
			Sfx.play_at("drone_lock", global_position, -2.0, false, 0.0)
			game.drone_alarm(self)
		elif aware > 0.3 and mode != Mode.TRACK:
			_ping_t -= dt
			if _ping_t <= 0.0:
				_ping_t = 1.0
				Sfx.play_at("drone_scan", global_position, -6.0, false, 0.0)
	else:
		aware = maxf(0.0, aware - dt * (0.06 if mode == Mode.TRACK else 0.18))
		_lost += dt


func _can_see(target: Vector3) -> bool:
	var to := target - head_pos()
	var d := to.length()
	if d > SCAN_RANGE:
		return false
	if Vector3.DOWN.dot(to / d) < cos(deg_to_rad(SCAN_HALF)):
		return false
	return game.los(head_pos(), target) and not game.smoke_blocks(head_pos(), target)


func _move_toward(p: Vector3, dt: float, speed := SPEED) -> bool:
	var to := p - global_position
	var d := to.length()
	if d < 0.3:
		return true
	global_position += to / d * minf(d, speed * dt)
	_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), minf(1.0, dt * 3.0))
	return false


func _patrol(dt: float) -> void:
	if _wait > 0.0:
		_wait -= dt
		_yaw += dt * 0.4
		return
	if _move_toward(_target, dt):
		_i = (_i + 1) % route.size()
		_target = route[_i]
		_wait = randf_range(0.6, 1.8)


func _investigate(dt: float) -> void:
	if _move_toward(_target, dt):
		_yaw += dt * 1.2
		_lost += dt
		if _lost > 7.0:
			mode = Mode.PATROL
			_target = route[_i]


func _track(dt: float) -> void:
	_move_toward(_target + Vector3.UP * 0.0, dt, SPEED * 1.1)
	_report_t -= dt
	if sees_player and _report_t <= 0.0:
		_report_t = 1.3
		game.drone_report(self)
	if _lost > 6.0:
		mode = Mode.INVESTIGATE
		_lost = 0.0


func _return(dt: float) -> void:
	if _move_toward(home, dt):
		if not game.comms_down:
			mode = Mode.PATROL
			_target = route[_i]


func investigate(pos: Vector3) -> void:
	if mode == Mode.TRACK or mode == Mode.RETURN or grounded():
		return
	mode = Mode.INVESTIGATE
	_target = Vector3(pos.x, home.y, pos.z)
	_lost = 0.0


func _fall(dt: float, hover := false) -> void:
	if hover:
		position.y = move_toward(position.y, home.y - 0.3, dt * 1.5)
		_body.rotation.z = sin(_bob * 8.0) * 0.1
		return
	# destroyed: a wreck falls until it hits whatever is below, then lies there
	if landed:
		return
	_vy -= 9.8 * dt
	var ny := position.y + _vy * dt
	var q := PhysicsRayQueryParameters3D.create(global_position, Vector3(global_position.x, ny - 0.15, global_position.z), Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		position.y = hit.position.y + 0.12
		landed = true
		_body.rotation.x = 0.0
		_body.rotation.z = 0.9
		game.fx.burst("spark", global_position)
		Sfx.play_at("impact_metal", global_position, 0.0)
		Sfx.play_at("glass", global_position, -8.0)
		return
	position.y = ny
	_body.rotation.z += dt * 4.0
	_body.rotation.x += dt * 2.5
	_yaw += dt * 5.0
