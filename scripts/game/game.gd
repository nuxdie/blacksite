class_name Game
extends Node3D
## Mission flow and shared services: owns the world, the player, the guards, equipment in flight,
## and the rules for noise, sight and damage between them.

enum Phase { LOADING, MENU, PLAY, PAUSED, DEAD, DONE }

const SOLDIER_SCENE := preload("res://scenes/soldier.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")

const ROSTER := [
	{"squad": "yard", "type": "rifleman", "pos": Vector3(-22, 0, -14), "patrol": [[-22, -14], [-9, -1], [2, -12], [-12, -14]]},
	{"squad": "yard", "type": "rifleman", "pos": Vector3(-10, 0, -5), "yaw": 0.0},
	{"squad": "yard", "type": "rifleman", "pos": Vector3(-14, 3.7, 14), "yaw": 0.0},
	{"squad": "yard", "type": "rifleman", "pos": Vector3(-12.5, 0, -17.5), "yaw": 0.45, "access": ["security"]},
	{"squad": "yard", "type": "rifleman", "pos": Vector3(7.5, 4.5, -34.3), "yaw": 0.9},
	{"squad": "office", "type": "breacher", "pos": Vector3(-27, 0, 21.2), "patrol": [[-27, 21.2], [-3, 21.2]]},
	{"squad": "office", "type": "rifleman", "pos": Vector3(-15, 0, 27.5), "yaw": 0.0},
	{"squad": "office", "type": "rifleman", "pos": Vector3(-22, 0, 15), "yaw": -PI / 2},
	{"squad": "office", "type": "rifleman", "pos": Vector3(5, 0, 26), "patrol": [[5, 26], [5, 14], [-4, 8]]},
	{"squad": "wh", "type": "rifleman", "pos": Vector3(14, 0, -15), "patrol": [[14, -15], [36, -17], [36, 18], [16, 18]]},
	{"squad": "wh", "type": "rifleman", "pos": Vector3(14, 0, 4), "yaw": -PI / 2},
	{"squad": "wh", "type": "breacher", "pos": Vector3(26, 0, -9), "yaw": -PI / 2},
	{"squad": "wh", "type": "heavy", "pos": Vector3(28, 4.2, 26), "yaw": 0.0, "access": ["warehouse", "secure"]},
	{"squad": "wh", "type": "rifleman", "pos": Vector3(44, 4.2, 2), "yaw": -PI / 2},
	{"squad": "wh", "type": "rifleman", "pos": Vector3(42.5, 4.2, 27), "yaw": 0.0},
]
const REINFORCEMENTS := [
	{"squad": "qrf", "type": "heavy", "pos": Vector3(6, 0, 33)},
	{"squad": "qrf", "type": "rifleman", "pos": Vector3(4, 0, 34)},
	{"squad": "qrf", "type": "breacher", "pos": Vector3(8, 0, 34)},
	{"squad": "qrf", "type": "rifleman", "pos": Vector3(42, 0, -32)},
	{"squad": "qrf", "type": "rifleman", "pos": Vector3(-2, 0, -33)},
]
## Lines guards shout rather than send over the radio; everything else is squad net traffic.
const SHOUTED := ["contact", "heard", "nade", "nade_warn", "hit", "blind", "huh", "calm", "lights", "noise", "power", "body", "pulled", "smoke", "cover", "jammed"]
const INTERIORS := ["WAREHOUSE", "MEZZANINE", "DATA OFFICE", "OFFICE", "SERVER ROOM", "ARMOURY", "GATEHOUSE"]

var phase := Phase.LOADING
var facility: Facility
var fx: Fx
var player: Player
var hud: Hud
var menu: Menu
var soldiers: Array[Soldier] = []
var squads: Dictionary = {}
var gadgets: Array[Gadget] = []
var time := 0.0
var mission := "infil"
var detected := false
var reinforce_t := -1.0
var player_light := 1.0
var god_mode := false
var stats := {}
var _light_t := 0.0
var _last_line_t := -9.0
var _pending_radio: Array[Dictionary] = []
var _beacon: Node3D
var _test: TestRunner
var _shot_hit := false
var comms_down := false
## Access levels on the credentials you hold (taken or cloned badges).
var access: Dictionary = {}
## Security-level access: clean admin logins on the camera network.
var has_badge: bool:
	get:
		return access.has("security")
	set(v):
		if v:
			access["security"] = true
		else:
			access.erase("security")
var trace := 0.0
var tablet_access: Device = null
var tablet_admin := false
var tablet_cam := 0
var use_target: Device = null
var using := false
var use_progress: Dictionary = {}
## A finished hold has to be released before the next one starts (so popping a cover doesn't
## roll straight into cabling the port).
var _use_latch := false
var _repairs: Array[Dictionary] = []
var _body_scan_t := 0.0
var hq := Command.new(self)
var console := NetConsole.new()
## Multitool action in progress: {kind, door|soldier, time, label}, and its 0..1 progress.
var tool_target: Dictionary = {}
## What interact would do this tick, from focus().
var act: Dictionary = {}
var tool_progress := 0.0
var _spotted_t := -9.0
var _trace_warn_t := 0.0


func _ready() -> void:
	facility = Facility.new()
	add_child(facility)
	facility.build()
	fx = Fx.new()
	add_child(fx)
	player = PLAYER_SCENE.instantiate()
	player.game = self
	add_child(player)
	_build_beacon()
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	menu = Menu.new()
	menu.game = self
	add_child(menu)
	player.spawn(facility.player_start, facility.player_start_yaw)
	player.active = false
	facility.nav_ready.connect(_on_nav_ready)
	facility.bake_navigation.call_deferred()
	menu.show_loading()
	if OS.get_cmdline_user_args().size() > 0:
		_test = TestRunner.new()
		_test.game = self
		add_child(_test)


func _on_nav_ready() -> void:
	phase = Phase.MENU
	menu.show_title()
	if _test:
		_test.start()


func _build_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.position = facility.extraction
	var flare := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = 0.3
	flare.mesh = cm
	flare.material_override = Mats.emissive(Color("40ff60"), 6.0)
	flare.position.y = 0.15
	_beacon.add_child(flare)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.75
	tm.outer_radius = 3.9
	tm.rings = 64
	ring.mesh = tm
	var rm := Mats.emissive(Color("40ff60"), 1.5)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0, 0, 0, 0.5)
	ring.material_override = rm
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.03
	_beacon.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color("40ff60")
	light.light_energy = 1.5
	light.omni_range = 12.0
	light.position.y = 0.6
	_beacon.add_child(light)
	_beacon.visible = false
	add_child(_beacon)


# ------------------------------------------------------------------ flow

func start_mission() -> void:
	for s in soldiers:
		s.queue_free()
	soldiers.clear()
	squads.clear()
	for g in gadgets:
		g.queue_free()
	gadgets.clear()
	_pending_radio.clear()
	facility.reset_props()
	fx.clear()
	for r: Dictionary in ROSTER:
		_spawn(r)
	time = 0.0
	mission = "infil"
	detected = false
	reinforce_t = -1.0
	comms_down = false
	access.clear()
	trace = 0.0
	tablet_access = null
	player.in_tablet = false
	use_target = null
	using = false
	use_progress.clear()
	_repairs.clear()
	hq.reset()
	console.game = self
	console.close()
	tool_target = {}
	tool_progress = 0.0
	act = {}
	stats = {"hacks": 0, "shots": 0, "hits": 0, "heads": 0, "kills": 0, "takedowns": 0, "damage_taken": 0.0, "enemy_shots": 0, "enemy_hits": 0}
	_spotted_t = -9.0
	Sfx.set_muffle(0.0)
	for id: String in ["tool", "use", "copy", "term"]:
		Sfx.stop_loop(id, 400.0)
	player.spawn(facility.player_start, facility.player_start_yaw)
	player.active = true
	_beacon.visible = false
	hud.reset()
	phase = Phase.PLAY
	menu.hide_all()
	hud.visible = true
	_capture(true)


func spawn_soldier(r: Dictionary) -> Soldier:
	return _spawn(r)


func set_beacon(on: bool) -> void:
	_beacon.visible = on


