class_name Truck
extends AnimatableBody3D
## A delivery truck on the site's routine. It comes through the vehicle gate, up the yard and
## into the warehouse bay, sits a while loading, then backs the whole way out again. Whatever is
## in its bed goes with it, and the bed's sides hide anyone lying there from eyes on the ground.
## It brakes for anyone standing in its way.

enum State { AWAY, IN, LOADING, OUT }

const LENGTH := 7.4
const WIDTH := 2.2
const BED_Y := 0.95
const SPEED_ROAD := 5.0
const SPEED_YARD := 2.8
const PERIOD := 240.0
const LOAD_TIME := 45.0

var game: Game
var state := State.AWAY
## Seconds until the next run, while away.
var next_t := 70.0
var load_t := 0.0
var gate: Door
## Distance along the route, and the route itself: a centre line with the corners rounded off.
var s := 0.0
var speed := 0.0
var path: PackedVector3Array = []
var _cum: PackedFloat32Array = []
var total := 0.0
var _beep_t := 0.0
var _lights: Array[SpotLight3D] = []
var _tail_mat: StandardMaterial3D


static func make(p_path: PackedVector3Array) -> Truck:
	var t := Truck.new()
	t.path = p_path
	var acc := 0.0
	t._cum.append(0.0)
	for i in range(1, p_path.size()):
		acc += p_path[i].distance_to(p_path[i - 1])
		t._cum.append(acc)
	t.total = acc
	return t