func quicksave() -> void:
	if phase != Phase.PLAY or not player.alive:
		return
	if SaveGame.save(self):
		Sfx.ui("save", -6.0)
		hud.toast("QUICKSAVED", false)
		hud.learn("quicksave")


func quickload() -> void:
	if not SaveGame.exists():
		hud.toast("NO QUICKSAVE")
		return
	SaveGame.load_into(self)
	Sfx.ui("load", -6.0)
	hud.toast("QUICKLOADED", false)


func _spawn(r: Dictionary) -> Soldier:
	var s: Soldier = SOLDIER_SCENE.instantiate()
	var sq_id: String = r.squad
	if not squads.has(sq_id):
		squads[sq_id] = Squad.new(sq_id)
	s.game = self
	s.setup(load("res://resources/soldiers/%s.tres" % r.type), squads[sq_id], r.pos, r.get("yaw", 0.0), r.get("patrol", []))
	var default_access := {"yard": [], "office": ["office"], "wh": ["warehouse"], "qrf": ["security", "warehouse", "office"]}
	var acc: Array = r.get("access", default_access.get(sq_id, []))
	for a: String in acc:
		s.badge.append(a)
	var sq_n := (squads[sq_id] as Squad).members.size()
	s.callsign = "%s %d" % [{"yard": "Gate", "office": "Office", "wh": "Warehouse", "qrf": "Reaction"}.get(sq_id, "Post"), sq_n]
	s.call_order = soldiers.size()
	s.voice = Lines.guard_voice(s.call_order)
	add_child(s)
	soldiers.append(s)
	return s


func pause() -> void:
	if phase != Phase.PLAY:
		return
	phase = Phase.PAUSED
	player.active = false
	weapons_release()
	get_tree().paused = false
	Sfx.ui("pause", -6.0)
	menu.show_pause()
	hud.visible = false
	_capture(false)


func resume() -> void:
	if phase != Phase.PAUSED:
		return
	phase = Phase.PLAY
	player.active = true
	Sfx.ui("pause", -8.0)
	menu.hide_all()
	hud.visible = true
	_capture(true)


func weapons_release() -> void:
	player.weapons.aiming_throw = false
	player.drag_body = null


func to_menu() -> void:
	phase = Phase.MENU
	player.active = false
	hud.visible = false
	menu.show_title()
	_capture(false)


func on_player_died() -> void:
	player.active = false
	Sfx.play("death", -2.0)
	for id: String in ["tool", "use", "term"]:
		Sfx.stop_loop(id)
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if phase != Phase.PLAY:
			return
		phase = Phase.DEAD
		hud.visible = false
		menu.show_debrief(false, _rating())
		_capture(false))


func _complete() -> void:
	phase = Phase.DONE
	player.active = false
	Sfx.ui("extracted", -4.0)
	if Settings.best_time < 0.0 or time < Settings.best_time:
		Settings.best_time = time
		Settings.save_settings()
	hud.visible = false
	menu.show_debrief(true, _rating())
	_capture(false)


func bodies_found() -> int:
	return soldiers.filter(func(s: Soldier) -> bool: return not s.alive and s.corpse_found).size()


func _rating() -> String:
	var acc := float(stats.hits) / maxf(1.0, float(stats.shots))
	if not detected and hq.stats.alarms == 0 and bodies_found() == 0:
		return "GHOST"
	if hq.stats.alarms == 0:
		return "QUIET PROFESSIONAL"
	if stats.damage_taken < 60.0 and acc > 0.45:
		return "SURGICAL"
	return "PROFESSIONAL" if stats.damage_taken < 150.0 else "SURVIVOR"


func _capture(on: bool) -> void:
	if _test:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.PLAY and tablet_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quicksave"):
		quicksave()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quickload") and (phase == Phase.PLAY or phase == Phase.DEAD):
		quickload()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if phase == Phase.PLAY:
			pause()
		elif phase == Phase.PAUSED:
			resume()
		get_viewport().set_input_as_handled()
	elif phase == Phase.PLAY and event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _test:
		_capture(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase == Phase.PLAY and not _test:
		pause()


# ------------------------------------------------------------------ simulation

func _physics_process(dt: float) -> void:
	if phase != Phase.PLAY and phase != Phase.DEAD:
		return
	var sdt := dt if player.alive else dt * 0.5
	time += sdt
	_light_t -= sdt
	if _light_t <= 0.0:
		_light_t = 0.25
		player_light = facility.light_level(player.global_position, _flashlights())
		_tick_spotting()
	player.tick(sdt)
	for s in soldiers:
		s.tick(sdt)
	_separate()
	_tick_gadgets(sdt)
	_tick_pickups()
	_tick_radio()
	_tick_devices(sdt)
	for dr in facility.drones:
		dr.tick(sdt, self)
	hq.tick(sdt)
	_tick_mission(sdt)
	_tick_audio_state(sdt)


func _process(dt: float) -> void:
	if phase == Phase.PLAY or phase == Phase.DEAD or phase == Phase.LOADING or phase == Phase.MENU:
		player.update_camera(dt)
	if phase == Phase.PLAY:
		hud.refresh(dt)


func _flashlights() -> Array:
	var out: Array = facility.searchlights.filter(func(sl: SpotLight3D) -> bool: return sl.visible)
	for s in soldiers:
		if s.alive and s.model.flashlight.visible:
			out.append(s.model.flashlight)
	for dr in facility.drones:
		if dr.scanning() and dr._cone.visible:
			out.append(dr._cone)
	return out


func _separate() -> void:
	for s in soldiers:
		if not s.alive:
			continue
		for o in soldiers:
			if o == s or not o.alive:
				continue
			var d := Vector2(s.global_position.x - o.global_position.x, s.global_position.z - o.global_position.z)
			if d.length() > 0.001 and d.length() < 0.7 and absf(s.global_position.y - o.global_position.y) < 1.5:
				var k := (0.7 - d.length()) / d.length() * 0.5
				s.global_position += Vector3(d.x * k, 0, d.y * k)


func _tick_mission(dt: float) -> void:
	if reinforce_t > 0.0:
		reinforce_t -= dt
		if reinforce_t <= 0.0:
			Sfx.play_at("truck", Vector3(6, 1, 33))
			for k in 3:
				get_tree().create_timer(2.4 + k * 0.45).timeout.connect(func() -> void: Sfx.play_at("truck_door", Vector3(6 + k, 1, 33), 0.0))
			hq.announce("qrf")
			for r: Dictionary in REINFORCEMENTS:
				var s := _spawn(r)
				s.state = Soldier.State.COMBAT
				s.react = randf_range(0.5, 1.5)
			var q: Squad = squads["qrf"]
			q.report(player.global_position if hq.level == Command.Level.ALARM else facility.intel_pos, time - 4.0)
	if mission == "extract":
		_beacon.rotate_y(dt * 0.5)
		if player.alive and Vector2(player.global_position.x - facility.extraction.x, player.global_position.z - facility.extraction.z).length() < 4.0:
			_complete()


func objective_target() -> Vector3:
	return facility.intel_pos if mission == "infil" else facility.extraction


func objective_text() -> String:
	if mission != "infil":
		return "EXTRACT — WEST BREACH"
	for dv in facility.devices:
		if dv.kind == Device.Kind.LAPTOP:
			if dv.copy_state == "copying":
				return "KEEP GUARDS AWAY FROM THE LAPTOP"
			if dv.copy_state == "done":
				return "RETRIEVE THE DRIVE"
	return "COPY THE DATA"


func _take_intel() -> void:
	mission = "extract"
	Sfx.play("objective")
	hud.banner("DRIVE RECOVERED")
	_beacon.visible = true


# ------------------------------------------------------------------ sight & sound

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q)


func los(a: Vector3, b: Vector3) -> bool:
	if a.distance_squared_to(b) < 0.0001:
		return true
	return ray(a, b).is_empty()


func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for g in gadgets:
		var s := g.smoke_sphere()
		if s.w <= 0.0:
			continue
		var c := Vector3(s.x, s.y, s.z)
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < s.w * 0.8:
			return true
	return false


func say(s: Soldier, kind: String, force := false) -> void:
	if not s.alive:
		return
	if not force and (s.voice_t > 0.0 or time - _last_line_t < 0.9):
		return
	var texts := Lines.guard(kind)
	if texts.is_empty():
		return
	s.voice_t = 4.0
	_last_line_t = time
	if player.global_position.distance_to(s.global_position) > 45.0 and kind != "nade":
		return
	var i := randi() % texts.size()
	_line(s, kind, i, "", texts[i], not comms_down and not SHOUTED.has(kind))


## A guard answering the radio check, in the voice that callsign always has.
func checkin(s: Soldier, i: int) -> void:
	var texts := Lines.guard("check_in")
	if texts.is_empty():
		return
	_line(s, "check_in", i, Lines.slug(s.callsign), texts[i] % s.callsign, not comms_down)


## A guard's line: heard in person when they are close; otherwise, if it went over the net, through
## the nearest radio within earshot (a guard's, or a body's).
func _line(s: Soldier, kind: String, i: int, slug: String, text: String, over_radio: bool) -> void:
	var d := player.global_position.distance_to(s.global_position)
	var path := ""
	var radio := false
	var pos := s.eye()
	if d < 22.0 or not over_radio:
		path = Sfx.voice_path(s.voice, kind, i, slug, false)
	else:
		var r := nearest_radio()
		if r == null:
			return
		path = Sfx.voice_path(s.voice, kind, i, slug, true)
		radio = true
		pos = radio_pos(r)
	if path == "":
		Sfx.play_at("radio", pos, -4.0)
	s.speaking(Sfx.speak(path, pos, radio, -3.0 if radio else 0.0))
	s.voice_t = maxf(1.5, Sfx.voice_length(path) + 0.6)
	hud.subtitle(s.callsign, text, radio)


## Any radio within earshot: a guard, or a body still wearing one.
func nearest_radio() -> Soldier:
	var best: Soldier = null
	var bd := 22.0
	for o in soldiers:
		var d := o.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = o
	return best


func radio_pos(r: Soldier) -> Vector3:
	return r.eye() if r.alive else r.global_position + Vector3.UP * 0.3


## HQ and the security desk only reach you through a radio nearby. Priority traffic opens with
## the two-tone alert. Returns false when nobody near you is carrying a radio.
func net_say(who: String, voice: String, kind: String, i: int, slug: String, text: String, priority := false) -> bool:
	var r := nearest_radio()
	if r == null:
		return false
	var pos := radio_pos(r)
	var path := Sfx.voice_path(voice, kind, i, slug, true)
	if priority:
		Sfx.play_at("hq_tone", pos, -8.0, false, 0.0)
		get_tree().create_timer(0.45).timeout.connect(func() -> void: Sfx.speak(path, pos, true, -3.0))
	else:
		Sfx.speak(path, pos, true, -3.0)
	hud.subtitle(who, text, true)
	return true


## The security desk reports what a camera or drone saw.
func security_say(kind: String, label: String) -> void:
	var texts := Lines.security(kind)
	if texts.is_empty():
		return
	var i := randi() % texts.size()
	net_say("SECURITY", Lines.security_voice(), kind, i, Lines.slug(label), texts[i] % label)


## The moment someone confirms you: once, not for every guard in the squad.
func spotted_cue() -> void:
	if time - _spotted_t > 2.5:
		_spotted_t = time
		Sfx.ui("spotted", -6.0)


func lost_cue() -> void:
	Sfx.ui("lost_you", -8.0)


## What the mix should say about the state of the night: tension beds, indoors or out, and the
## machines that keep running (searchlight motors, the laptop copying, the terminal, trace).
func _tick_audio_state(dt: float) -> void:
	var level := 0.0
	for s in soldiers:
		if not s.alive:
			continue
		if s.state == Soldier.State.COMBAT:
			level = 2.0
			break
		if s.state == Soldier.State.SUSPICIOUS or s.aware > 0.15:
			level = maxf(level, 1.0)
	if level < 2.0:
		for dv in facility.devices:
			if dv.camera_live() and dv.aware > 0.1:
				level = maxf(level, 1.0)
		for dr in facility.drones:
			if dr.scanning() and dr.aware > 0.1:
				level = maxf(level, 2.0 if dr.mode == Drone.Mode.TRACK else 1.0)
	if not player.alive:
		level = 0.0
	Sfx.tension(level, dt)
	Sfx.interior(1.0 if facility.area_name(player.global_position) in INTERIORS else 0.0, dt)
	for i in facility.searchlights.size():
		var sl := facility.searchlights[i]
		if sl.visible:
			Sfx.loop_at("searchlight%d" % i, "motor", sl.global_position, -12.0, 3.0, 28.0)
		else:
			Sfx.stop_loop("searchlight%d" % i)
	var lap := laptop()
	if lap and lap.copy_state == "copying":
		Sfx.loop_at("copy", "copy_loop", lap.global_position + Vector3.UP * 0.1, -10.0, 1.5, 14.0)
	else:
		Sfx.stop_loop("copy")
	if tablet_access:
		Sfx.loop("term", "term_hum", -14.0)
		if trace > 70.0:
			_trace_warn_t -= dt
			if _trace_warn_t <= 0.0:
				_trace_warn_t = 1.6
				Sfx.ui("term_trace", -8.0)
	else:
		Sfx.stop_loop("term")


func laptop() -> Device:
	for dv in facility.devices:
		if dv.kind == Device.Kind.LAPTOP:
			return dv
	return null


func radio_alert(s: Soldier, delay: float) -> void:
	if comms_down:
		return
	_pending_radio.append({"s": s, "t": time + delay})


## Shouting carries without a radio: nearby guards of any squad hear it.
func shout(from: Soldier, pos: Vector3) -> void:
	for o in soldiers:
		if o == from or not o.alive or o.state == Soldier.State.COMBAT:
			continue
		var d := o.global_position.distance_to(from.global_position)
		if d < 12.0 or (d < 28.0 and los(o.eye(), from.eye())):
			o.alert(pos, "shout")


func _tick_radio() -> void:
	for i in range(_pending_radio.size() - 1, -1, -1):
		var r: Dictionary = _pending_radio[i]
		if time >= float(r.t):
			_pending_radio.remove_at(i)
			if r.has("release"):
				var sq: Squad = r.release
				if sq.flanker == r.s:
					sq.flanker = null
					sq.flank_cooldown = time + 6.0
				continue
			var s: Soldier = r.s
			if is_instance_valid(s) and s.alive and s.state != Soldier.State.COMBAT:
				s.alert(s.squad.last_known, "radio")


## Lets a squad pick a new flanker a few seconds after this one reaches position.
func release_flanker_later(sq: Squad, s: Soldier) -> void:
	_pending_radio.append({"release": sq, "s": s, "t": time + 5.0})


## quiet = suppressed: only guards right next to it recognise gunfire; others just hear something.
func hear_gunshot(pos: Vector3, radius: float, quiet := false) -> void:
	for s in soldiers:
		if not s.alive:
			continue
		var d := s.global_position.distance_to(pos)
		if d > radius:
			continue
		if quiet:
			if s.state == Soldier.State.COMBAT:
				continue
			if d < 3.5:
				s.alert(pos, "heard")
			else:
				s.make_suspicious(pos, 0.6, "huh", 0.4)
			continue
		var clear := d < 20.0 or los(s.eye(), pos + Vector3.UP * 1.2)
		if s.state == Soldier.State.COMBAT:
			if s.squad.since_seen(time) > 2.5:
				s.squad.report(pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), time - 1.0)
		elif clear:
			s.alert(pos, "heard")
		else:
			s.make_suspicious(pos, 0.7)


## Bullet impacts are audible close by, even from a suppressed weapon.
func impact_noise(pt: Vector3) -> void:
	for s in soldiers:
		if s.alive and s.state != Soldier.State.COMBAT and s.global_position.distance_to(pt) < 5.0:
			s.make_suspicious(pt, 0.5, "huh", 0.6)


# ------------------------------------------------------------------ shooting