## A polyline with each corner replaced by an arc of `radius`, so the truck turns like a truck.
static func route(points: Array, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(points[0])
	for i in range(1, points.size() - 1):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var c: Vector3 = points[i + 1]
		var d1 := (b - a).normalized()
		var d2 := (c - b).normalized()
		var ang := d1.angle_to(d2)
		if ang < 0.05:
			out.append(b)
			continue
		var tl := radius * tan(ang * 0.5)
		var p0 := b - d1 * tl
		var p1 := b + d2 * tl
		# the arc's centre sits off to the inside of the turn
		var inward := (d2 - d1).normalized()
		var centre := b + inward * (radius / cos(ang * 0.5))
		var a0 := (p0 - centre)
		var a1 := (p1 - centre)
		var n := maxi(8, int(ang * radius / 0.4))
		for k in n + 1:
			var t := float(k) / n
			out.append(centre + a0.slerp(a1, t))
	out.append(points[points.size() - 1])
	return out


func _ready() -> void:
	# moved by setting its transform each physics step; the physics server derives the body's
	# velocity from that, which is what carries whoever stands in the bed
	sync_to_physics = false
	collision_layer = Layers.WORLD
	collision_mask = 0
	set_meta("mat", "metal")
	set_meta("pen", 0.0)
	_build()
	_place(0.0)
	visible = false


func _build() -> void:
	var steel := Mats.get_mat("steel")
	var paint := Mats.get_mat("c_blue")
	var dark := Mats.plain(Color("1a1b1e"), 0.6, 0.3)
	# chassis, cab, bed floor, three sides and a low tailgate: the open back is how you get in
	_part(Vector3(0, 0.72, 0), Vector3(WIDTH, 0.45, LENGTH), steel)
	_part(Vector3(0, 1.85, -2.5), Vector3(WIDTH, 1.8, 2.4), paint)
	_part(Vector3(0, 2.2, -3.71), Vector3(1.9, 0.7, 0.02), Mats.get_mat("glass"), false)
	_part(Vector3(0, BED_Y - 0.03, 1.3), Vector3(WIDTH, 0.06, 4.8), steel)
	for sx: float in [-1.0, 1.0]:
		_part(Vector3(sx * (WIDTH * 0.5 - 0.04), BED_Y + 0.52, 1.3), Vector3(0.08, 1.05, 4.8), steel)
	_part(Vector3(0, BED_Y + 0.52, -1.06), Vector3(WIDTH, 1.05, 0.08), steel)
	_part(Vector3(0, BED_Y + 0.22, 3.66), Vector3(WIDTH, 0.45, 0.08), steel)
	# wheels
	var tire := Mats.plain(Color("151515"), 0.95)
	for z: float in [-2.6, 1.5, 2.7]:
		for sx: float in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.3
			mi.mesh = cm
			mi.material_override = tire
			mi.position = Vector3(sx * 1.05, 0.5, z)
			mi.rotation = Vector3(0, 0, PI / 2)
			add_child(mi)
	# lights: head and tail
	for sx: float in [-0.8, 0.8]:
		var l := SpotLight3D.new()
		l.position = Vector3(sx, 1.1, -3.7)
		l.rotation = Vector3(-0.08, PI, 0)
		l.light_color = Color("fff2d0")
		l.light_energy = 4.0
		l.spot_range = 22.0
		l.spot_angle = 26.0
		l.spot_attenuation = 1.0
		l.light_volumetric_fog_energy = 1.5
		l.shadow_enabled = true
		add_child(l)
		_lights.append(l)
		_part(Vector3(sx, 1.1, -3.71), Vector3(0.3, 0.16, 0.02), Mats.emissive(Color("fff2d0"), 2.0), false)
	_tail_mat = Mats.emissive(Color("ff2a1a"), 1.5)
	for sx: float in [-0.9, 0.9]:
		_part(Vector3(sx, 0.9, 3.71), Vector3(0.22, 0.1, 0.02), _tail_mat, false)
	var plate := _part(Vector3(0, 1.3, 3.71), Vector3(0.02, 0.02, 0.02), dark, false)
	plate.visible = false


func _part(pos: Vector3, size: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		add_child(cs)
	return mi


# ------------------------------------------------------------------ route

func _sample(at: float) -> Array:
	at = clampf(at, 0.0, total)
	var i := 1
	while i < _cum.size() - 1 and _cum[i] < at:
		i += 1
	var seg := maxf(0.001, _cum[i] - _cum[i - 1])
	var t := (at - _cum[i - 1]) / seg
	var dir := (path[i] - path[i - 1]).normalized()
	return [path[i - 1].lerp(path[i], t), dir]


func _place(at: float) -> void:
	var sm := _sample(at)
	var pos: Vector3 = sm[0]
	var dir: Vector3 = sm[1]
	global_position = pos
	rotation.y = atan2(-dir.x, -dir.z)


func forward() -> Vector3:
	return -global_transform.basis.z


## The middle of the bed, where a stowaway lies.
func bed_point() -> Vector3:
	return to_global(Vector3(0, BED_Y + 0.02, 1.3))


## Is this body in the bed, going wherever the truck goes?
func carrying(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < WIDTH * 0.5 and l.z > -1.0 and l.z < 3.7 and l.y > BED_Y - 0.3 and l.y < BED_Y + 2.0


func moving() -> bool:
	return state == State.IN or state == State.OUT


# ------------------------------------------------------------------ driving

func tick(dt: float) -> void:
	match state:
		State.AWAY:
			next_t -= dt
			if next_t <= 0.0:
				_start_run()
		State.IN:
			_drive(dt, 1.0)
			if s >= total - 0.05:
				state = State.LOADING
				load_t = LOAD_TIME
				speed = 0.0
				Sfx.play_at("truck_door", global_position + forward() * -2.0, -2.0)
		State.LOADING:
			load_t -= dt
			if load_t <= 0.0:
				state = State.OUT
				Sfx.play_at("truck_door", global_position + forward() * -2.0, -2.0)
		State.OUT:
			_drive(dt, -1.0)
			_beep_t -= dt
			if _beep_t <= 0.0:
				_beep_t = 1.0
				Sfx.play_at("reverse_beep", global_position - forward() * 3.7, -8.0, false, 0.0)
			if s <= 0.05:
				_finish_run()
	if gate:
		gate.hold = state != State.AWAY and absf(global_position.z - gate.global_position.z) < 16.0
	for l in _lights:
		l.visible = state != State.AWAY
	if _tail_mat:
		_tail_mat.emission_energy_multiplier = 4.0 if (state == State.OUT or speed < 0.3) and state != State.AWAY else 1.5
	if state != State.AWAY:
		Sfx.loop_at("engine", "truck", global_position, -4.0 + (0.0 if speed > 0.5 else -6.0), 4.0, 55.0)
	else:
		Sfx.stop_loop("engine")


func _start_run() -> void:
	state = State.IN
	s = 0.0
	speed = 0.0
	visible = true
	_place(0.0)
	game.hud.hint_event("truck")


func _finish_run() -> void:
	state = State.AWAY
	next_t = PERIOD
	visible = false
	speed = 0.0
	_place(0.0)


func _drive(dt: float, dir: float) -> void:
	# where we'd be next, and whether someone is standing there
	var want := SPEED_ROAD if global_position.z < -24.0 else SPEED_YARD
	var ahead := global_position + forward() * dir * (LENGTH * 0.5 + 2.8)
	var blocked := false
	var p := game.player
	if p.alive and not carrying(p.global_position) and Vector2(p.global_position.x - ahead.x, p.global_position.z - ahead.z).length() < 2.4:
		blocked = true
	for sd in game.soldiers:
		if sd.alive and Vector2(sd.global_position.x - ahead.x, sd.global_position.z - ahead.z).length() < 2.4:
			blocked = true
			break
	if blocked:
		want = 0.0
	speed = move_toward(speed, want, dt * (2.2 if want > speed else 6.0))
	s = clampf(s + speed * dir * dt, 0.0, total)
	_place(s)