func player_shot(o: Vector3, d: Vector3, w: WeaponData, first := true) -> void:
	if first:
		_shot_hit = false
	var space := get_world_3d().direct_space_state
	var res := Ballistics.trace(space, o, d, w.penetration, 300.0,
		func(oo: Vector3, dd: Vector3, max_t: float) -> Dictionary:
			var best := {}
			for s in soldiers:
				if not s.alive:
					continue
				for z: Array in s.zones():
					var t := Ballistics.ray_sphere(oo, dd, z[1], z[2])
					var bonus := 0.12 if z[0] == "head" else 0.0
					if t >= 0.0 and t < max_t and (best.is_empty() or t < float(best.t) - bonus):
						best = {"t": t, "soldier": s, "zone": z[0]}
			var lt: float = best.t if not best.is_empty() else max_t
			for l in facility.lamps:
				if l.dead:
					continue
				var t2 := Ballistics.ray_sphere(oo, dd, l.global_position, 0.3)
				if t2 >= 0.0 and t2 < lt:
					best = {"t": t2, "lamp": l}
					lt = t2
			for c in cameras():
				if c.destroyed:
					continue
				var t3 := Ballistics.ray_sphere(oo, dd, c.head.global_position, 0.2)
				if t3 >= 0.0 and t3 < lt:
					best = {"t": t3, "camera": c}
					lt = t3
			for dr in facility.drones:
				if dr.destroyed:
					continue
				var t4 := Ballistics.ray_sphere(oo, dd, dr.global_position, 0.26)
				if t4 >= 0.0 and t4 < lt:
					best = {"t": t4, "drone": dr}
					lt = t4
			return best,
		func(pt: Vector3, n: Vector3, is_exit: bool, mat: String) -> void:
			fx.hole(pt, n)
			fx.burst("dust", pt, n)
			if not is_exit:
				if mat in Mats.METALLIC:
					fx.burst("spark", pt, n)
				if player.camera.global_position.distance_to(pt) < 25.0:
					Sfx.play_at("impact_metal" if mat in Mats.METALLIC else "impact", pt, -4.0)
				impact_noise(pt))
	var end: Vector3 = res.end
	var end_t := o.distance_to(end)
	if first and randf() < w.tracer_chance:
		fx.tracer(o + d * 1.2 + player.right() * 0.08 + Vector3.DOWN * 0.08, end)
	var tgt: Dictionary = res.get("target", {})
	# near misses pin guards down
	for s in soldiers:
		if not s.alive or tgt.get("soldier") == s:
			continue
		var hp := s.head_pos()
		var t := clampf((hp - o).dot(d), 0.0, end_t)
		var miss := (o + d * t).distance_to(hp)
		if miss < 1.4:
			s.supp = minf(1.0, s.supp + 0.3 * (1.4 - miss))
			if s.state != Soldier.State.COMBAT:
				if w.suppressed:
					impact_noise(hp)
				else:
					s.alert(player.global_position, "heard")
	if tgt.is_empty():
		return
	if tgt.has("lamp"):
		_break_lamp(tgt.lamp)
		return
	if tgt.has("drone"):
		(tgt.drone as Drone).take_hit(w.damage)
		fx.burst("spark", end)
		return
	if tgt.has("camera"):
		var cam: Device = tgt.camera
		cam.shoot_out()
		fx.burst("spark", cam.head.global_position)
		# a feed that suddenly dies gets noticed in the security office
		if not comms_down:
			security_say("cam_lost", cam.label)
			_dispatch(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, cam.global_position), "investigate", 1)
		return
	if not _shot_hit:
		stats.hits += 1
		_shot_hit = true
	var s: Soldier = tgt.soldier
	var zone: String = tgt.zone
	var dmg := Ballistics.zone_damage(w, zone, s.profile.helmet, s.profile.armor, end_t, float(res.mul))
	if zone == "head":
		stats.heads += 1
		if s.profile.helmet < 1.0:
			Sfx.play_at("helmet", end, 0.0, false)
	Sfx.play_at("flesh", end, 0.0, false)
	fx.burst("blood", end, -d)
	s.take_hit(dmg, d, zone, true, w.suppressed)


func _break_lamp(l: Lamp) -> void:
	l.shatter()
	fx.burst("glass", l.global_position, Vector3.DOWN)
	light_killed(l, true)


## Guards near a lamp notice the dark; breaking glass is far more alarming than a dead fixture.
func light_killed(l: Lamp, loud: bool) -> void:
	_light_t = 0.0
	hud.learn("lights")
	for s in soldiers:
		if s.alive and s.state != Soldier.State.COMBAT and s.global_position.distance_to(l.global_position) < (16.0 if loud else 12.0):
			var below := l.global_position
			below.y = s.global_position.y
			s.make_suspicious(below, 0.5 if loud else 0.3, "lights")


func soldier_shot(s: Soldier, target: Vector3, extra: float, suppressive: bool) -> void:
	var muzzle := s.model.muzzle.global_position
	stats.enemy_shots += 1
	var prof := s.profile
	var w := s.weapon
	var base := (target - muzzle).normalized()
	Sfx.play_at("enemy_" + prof.weapon_kind, muzzle, 2.0 if prof.weapon_kind == "lmg" else 0.0)
	fx.muzzle(muzzle, 0.7 if prof.weapon_kind == "lmg" else 0.55)
	if randf() < 0.5:
		fx.flash_light(muzzle, Color("ffb060"), 2.5, 0.05, 7.0)
	var space := get_world_3d().direct_space_state
	var eye := player.eye_pos()
	var center := Ballistics.spread(base, s.aim_err * prof.spread_mult + extra)
	for i in w.pellets:
		var d := Ballistics.spread(center, w.hip_spread * 0.6) if w.pellets > 1 else center
		var first := i == 0
		var res := Ballistics.trace(space, muzzle, d, w.penetration, 160.0,
			func(oo: Vector3, dd: Vector3, max_t: float) -> Dictionary:
				if not player.alive:
					return {}
				var h := player.ray_hit(oo, dd)
				return h if not h.is_empty() and float(h.t) < max_t else {},
			func(pt: Vector3, n: Vector3, is_exit: bool, mat: String) -> void:
				if pt.distance_to(player.global_position) < 30.0 and (first or randf() < 0.3):
					fx.hole(pt, n)
					fx.burst("dust", pt, n)
					if not is_exit and pt.distance_to(eye) < 8.0:
						Sfx.play_at("impact_metal" if mat in Mats.METALLIC else "impact", pt, -2.0))
		var end: Vector3 = res.end
		var end_t := muzzle.distance_to(end)
		if first or randf() < 0.3:
			fx.tracer(muzzle, end)
		var tgt: Dictionary = res.get("target", {})
		if not tgt.is_empty():
			var zone: String = tgt.zone
			stats.enemy_hits += 1
			player.take_damage(Ballistics.zone_damage(w, zone, Player.HELMET, Player.ARMOR, end_t, float(res.mul)), muzzle, int(res.pens) > 0, zone)
		else:
			var t := clampf((eye - muzzle).dot(d), 0.0, end_t)
			var cp := muzzle + d * t
			var miss := cp.distance_to(eye)
			if miss < 1.8 and player.alive and first:
				player.near_miss((0.16 if suppressive else 0.1) * (1.8 - miss) / 1.8, cp)
	# gunfire draws other squads in
	for o in soldiers:
		if o.alive and o.state == Soldier.State.CALM and o.squad != s.squad and o.global_position.distance_to(s.global_position) < 45.0:
			o.make_suspicious(s.global_position, 0.6, "huh", 0.8)


# ------------------------------------------------------------------ equipment

func spawn_gadget(type: String, pos: Vector3, vel: Vector3, from_player: bool) -> Gadget:
	var g := Gadget.create(type, from_player)
	add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	g.gravity_scale = 20.0 / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	g.detonated.connect(_on_detonate)
	gadgets.append(g)
	return g


func enemy_throw(from: Vector3, target: Vector3) -> void:
	var dist := Vector2(target.x - from.x, target.z - from.z).length()
	var apex := maxf(from.y, target.y) + 2.5
	var vy := sqrt(2.0 * 20.0 * (apex - from.y))
	var tt := vy / 20.0 + sqrt(2.0 * (apex - target.y) / 20.0)
	var v := Vector3((target.x - from.x) / tt, vy, (target.z - from.z) / tt)
	var g := spawn_gadget("frag", from, v, false)
	g.fuse = maxf(2.2, tt + 1.4)
	if dist < 0.1:
		g.linear_velocity = Vector3.UP


func _tick_gadgets(dt: float) -> void:
	for i in range(gadgets.size() - 1, -1, -1):
		var g := gadgets[i]
		if not g.step(dt):
			gadgets.remove_at(i)
			g.queue_free()
			continue
		if g.type == "frag" and not g.live and g.fuse < 2.4:
			for s in soldiers:
				if not s.alive or s.flee_from or s.blind > 0.0 or s.global_position.distance_to(g.global_position) > 7.5:
					continue
				if not g.owner_is_player and s.global_position.distance_to(g.global_position) > 5.0:
					continue
				if randf() < dt * 3.0 and los(s.eye(), g.global_position + Vector3.UP * 0.2):
					s.flee(g)
		elif g.type == "decoy" and g.live and g.tick <= 0.0:
			g.tick = randf_range(0.35, 0.6)
			Sfx.play_at("decoy", g.global_position)
			for s in soldiers:
				if s.alive and s.state != Soldier.State.COMBAT and s.global_position.distance_to(g.global_position) < 20.0:
					s.make_suspicious(g.global_position, 0.55, "noise", 0.4)
					s.susp_t = minf(s.susp_t, 1.2)


## An explosion: hurts everyone in the radius with a line to it, rattles everyone nearby.
func blast(p: Vector3, radius: float, soldier_dmg: float, player_dmg: float, by_player: bool) -> void:
	fx.explosion(p)
	Sfx.play_at("explode", p, 4.0, false)
	for s in soldiers:
		if not s.alive:
			continue
		var c := s.global_position + Vector3.UP
		var d := c.distance_to(p)
		if d < radius and los(p, c):
			s.take_hit(soldier_dmg * pow(1.0 - d / radius, 1.2), (c - p).normalized(), "body", by_player)
	var pc := player.chest_pos()
	var dp := pc.distance_to(p)
	if dp < radius and los(p, pc):
		player.take_damage(player_dmg * pow(1.0 - dp / radius, 1.3), p)
	if dp < radius * 2.0:
		player.supp = minf(1.0, player.supp + 0.8 * (1.0 - dp / (radius * 2.0)))
	var cd := player.camera.global_position.distance_to(p)
	if cd < 30.0:
		player.trauma = minf(1.0, player.trauma + 0.6 * (1.0 - cd / 30.0))
	hear_gunshot(p, 60.0)


func _on_detonate(g: Gadget) -> void:
	var p := g.global_position + Vector3.UP * 0.15
	match g.type:
		"frag":
			fx.hole(g.global_position + Vector3.UP * 0.05, Vector3.UP, 9.0, true)
			blast(p, 7.5, 190.0, 150.0, g.owner_is_player)
		"flash":
			Sfx.play_at("bang", p, 4.0, false)
			fx.flash_light(p, Color.WHITE, 30.0, 0.3, 28.0)
			fx.burst("spark", p)
			for s in soldiers:
				if not s.alive:
					continue
				var e := s.eye()
				var d := e.distance_to(p)
				if d > 15.0 or not los(p, e) or smoke_blocks(p, e):
					continue
				var to := (p - e).normalized()
				var facing := to.x * s.facing().x + to.z * s.facing().z
				var k := (1.0 - d / 15.0) * (1.0 if facing > 0.0 else 0.35)
				if k < 0.1:
					continue
				s.blind = maxf(s.blind, 1.0 + 4.5 * k)
				s.flinch = 0.5
				s.peeking = false
				s.burst = 0
				if s.state != Soldier.State.COMBAT:
					s.alert(player.global_position, "heard")
					s.react = 0.0
				say(s, "blind", true)
			var eye := player.eye_pos()
			var dp := eye.distance_to(p)
			if dp < 18.0 and los(p, eye):
				var face := player.view_dir().dot((p - eye).normalized())
				var k2 := (1.0 - dp / 18.0) * clampf((face + 0.3) / 1.3, 0.12, 1.0)
				hud.flash = maxf(hud.flash, k2 * 1.8)
				Sfx.play("ring", linear_to_db(clampf(k2, 0.05, 1.0)), 0.0)
			hear_gunshot(p, 35.0)


# ------------------------------------------------------------------ interaction

# ------------------------------------------------------------------ networks, power, comms

## The one thing interact does right now. Everything hangs off one key, so the prompt, the press
## and the hold all read this instead of checking the targets separately and disagreeing.
## Takedown first; then whichever aimed thing (pickup, device, badge clone) you look at most squarely;
## then the proximity-only things (splice, drag body). Looking at something is how you choose.
## Ladders aren't here: you climb one by walking into it.
func focus() -> Dictionary:
	if not player.alive or tablet_access:
		return {}
	if player.ladder:
		return {"kind": "letgo", "label": "Let go"}
	if player.drag_body:
		return {"kind": "drop", "label": "Release to drop"}
	var t := takedown_target()
	if t:
		return {"kind": "takedown", "soldier": t, "label": "Takedown"}
	# aimed things compete on how squarely you're looking at them: a gun lying beside a body
	# is the pickup when you look at the gun and the badge clone when you look at the body
	var cands := []
	var p := interact_target()
	if p:
		cands.append([_aim(p.global_position + Vector3.UP * 0.15), {"kind": "pickup", "pickup": p, "label": p.label()}])
	# a device you can't work yet still names itself, but only if nothing else wants the key
	var dev := {}
	if use_target:
		dev = {"kind": "use", "device": use_target, "ok": use_target.can_use(self), "hold": use_target.use_time(self) > 1.0, "label": use_target.use_label(self)}
		if dev.ok:
			cands.append([_aim(use_target.use_point()), dev])
	var tool := tool_action()
	if tool.get("kind") == "clone":
		var s: Soldier = tool.soldier
		cands.append([_aim(s.global_position + Vector3.UP * (1.0 if s.alive else 0.3)), tool])
	if not cands.is_empty():
		cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		return cands[0][1]
	# then the things that only need you to stand in the right place
	if tool.get("kind") == "splice":
		return tool
	var c := corpse_near()
	if c:
		return {"kind": "drag", "soldier": c, "label": "Hold to drag body"}
	return dev


## How squarely the player is looking at a point: 1 dead on, 0 at ninety degrees.
func _aim(point: Vector3) -> float:
	return (point - player.eye_pos()).normalized().dot(player.view_dir())


## The physical device in reach that interact would use, or null.
func find_use_target() -> Device:
	if not player.alive or player.drag_body or player.vault_t >= 0.0 or tablet_access:
		return null
	var eye := player.eye_pos()
	var d := player.view_dir()
	var best: Device = null
	var best_dot := 0.72
	for dv in facility.devices:
		if dv.kind == Device.Kind.CAMERA or dv.use_label(self) == "":
			continue
		var to := dv.use_point() - eye
		if to.length() > 2.3:
			continue
		var dot := to.normalized().dot(d)
		if dot > best_dot:
			best_dot = dot
			best = dv
	return best


## A ladder that takes you as you walk into it: up against its rungs anywhere along its height, or
## at the top edge stepping back onto it. `push` is the direction you're moving.
func ladder_touch(push: Vector3) -> Ladder:
	if not player.alive or player.ladder or player.drag_body or push.length() < 0.2:
		return null
	var p := player.global_position
	var flat := Vector3(push.x, 0.0, push.z).normalized()
	for l in facility.ladders:
		var on := l.climb_point(p.y)
		if p.y > l.global_position.y - 0.3 and p.y < l.top_y() - 0.3 and Vector2(p.x - on.x, p.z - on.z).length() < 0.75:
			if flat.dot(-l.normal) > 0.5:
				return l
		if absf(p.y - l.top_y()) < 0.6 and Vector2(p.x - l.top_exit.x, p.z - l.top_exit.z).length() < 1.0:
			var back := l.climb_point(l.top_y()) - l.top_exit
			back.y = 0.0
			if flat.dot(back.normalized()) > 0.6:
				return l
	return null


func has_access(level: String) -> bool:
	return access.has(level)


## A door at the player's feet that won't open for them.
func refused_door() -> Door:
	for d in facility.doors:
		if d.refused:
			return d
	return null


func _tick_devices(dt: float) -> void:
	for dv in facility.devices:
		dv.tick(dt, self)
	for d in facility.doors:
		d.tick(dt, self)
	facility.tick_searchlights(dt)
	trace = maxf(0.0, trace - dt * (0.4 if tablet_access else 1.5))
	use_target = find_use_target()
	act = focus()
	using = false
	if not Input.is_action_pressed("interact"):
		_use_latch = false
	if act.get("kind") == "use" and act.ok and player.active:
		if Input.is_action_pressed("interact") and not _use_latch:
			using = true
			var prog: float = use_progress.get(use_target, 0.0) + dt / use_target.use_time(self)
			use_progress[use_target] = prog
			if prog >= 1.0:
				use_progress.erase(use_target)
				var dv := use_target
				use_target = null
				using = false
				_use_latch = true
				dv.on_used(self)
	if using and use_target:
		Sfx.loop_at("use", use_target.use_sound(), use_target.use_point(), -10.0, 1.5, 12.0)
	else:
		Sfx.stop_loop("use")
	if act.get("kind") in ["clone", "splice"] and not _use_latch:
		_tick_tool(dt, act)
	else:
		tool_target = {}
		tool_progress = 0.0
		Sfx.stop_loop("tool")
	player.hacking = using or not tool_target.is_empty()
	if tablet_access:
		_tick_tablet(dt)
	_tick_repairs()
	_tick_laptop_watch()
	# cameras that are still watching spot bodies too
	_body_scan_t -= dt
	if _body_scan_t <= 0.0:
		_body_scan_t = 1.0
		for c in soldiers:
			if c.alive or c.corpse_found or c.death_t < 0.5:
				continue
			for dv in facility.devices:
				if dv.global_position.distance_to(c.global_position) < 22.0 and dv.sees_point(self, c.global_position + Vector3.UP * 0.3):
					c.corpse_found = true
					_dispatch(c.global_position, "body")
					break


## A drone just confirmed you: same as a camera alarm, HQ raises the alarm if comms are up.
func drone_alarm(dr: Drone) -> void:
	Sfx.play_at("alarm", dr.global_position, 0.0, false)
	spotted_cue()
	hud.hint_event("drone_alarm")
	if comms_down:
		return
	security_say("drone", dr.label)
	_dispatch(player.global_position, "saw")
	hq.camera_contact(player.global_position)


func drone_report(_dr: Drone) -> void:
	if comms_down:
		return
	for sq: Squad in squads.values():
		if sq.alive_members().any(func(m: Soldier) -> bool: return m.state == Soldier.State.COMBAT):
			sq.report(player.global_position, time)


## A hit drone turns on you: it dives and blows itself up on contact.
func drone_dive(dr: Drone) -> void:
	hud.hint_event("drone_dive")
	Sfx.play_at("drone_lock", dr.global_position, 2.0, false, 0.0)


## A diving drone went off: a small charge, nasty up close.
func drone_exploded(dr: Drone, at: Vector3, was_watching: bool) -> void:
	blast(at, 5.0, 120.0, 85.0, false)
	fx.hole(at, Vector3.UP, 4.0, true)
	drone_destroyed(dr, was_watching)


func drone_destroyed(dr: Drone, was_watching: bool) -> void:
	Sfx.play_at("glass", dr.global_position)
	Sfx.play_at("drone_down", dr.global_position, 0.0, false)
	if was_watching and not comms_down:
		# losing a drone mid-track is a report in itself
		_dispatch(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, dr.global_position), "investigate", 1)
		hq.caution("drone lost")


func cameras() -> Array[Device]:
	var out: Array[Device] = []
	for dv in facility.devices:
		if dv.kind == Device.Kind.CAMERA:
			out.append(dv)
	return out


# --- the tablet: a live session on the security network

## Put the nettop down at an access port and cable it up. The console logs itself in: a badge
## is clean and gives admin, a login read off the cover is quick, and otherwise it brute-forces
## the port's factory login, which takes a while and leaves failed logins in their records.
func open_tablet(access: Device) -> void:
	tablet_access = access
	tablet_admin = false
	tablet_cam = 0
	player.in_tablet = true
	console.game = self
	var mode := "saved" if access.cracked else ("badge" if has_badge else ("creds" if access.creds_known else "brute"))
	console.open(access, mode)
	access.plug(true, player.chest_pos())
	Sfx.ui("ui_select", -8.0)


## The login got through: the shell is open.
func session_opened() -> void:
	tablet_admin = console.admin
	if tablet_access:
		# the nettop keeps the key: next time it's straight in
		tablet_access.cracked = true
		tablet_access.cracked_admin = tablet_access.cracked_admin or console.admin
	stats.hacks += 1
	Sfx.stop_loop("brute")
	Sfx.ui("term_login", -6.0)
	hud.learn("network")


func close_tablet() -> void:
	if not tablet_access:
		return
	tablet_access.plug(false)
	tablet_access = null
	player.in_tablet = false
	console.close()
	Sfx.stop_loop("brute")
	Sfx.ui("ui_move", -6.0)


func _tick_tablet(dt: float) -> void:
	if not player.alive or player.global_position.distance_to(tablet_access.use_point()) > 2.6 or player.last_hit < 0.1:
		close_tablet()
		return
	console.tick(dt)
	if console.phase == NetConsole.Phase.LOGIN and console.mode == "brute":
		Sfx.loop_at("brute", "brute_loop", tablet_access.use_point(), -14.0, 1.2, 8.0)
	else:
		Sfx.stop_loop("brute")


## The login written inside a box's cover: the nettop will try it first from now on.
func creds_read(dv: Device) -> void:
	var parts := dv.password.split(":")
	hud.toast("LOGIN ON THE COVER  ·  %s / %s" % [parts[0], parts[1] if parts.size() > 1 else ""], false)
	Sfx.ui("badge_ok", -8.0)


## While connected, the terminal eats keyboard input: typed text goes to the command line.
## During the login only Escape does anything: it pulls the cable.
func tablet_input(event: InputEvent) -> bool:
	if not tablet_access:
		return false
	if event is InputEventMouseButton:
		return true
	if not (event is InputEventKey) or not event.pressed:
		return event is InputEventKey
	var k := event as InputEventKey
	if console.phase == NetConsole.Phase.LOGIN:
		if k.keycode == KEY_ESCAPE:
			close_tablet()
		return true
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			console.submit()
		KEY_BACKSPACE:
			console.backspace()
		KEY_DELETE:
			console.delete()
		KEY_TAB:
			console.autocomplete()
		KEY_LEFT:
			console.move_cursor(-1)
		KEY_RIGHT:
			console.move_cursor(1)
		KEY_UP:
			console.recall(-1)
		KEY_DOWN:
			console.recall(1)
		KEY_ESCAPE:
			close_tablet()
		_:
			if k.unicode >= 32:
				console.type_text(String.chr(k.unicode))
	Sfx.ui("key", -12.0)
	return true


func _terminal() -> Device:
	for dv in facility.devices:
		if dv.kind == Device.Kind.ACCESS and dv.label == "SECURITY TERMINAL":
			return dv
	return null


## Intrusion detection: enough suspicious activity and security kicks you out and comes looking.
func add_trace(amount: float, reason: String) -> void:
	trace += amount
	hud.trace_event(reason)
	if trace >= 100.0:
		trace = 60.0
		var at := tablet_access
		close_tablet()
		if at:
			at.locked = 60.0
			Sfx.ui("term_kick", -4.0)
			hud.banner("INTRUSION DETECTED", false)
			_dispatch(at.use_point(), "investigate", 2)


func restore_cameras() -> void:
	for c in cameras():
		if c.disabled and not c.destroyed:
			c.repaired(self)
	hud.toast("CAMERAS BACK ONLINE")


# --- comms, power, repairs

func jam_comms(relay: Device) -> void:
	comms_down = true
	_pending_radio = _pending_radio.filter(func(r: Dictionary) -> bool: return r.has("release"))
	Sfx.play_at("comms_cut", relay.global_position + Vector3.UP * 0.7, 0.0)
	hud.banner("COMMS DOWN")
	_schedule_repair(relay, 30.0)


func comms_restored(relay: Device) -> void:
	comms_down = false
	Sfx.play_at("comms_up", relay.global_position + Vector3.UP * 0.7, -2.0)
	hud.toast("ENEMY COMMS RESTORED")


func set_zone_power(breaker: Device, on: bool) -> void:
	for l in facility.lamps:
		if l.zone == breaker.zone:
			if on:
				l.power_on()
			else:
				l.power_off()
	for d in facility.doors:
		if d.zone == breaker.zone:
			d.powered = on
			if d.lock == Door.Lock.MAGLOCK:
				Sfx.play_at("maglock", d.global_position + Vector3.UP, -4.0)
	for sl in facility.searchlights:
		if sl.get_meta("zone") == breaker.zone:
			sl.visible = on
	_light_t = 0.0
	Sfx.play_at("breaker", breaker.global_position + Vector3.UP, -2.0)
	Sfx.play_at("power_up" if on else "power_down", breaker.global_position + Vector3.UP, 0.0, false)
	if _zone_of(player.global_position) == breaker.zone:
		Sfx.play("power_up" if on else "power_down", -12.0)
	if on:
		return
	hud.learn("lights")
	for s in soldiers:
		if s.alive and s.state == Soldier.State.CALM and _zone_of(s.global_position) == breaker.zone:
			s.make_suspicious(s.global_position + s.facing() * 2.0, 0.3, "power")
	_schedule_repair(breaker, 20.0)


func _zone_of(p: Vector3) -> String:
	return facility.zone_of(p)


func _schedule_repair(dv: Device, delay: float) -> void:
	_repairs.append({"device": dv, "t": time + delay})
	hq.caution("device")


func requeue_repair(dv: Device) -> void:
	_repairs.append({"device": dv, "t": time + 15.0})


## Send the nearest patrolling drone to look at a position.
func dispatch_drone(pos: Vector3) -> void:
	if comms_down:
		return
	var best: Drone = null
	var bd := INF
	for dr in facility.drones:
		if dr.scanning() and dr.mode == Drone.Mode.PATROL:
			var d := dr.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = dr
	if best:
		best.investigate(pos)


## HQ sends the nearest guards to a contact.
func dispatch_to(pos: Vector3, count: int) -> void:
	var near := soldiers.filter(func(s: Soldier) -> bool: return s.alive and s.state != Soldier.State.COMBAT and s.task.is_empty())
	near.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	for i in mini(count, near.size()):
		var s: Soldier = near[i]
		s.squad.report(pos, time - 3.0)
		s.alert(pos, "radio")


## A guard missed a radio check: two others go and look at their post.
func investigate_post(pos: Vector3) -> void:
	var near := soldiers.filter(func(s: Soldier) -> bool: return s.alive and s.state == Soldier.State.CALM and s.task.is_empty())
	near.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	for i in mini(2, near.size()):
		var s: Soldier = near[i]
		s.make_suspicious(pos, 0.9, "search", 0.5)


## Someone gets sent to fix whatever stopped working.
func _tick_repairs() -> void:
	for i in range(_repairs.size() - 1, -1, -1):
		var r: Dictionary = _repairs[i]
		if time < float(r.t):
			continue
		var dv: Device = r.device
		var broken := (dv.kind == Device.Kind.CAMERA and dv.disabled) or (dv.kind != Device.Kind.CAMERA and dv.kind != Device.Kind.ACCESS and dv.sabotaged) \
			or (dv.kind == Device.Kind.ACCESS and cameras().any(func(c: Device) -> bool: return c.disabled))
		if not broken:
			_repairs.remove_at(i)
			continue
		if dv.repair_pending:
			continue
		var worker := _nearest_free(dv.global_position)
		if worker == null:
			r.t = time + 10.0
			continue
		dv.repair_pending = true
		var stand := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, dv.global_position)
		worker.assign_task(stand, dv, 6.0 if dv.kind != Device.Kind.BREAKER else 3.0)
		_repairs.remove_at(i)


func _nearest_free(p: Vector3) -> Soldier:
	var best: Soldier = null
	var bd := INF
	for s in soldiers:
		if s.alive and s.state != Soldier.State.COMBAT and s.task.is_empty() and s.blind <= 0.0:
			var d := s.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = s
	return best


## Guards who wander near the laptop while it's copying notice the drive and pull it.
func _tick_laptop_watch() -> void:
	var lap: Device = null
	for dv in facility.devices:
		if dv.kind == Device.Kind.LAPTOP:
			lap = dv
	if lap == null or lap.copy_state != "copying" or lap.repair_pending:
		return
	for s in soldiers:
		if not s.alive or not s.task.is_empty() or s.global_position.distance_to(lap.global_position) > 7.0:
			continue
		if los(s.eye(), lap.use_point() + Vector3.UP * 0.1):
			lap.repair_pending = true
			s.assign_task(NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, lap.global_position), lap, 1.5)
			return


func data_downloaded() -> void:
	_take_intel()


# --- cameras

func camera_alarm(cam: Device) -> void:
	Sfx.play_at("alarm", cam.global_position, 2.0, false)
	spotted_cue()
	hud.hint_event("camera_alarm")
	if comms_down:
		hud.toast("CAMERA ALARM  ·  NOBODY ON THE RADIO TO HEAR IT")
		return
	security_say("cam", cam.label)
	_dispatch(player.global_position, "saw")
	dispatch_drone(player.global_position)
	hq.camera_contact(player.global_position)


func camera_report(_cam: Device) -> void:
	if comms_down:
		return
	for sq: Squad in squads.values():
		if sq.alive_members().any(func(m: Soldier) -> bool: return m.state == Soldier.State.COMBAT):
			sq.report(player.global_position, time)


## Security radios it in: the nearest guards respond.
func _dispatch(pos: Vector3, how: String, count := 3) -> void:
	if comms_down and how != "investigate":
		return
	var near := soldiers.filter(func(s: Soldier) -> bool: return s.alive)
	near.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	for i in mini(count, near.size()):
		var s: Soldier = near[i]
		if how == "investigate":
			s.make_suspicious(pos, 0.9, "huh")
			continue
		s.squad.report(pos, time)
		if s.state != Soldier.State.COMBAT:
			s.alert(pos, how if how == "body" else "radio")


## What the multitool can do where you're looking: clone a badge off an unaware guard or a body,
## or splice a secured door's reader open. Ordered against the other uses of the key in focus().
func tool_action() -> Dictionary:
	if not player.alive or player.in_tablet or player.drag_body or player.ladder:
		return {}
	var eye := player.eye_pos()
	var fwd := player.view_dir()
	# clone a badge: an unaware guard close in front, or a body
	var clone: Soldier = null
	var cbd := 2.8
	for s in soldiers:
		if s.badge.is_empty():
			continue
		# clone off a body, or off a guard who can't see you (not a takedown target here anyway)
		var live_ok := s.alive and s.state != Soldier.State.COMBAT and not s.sees and s != takedown_target()
		if not (live_ok or (not s.alive and s.death_t > 0.5)):
			continue
		var to := s.global_position + Vector3.UP * (1.0 if s.alive else 0.3) - eye
		var d := to.length()
		if d > cbd or to.normalized().dot(fwd) < 0.5:
			continue
		if not access_covers(s.badge):
			cbd = d
			clone = s
	if clone:
		return {"kind": "clone", "soldier": clone, "time": 2.2, "label": "Clone badge  ·  %s" % clone.badge.map(func(a: String) -> String: return a.to_upper())[0]}
	# splice a door reader you can't badge through
	var d2 := refused_door()
	if d2 and d2.reader_live():
		return {"kind": "splice", "door": d2, "time": 6.0 if d2.lock == Door.Lock.STRIKE else 9.0, "label": "Splice reader  ·  %s" % NetConsole._slug(d2.label)}
	return {}


## Do our access levels already include all of these?
func access_covers(levels: Array) -> bool:
	for a: String in levels:
		if not access.has(a):
			return false
	return true


func _tick_tool(dt: float, a: Dictionary) -> void:
	if not Input.is_action_pressed("interact"):
		tool_target = {}
		tool_progress = 0.0
		Sfx.stop_loop("tool")
		return
	var at: Vector3 = (a.soldier.global_position + Vector3.UP) if a.kind == "clone" else (a.door.global_position + Vector3.UP * 1.2)
	Sfx.loop_at("tool", "clone_loop" if a.kind == "clone" else "splice_loop", at, -10.0, 1.5, 12.0)
	# same action continuing?
	if tool_target.get("kind") != a.kind or tool_target.get("door") != a.get("door") or tool_target.get("soldier") != a.get("soldier"):
		tool_target = a
		tool_progress = 0.0
	tool_progress += dt / float(a.time)
	if tool_progress >= 1.0:
		_finish_tool(a)
		tool_target = {}
		tool_progress = 0.0
		_use_latch = true


func _finish_tool(act: Dictionary) -> void:
	match act.kind:
		"clone":
			var s: Soldier = act.soldier
			for a: String in s.badge:
				access[a] = true
			hud.toast("BADGE CLONED  ·  " + "  ·  ".join(s.badge.map(func(a: String) -> String: return a.to_upper())), false)
			Sfx.ui("badge_ok", -6.0)
			hud.hint_event("badge")
		"splice":
			var d: Door = act.door
			d.unlocked = true
			add_trace(10.0, "Reader spliced: %s" % d.label)
			Sfx.play_at("maglock", d.global_position + Vector3.UP, -2.0)
			hud.toast("%s  ·  READER SPLICED" % d.label)
			# shorting a reader is noticed if a camera or guard sees it
			for o in soldiers:
				if o.alive and o.state == Soldier.State.CALM and o.global_position.distance_to(d.global_position) < 6.0 and o.sees:
					o.make_suspicious(d.global_position, 0.6, "huh")


func takedown_target() -> Soldier:
	if not player.alive or player.drag_body:
		return null
	var f := player.view_dir()
	for s in soldiers:
		if not s.alive or (s.state == Soldier.State.COMBAT and s.sees):
			continue
		var to := s.global_position - player.global_position
		var d := Vector2(to.x, to.z).length()
		if d > 1.9 or d < 0.01 or absf(to.y) > 0.8:
			continue
		if (to.x * f.x + to.z * f.z) / d < 0.5:
			continue
		var behind := (to.x * s.facing().x + to.z * s.facing().z) / d
		if behind > 0.1 or s.state == Soldier.State.CALM or s.blind > 0.0:
			return s
	return null


func corpse_near() -> Soldier:
	var best: Soldier = null
	var bd := 1.9
	for s in soldiers:
		if s.alive or s.death_t < 0.6:
			continue
		var d := Vector2(s.global_position.x - player.global_position.x, s.global_position.z - player.global_position.z).length()
		if d < bd and absf(s.global_position.y - player.global_position.y) < 1.2:
			bd = d
			best = s
	return best


func interact_target() -> Pickup:
	var eye := player.eye_pos()
	var d := player.view_dir()
	var best: Pickup = null
	var bd := 2.3
	for p in facility.pickups:
		if p.taken or p.is_auto():
			continue
		var to := p.global_position + Vector3.UP * 0.15 - eye
		var dist := to.length()
		if dist > bd or to.normalized().dot(d) < 0.75:
			continue
		bd = dist
		best = p
	return best


func interact() -> void:
	var a := focus()
	match a.get("kind", ""):
		"takedown":
			var t: Soldier = a.soldier
			Sfx.play_at("takedown", t.global_position + Vector3.UP, 0.0, false)
			player.trauma += 0.15
			player.viewmodel.recoil = 0.08
			player.viewmodel.recoil_rot = -0.3
			t.die(player.view_dir(), false, true)
			for o in soldiers:
				if o.alive and o.global_position.distance_to(t.global_position) < 15.0 and o.sees:
					o.alert(player.global_position, "saw")
			hud.learn("takedown")
			_use_latch = true
		"pickup":
			_pick_up(a.pickup)
			_use_latch = true
		"drag":
			player.start_drag(a.soldier)


func _pick_up(p: Pickup) -> void:
	match p.kind:
		Pickup.Kind.MEDKIT:
			if not player.needs_treatment():
				hud.toast("NOT HURT")
				return
			player.treat()
			hud.toast("WOUNDS TREATED", false)
		Pickup.Kind.AMMO:
			player.weapons.resupply()
			hud.toast("RESUPPLIED", false)
		Pickup.Kind.INTEL:
			_take_intel()
		Pickup.Kind.WEAPON:
			var old := player.weapons.swap_primary(p.weapon, p.mag_rounds, p.spares)
			var drop := player.global_position + player.forward() * 0.4
			facility.place(Pickup.dropped_weapon(drop, old.weapon, old.mag, old.spares))
			hud.toast(p.weapon.display_name + "  ·  " + p.weapon.caliber, false)
			hud.hint_event("scavenge")
	p.take()


func _tick_pickups() -> void:
	if not player.alive:
		return
	for p in facility.pickups:
		if p.taken or not p.is_auto() or p.global_position.distance_to(player.global_position) > 1.3:
			continue
		if p.kind == Pickup.Kind.ROUNDS:
			var used := player.weapons.take_rounds(p.caliber, p.amount)
			if used == 0:
				continue
			p.amount -= used
			hud.toast("+%d  %s" % [used, p.caliber], false)
			Sfx.play("pickup")
			if p.amount > 0:
				continue
		else:
			var g: Dictionary = {}
			for x in player.weapons.gadgets:
				if x.type == "frag":
					g = x
			if g.is_empty() or int(g.n) >= 3:
				continue
			g.n = int(g.n) + 1
			hud.toast("+1 FRAG", false)
			Sfx.play("pickup")
		p.take()


## Loose rounds at your feet that none of your weapons take.
func useless_rounds_near() -> Pickup:
	for p in facility.pickups:
		if not p.taken and p.kind == Pickup.Kind.ROUNDS and p.global_position.distance_to(player.global_position) < 1.6 and not player.weapons.uses_caliber(p.caliber):
			return p
	return null


## Guards come onto your tracker when you actually see them: in front of you, in the open,
## and either lit or close enough to make out.
func _tick_spotting() -> void:
	var cam := player.camera
	var eye := player.eye_pos()
	var fwd := player.view_dir()
	var half := deg_to_rad(cam.fov * 0.5 * 1.25)
	for s in soldiers:
		if not s.alive:
			continue
		var head := s.head_pos()
		var to := head - eye
		var dist := to.length()
		if dist > 70.0 or to.normalized().angle_to(fwd) > half:
			continue
		var chest := s.global_position + Vector3.UP * 1.2
		if not (los(eye, head) or los(eye, chest)) or smoke_blocks(eye, head):
			continue
		var bright := s.model.flashlight.visible or dist < 18.0 or facility.light_level(s.global_position, []) > 0.45
		if not bright:
			continue
		s.tag_seen = s.global_position
		s.tag_seen_t = time
		if not s.tagged:
			s.tagged = true


func on_soldier_killed(s: Soldier, headshot: bool, takedown: bool) -> void:
	stats.kills += 1
	if takedown:
		stats.takedowns += 1
	Sfx.play_at("body", s.global_position + Vector3.UP * 0.3)
	# they drop what they were actually carrying: their weapon, and loose rounds for it
	var data: WeaponData = load("res://resources/weapons/%s.tres" % s.profile.weapon_id)
	var side := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
	facility.place(Pickup.dropped_weapon(s.global_position + side, data, clampi(s.mag, 0, data.mag_size), []))
	facility.place(Pickup.rounds(s.global_position - side * 0.6, data.caliber, s.profile.carried_rounds))
	if s.grenades > 0 and randf() < 0.6:
		facility.add_pickup(Pickup.Kind.FRAG, s.global_position + Vector3(0.3, 0, 0.2), 1, false)
	if not takedown:
		for o in s.squad.members:
			if o != s and o.alive and o.state == Soldier.State.COMBAT and o.global_position.distance_to(s.global_position) < 35.0 and randf() < 0.7:
				say(o, "mandown")
				break
	hud.hint_event("kill")
