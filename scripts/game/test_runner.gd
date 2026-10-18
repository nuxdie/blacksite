class_name TestRunner
extends Node
## Automated checks, enabled with user arguments after "--":
##   --autotest          run gameplay checks and print results as JSON, then quit
##   --shots=<dir>       capture screenshots at fixed viewpoints (needs a window)
##   --uishots=<dir>     capture the HUD in a series of game states (needs a window)
##   --sim=<seconds>     run a combat bot for that long and report

var game: Game
var _args: Dictionary = {}


func _ready() -> void:
	Settings.persist = false
	Settings.learned.clear()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func start() -> void:
	game.god_mode = true
	if _args.has("shots"):
		await _shots(_args["shots"])
	if _args.has("uishots"):
		await _ui_shots(_args["uishots"])
	if _args.has("autotest"):
		await _autotest()
	if _args.has("sim"):
		await _sim(float(_args["sim"]))
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _look_at(p: Vector3) -> void:
	var pl := game.player
	var d := p - pl.eye_pos()
	pl.yaw = atan2(-d.x, -d.z)
	pl.pitch = asin(clampf(d.y / d.length(), -1.0, 1.0))


func _isolate(keep: Array) -> void:
	for s in game.soldiers:
		if not keep.has(s):
			s.alive = false
			s.visible = false
			s.death_t = 1.0
			s.corpse_found = true
			s.accounted = true
			s.collision_layer = 0


func _find(squad: String, x: float) -> Soldier:
	for s in game.soldiers:
		if s.squad.id == squad and absf(s.global_position.x - x) < 1.0:
			return s
	return null


func _device(label: String) -> Device:
	for dv in game.facility.devices:
		if dv.label == label:
			return dv
	return null


## Run one console command, as if typed and entered.
func _console(cmd: String) -> void:
	game.console.input = cmd
	game.console.submit()
	await _frames(2)


func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _fresh(primary := "carbine", gadgets: Array[String] = ["frag", "smoke"]) -> void:
	Settings.primary = primary
	Settings.gadgets = gadgets
	game.start_mission()
	game.god_mode = true
	await _frames(30)


func _fire(n_frames: int) -> void:
	Input.action_press("fire")
	await _frames(n_frames)
	Input.action_release("fire")
	await _frames(5)


func _autotest() -> void:
	var r := {}
	var t0 := Time.get_ticks_msec()
	# penetration: carbine through an office plaster wall
	await _fresh("carbine")
	var e := _find("office", -22.0)
	_isolate([e])
	e.global_position = Vector3(-22, 0, 14)
	game.player.global_position = Vector3(-22, 0, 8)
	await _frames(5)
	_look_at(Vector3(-22, 1.36, 14))
	await _fire(12)
	r["pen_carbine_plaster"] = {"hp": roundi(e.hp), "alive": e.alive}
	await _fresh("smg")
	e = _find("office", -22.0)
	_isolate([e])
	e.global_position = Vector3(-22, 0, 14)
	game.player.global_position = Vector3(-22, 0, 8)
	await _frames(5)
	_look_at(Vector3(-22, 1.36, 14))
	await _fire(12)
	r["pen_smg_plaster"] = {"hp": roundi(e.hp)}
	# concrete stops the marksman rifle
	await _fresh("dmr")
	e = _find("yard", -10.0)
	_isolate([e])
	e.global_position = Vector3(-12, 0, -1.4)
	e.crouch = true
	e.crouch_k = 1.0
	game.player.global_position = Vector3(-12, 0, -10)
	await _frames(3)
	Input.action_press("aim")
	await _frames(40)
	_look_at(Vector3(-12, 0.6, -1.4))
	await _fire(3)
	Input.action_release("aim")
	r["concrete_stops_dmr"] = {"hp": roundi(e.hp)}
	# suppressed kill: a guard 8 m away stays calm
	await _fresh("smg")
	var g1 := _find("yard", -10.0)
	var g2 := _find("yard", -12.5)
	_isolate([g1, g2])
	for c in game.cameras():
		c.disable()
	game.player.global_position = Vector3(-10, 0, 10)
	game.player.crouch_toggle = true
	await _frames(10)
	Input.action_press("aim")
	await _frames(30)
	for _k in 8:
		if not g1.alive:
			break
		_look_at(g1.head_pos())
		await _fire(2)
		await _frames(6)
	Input.action_release("aim")
	await _frames(30)
	r["quiet_kill"] = {"target_dead": not g1.alive, "neighbour_state": Soldier.State.keys()[g2.state], "detected": game.detected}
	# shoot out a lamp
	await _fresh("carbine")
	var lamp: Lamp = null
	for l in game.facility.lamps:
		if absf(l.global_position.x + 2.3) < 0.5 and absf(l.global_position.z + 1.0) < 0.5:
			lamp = l
	game.player.global_position = Vector3(-2, 0, -8)
	await _frames(3)
	_look_at(lamp.global_position)
	await _fire(3)
	r["lamp_shot"] = lamp.dead
	# navigation: a patrol actually walks its route
	await _fresh("carbine")
	var walker := _find("wh", 14.0)
	var start := walker.global_position
	await _frames(400)
	r["patrol_moved"] = snappedf(walker.global_position.distance_to(start), 0.1)
	# combat: engage a squad and see who takes cover / flanks
	await _fresh("carbine")
	game.player.global_position = Vector3(-12, 0, -8)
	for s in game.soldiers:
		if s.squad.id == "yard":
			s.alert(game.player.global_position, "saw")
	var modes := {}
	for _k in 600:
		await get_tree().physics_frame
		for s in game.soldiers:
			if s.alive and s.state == Soldier.State.COMBAT:
				modes[Soldier.Mode.keys()[s.mode]] = true
	r["combat_modes"] = modes.keys()
	r["player_hp_after_10s"] = roundi(game.player.hp)
	# vault over a jersey barrier
	await _fresh("carbine")
	game.player.global_position = Vector3(-12, 0, -3.0)
	game.player.yaw = PI
	await _frames(20)
	r["vault_available"] = game.player.vault_ok
	if game.player.vault_ok:
		game.player._start_vault()
		await _frames(40)
	r["vault_end"] = game.player.global_position.snappedf(0.1)
	# scavenging: a rifleman drops his AR-7 and 7.62 rounds; the carbine can't use them, the AR-7 can
	await _fresh("carbine")
	e = _find("yard", -10.0)
	_isolate([e])
	e.die(Vector3.FORWARD, false, true)
	await _frames(60)
	var gun: Pickup = null
	var ammo: Pickup = null
	for p in game.facility.pickups:
		if p.taken:
			continue
		if p.kind == Pickup.Kind.WEAPON:
			gun = p
		elif p.kind == Pickup.Kind.ROUNDS:
			ammo = p
	var sc := {"weapon": gun.weapon.id if gun else "", "rounds": ammo.amount if ammo else 0, "caliber": ammo.caliber if ammo else ""}
	game.player.global_position = ammo.global_position
	await _frames(10)
	sc["carbine_took_rounds"] = ammo.taken or ammo.amount < 60
	game.player.global_position = gun.global_position + Vector3(0, 0, 1.2)
	await _frames(2)
	_look_at(gun.global_position + Vector3.UP * 0.15)
	await _frames(2)
	game.interact()
	await _frames(40)
	sc["primary_after_swap"] = game.player.weapons.slots[0].id
	var spares_before := (game.player.weapons.spare[0] as Array).size()
	game.player.global_position = ammo.global_position
	await _frames(10)
	sc["ar7_spares"] = [spares_before, (game.player.weapons.spare[0] as Array).size()]
	sc["carbine_on_ground"] = game.facility.pickups.any(func(p: Pickup) -> bool: return not p.taken and p.kind == Pickup.Kind.WEAPON and p.weapon.id == "carbine")
	r["scavenge"] = sc
	# shotgun pellets: a breacher's own shotgun at close range
	await _fresh("carbine")
	var target := _find("office", -15.0)
	_isolate([target])
	target.global_position = Vector3(-15, 0, 26)
	game.player.weapons.swap_primary(load("res://resources/weapons/shotgun.tres"), 7, [7, 7])
	game.player.global_position = Vector3(-15, 0, 30)
	await _frames(40)
	_look_at(target.global_position + Vector3.UP * 1.2)
	await _fire(3)
	r["shotgun_close"] = {"hp": roundi(target.hp), "alive": target.alive, "mag": game.player.weapons.mag[0]}
	# security, power, comms, data
	var hk := {}
	await _fresh("carbine")
	var cams := game.cameras()
	var c2: Device = cams[1]
	game.player.global_position = Vector3(-15, 0, -27)
	await _frames(3)
	_look_at(c2.head.global_position)
	for _k in 1200:
		await get_tree().physics_frame
		if c2.alarm:
			break
	await _frames(60)
	hk["camera_alarm"] = c2.alarm
	hk["guards_dispatched"] = game.soldiers.filter(func(x: Soldier) -> bool: return x.state == Soldier.State.COMBAT).size()
	# bypass at the junction box without credentials
	await _fresh("carbine")
	var lookout := _find("yard", 7.5)
	lookout.alive = false
	lookout.visible = false
	lookout.accounted = true
	lookout.collision_layer = 0
	var junction := _device("JUNCTION BOX")
	game.player.global_position = junction.use_point() + Vector3(0, -1.3, -1.2)
	await _frames(5)
	_look_at(junction.use_point())
	await _frames(3)
	hk["junction_prompt"] = junction.use_label(game)
	Input.action_press("interact")
	await _frames(950)
	Input.action_release("interact")
	await _frames(3)
	hk["tablet_open"] = game.tablet_access == junction
	hk["trace_after_bypass"] = roundi(game.trace)
	await _console("loop 1")
	hk["cam1_looped"] = cams[0].looped > 0.0
	await _console("kill 3")
	hk["cam3_disabled"] = cams[2].disabled
	await _console("unlock server")
	hk["console_unlock"] = not game.facility.doors[0].secured()
	await _console("relay off")
	hk["console_relay"] = game.comms_down
	# drive trace to the lockout
	for _n2 in 6:
		await _console("kill %d" % (randi() % 5 + 1))
		await _console("loop %d" % (randi() % 5 + 1))
	hk["intrusion_locked"] = junction.locked > 0.0
	hk["tablet_closed"] = game.tablet_access == null
	# leave before they come to look
	game.player.global_position = Vector3(-54, 0, -20)
	await _frames(60 * 22)
	hk["repair_dispatched"] = cams[2].repair_pending or not cams[2].disabled
	hk["repair_debug"] = {"combat": game.soldiers.filter(func(x: Soldier) -> bool: return x.alive and x.state == Soldier.State.COMBAT).size(), "tasks": game.soldiers.filter(func(x: Soldier) -> bool: return not x.task.is_empty()).size(), "repairs": game._repairs.size(), "alarm": Command.Level.keys()[game.hq.level]}
	# badge: take down the booth guard, clone their security badge off the body with the multitool
	await _fresh("carbine")
	var booth := _find("yard", -12.5)
	booth.die(Vector3.FORWARD, false, true)
	booth.global_position = Vector3(-5, 0, -10)
	await _frames(60)
	game.player.global_position = Vector3(-5, 0, -9.0)
	await _frames(3)
	_look_at(Vector3(-5, 0.3, -10))
	await _frames(3)
	hk["clone_offered"] = game.tool_action().get("kind") == "clone"
	Input.action_press("interact")
	await _frames(int(2.2 * 60.0) + 10)
	Input.action_release("interact")
	hk["has_badge"] = game.has_badge
	var term := _device("SECURITY TERMINAL")
	game.player.global_position = Vector3(-12.5, 0, -17.2)
	await _frames(5)
	_look_at(term.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(100)
	Input.action_release("interact")
	await _frames(3)
	hk["admin"] = game.tablet_admin
	hk["trace_with_badge"] = roundi(game.trace)
	await _console("blackout")
	hk["all_cameras_down"] = cams.all(func(d: Device) -> bool: return d.disabled or d.destroyed)
	game.close_tablet()
	# relay sabotage cuts their radio
	await _fresh("carbine")
	var relay := _device("COMMS RELAY")
	game.player.global_position = Vector3(-25.2, 3.7, 29)
	await _frames(5)
	_look_at(relay.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(390)
	Input.action_release("interact")
	hk["comms_down"] = game.comms_down
	game.player.global_position = Vector3(-15, 0, -27)
	await _frames(3)
	_look_at(c2.head.global_position)
	await _frames(600)
	hk["alarm_while_comms_down"] = c2.alarm
	hk["dispatched_while_down"] = game.soldiers.filter(func(x: Soldier) -> bool: return x.state == Soldier.State.COMBAT).size()
	game.player.global_position = Vector3(-44, 0, -32)
	await _frames(60 * 25)
	hk["relay_repair_sent"] = relay.repair_pending or not relay.sabotaged
	# breaker
	await _fresh("carbine")
	var yard_breaker: Device = null
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.BREAKER and dv.zone == "YARD":
			yard_breaker = dv
	game.player.global_position = yard_breaker.global_position + Vector3(0, -1.3, 1.0)
	await _frames(5)
	_look_at(yard_breaker.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(80)
	Input.action_release("interact")
	hk["yard_dark"] = game.facility.lamps.filter(func(l: Lamp) -> bool: return l.zone == "YARD").all(func(l: Lamp) -> bool: return not l.is_lit())
	hk["warehouse_lit"] = game.facility.lamps.filter(func(l: Lamp) -> bool: return l.zone == "WAREHOUSE").any(func(l: Lamp) -> bool: return l.is_lit())
	# data: a guard standing at the laptop pulls the drive
	await _fresh("carbine")
	var lap := _device("LAPTOP")
	game.player.global_position = Vector3(45.6, 4.2, 26.6)
	await _frames(5)
	_look_at(lap.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(60)
	Input.action_release("interact")
	hk["copy_started"] = lap.copy_state
	game.player.global_position = Vector3(36, 0, 20)
	await _frames(500)
	hk["drive_pulled_by_guard"] = lap.copy_state == "idle"
	await _fresh("carbine")
	lap = _device("LAPTOP")
	_isolate([])
	game.player.global_position = Vector3(45.6, 4.2, 26.6)
	await _frames(5)
	_look_at(lap.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(60)
	Input.action_release("interact")
	await _frames(60 * 36)
	hk["copy_state"] = lap.copy_state
	_look_at(lap.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(60)
	Input.action_release("interact")
	await _frames(5)
	hk["mission"] = game.mission
	await _fresh("carbine")
	var shot_cam: Device = game.cameras()[0]
	game.player.global_position = Vector3(-2, 0, -12)
	await _frames(5)
	Input.action_press("aim")
	await _frames(30)
	_look_at(shot_cam.head.global_position)
	await _fire(12)
	Input.action_release("aim")
	hk["camera_shot_out"] = shot_cam.destroyed
	r["security"] = hk
	r["consequences"] = await _consequences()
	r["quicksave"] = await _quicksave()
	r["vertical"] = await _vertical()
	r["fairness"] = await _fairness()
	r["drones"] = await _drones()
	r["multitool"] = await _multitool()
	# duel: one rifleman engages a player standing in the open 15 m away
	await _fresh("carbine")
	e = _find("yard", -10.0)
	_isolate([e])
	e.global_position = Vector3(-10, 0, -5)
	game.player.global_position = Vector3(-12, 0, 9)
	e.alert(game.player.global_position, "saw")
	game.god_mode = false
	var first := -1.0
	var t_start := game.time
	var seen_frames := 0
	var min_err := 1.0
	var peeks := 0
	for _k in 600:
		await get_tree().physics_frame
		if e.sees:
			seen_frames += 1
		if e.peeking:
			peeks += 1
		min_err = minf(min_err, e.aim_err)
		if first < 0.0 and game.player.hp < 100.0:
			first = game.time - t_start
		if not game.player.alive:
			break
	r["duel"] = {"first_hit_s": snappedf(first, 0.01), "hp": roundi(game.player.hp), "alive": game.player.alive, "enemy_shots": game.stats.enemy_shots, "enemy_hits": game.stats.enemy_hits, "sees": e.sees, "mode": Soldier.Mode.keys()[e.mode], "seen_frames": seen_frames, "peek_frames": peeks, "min_err": snappedf(min_err, 0.001), "muzzle": e.model.muzzle.global_position.snappedf(0.01), "pos": e.global_position.snappedf(0.01)}
	game.god_mode = true
	r["ms"] = Time.get_ticks_msec() - t0
	print("AUTOTEST ", JSON.stringify(r))


## Splicing a door reader: offered only at a secured door you can't badge, opens it, costs trace.
func _multitool() -> Dictionary:
	var c := {}
	await _fresh("carbine")
	_isolate([])
	var p := game.player
	var d: Door = game.facility.doors[1]
	p.global_position = d.global_position + Vector3(0, 0, -0.9)
	await _frames(3)
	_look_at(d.global_position + Vector3.UP * 1.2)
	await _frames(30)
	c["refused"] = d.refused
	c["splice_offered"] = game.tool_action().get("kind") == "splice"
	var trace0 := game.trace
	Input.action_press("interact")
	await _frames(int(6.0 * 60.0) + 20)
	Input.action_release("interact")
	await _frames(40)
	c["door_opened"] = d.unlocked and d.open_k > 0.5
	c["trace_added"] = game.trace > trace0
	# a dead reader cannot be spliced
	await _fresh("carbine")
	_isolate([])
	d = game.facility.doors[1]
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.BREAKER and dv.zone == "OFFICE":
			dv.on_used(game)
	p.global_position = d.global_position + Vector3(0, 0, -0.9)
	await _frames(3)
	_look_at(d.global_position + Vector3.UP * 1.2)
	await _frames(30)
	c["dead_reader_no_splice"] = game.tool_action().is_empty() and not d.reader_live()
	return c


## Drones: scan from above, raise the alarm, grounded by comms-down, shot down, and no sight
## through walls or roofs.
func _drones() -> Dictionary:
	var c := {}
	await _fresh("carbine")
	_isolate([])
	var d: Drone = game.facility.drones[0]
	var p := game.player
	# park the drone and stand lit, in the open, under it: it should spot and track
	d.mode = Drone.Mode.PATROL
	d.route = [Vector3(-10, 5.6, -8)]
	d._i = 0
	d._target = d.route[0]
	d.position = Vector3(-10, 5.6, -8)
	p.global_position = Vector3(-10, 0, -8)
	p.crouch_toggle = false
	var tracked := false
	for _i in 60 * 8:
		await get_tree().physics_frame
		Input.action_press("move_right") if _i % 40 < 20 else Input.action_press("move_left")
		if d.mode == Drone.Mode.TRACK:
			tracked = true
			break
	Input.action_release("move_right")
	Input.action_release("move_left")
	c["drone_tracks_in_open"] = tracked
	c["alarm_from_drone"] = Command.Level.keys()[game.hq.level]
	# a roof blocks the drone: stand indoors under the office roof
	await _fresh("carbine")
	d = game.facility.drones[0]
	_isolate([])
	d.route = [Vector3(-21, 5.6, 20)]
	d._i = 0
	d._target = d.route[0]
	d.position = Vector3(-21, 5.6, 20)
	p.global_position = Vector3(-21, 0, 20)
	var saw := false
	for _i in 60 * 3:
		await get_tree().physics_frame
		saw = saw or d.sees_player
	c["drone_blocked_by_roof"] = not saw
	# comms-down grounds it: returns to home
	await _fresh("carbine")
	d = game.facility.drones[0]
	d.mode = Drone.Mode.PATROL
	game.comms_down = true
	await _frames(60 * 6)
	c["grounded_on_comms_down"] = d.mode == Drone.Mode.RETURN and d.global_position.distance_to(d.home) < 1.0
	# shoot it down
	await _fresh("carbine")
	d = game.facility.drones[0]
	_isolate([])
	d.route = [Vector3(-10, 5.6, -8)]
	d._i = 0
	d._target = d.route[0]
	d.position = Vector3(-10, 5.6, -8)
	p.global_position = Vector3(-10, 0, -14)
	await _frames(5)
	_look_at(d.global_position)
	await _fire(12)
	c["drone_shot_down"] = d.destroyed
	return c


## Detection has to be explainable: no light through walls, no sight through doors, footsteps
## muffled by walls, darkness and stance really working, and a stated reason when noticed.
func _fairness() -> Dictionary:
	var c := {}
	await _fresh("carbine")
	var fac := game.facility
	# a lamp inside the office must not light someone standing outside its wall
	var office_lamp: Lamp = null
	for l in fac.lamps:
		if l.global_position.distance_to(Vector3(-21, 3.3, 16)) < 0.5:
			office_lamp = l
	c["office_lamp_inside"] = snappedf(fac.lamp_light(office_lamp, Vector3(-21, 0, 13.5)), 0.01)
	c["office_lamp_through_wall"] = snappedf(fac.lamp_light(office_lamp, Vector3(-21, 0, 11.2)), 0.01)
	c["no_light_through_wall"] = c["office_lamp_through_wall"] == 0.0 and c["office_lamp_inside"] > 0.0
	# a closed door blocks sight both ways
	var g := _find("wh", 14.0)
	_isolate([g])
	g.patrol.clear()
	g.global_position = Vector3(20.8, 0, 27.4)
	g.post = g.global_position
	g.yaw = PI
	g.base_yaw = PI
	g.post_yaw = PI
	var p := game.player
	p.global_position = Vector3(20.8, 0, 32.6)
	p.yaw = 0.0
	var saw := false
	for _i in 120:
		await get_tree().physics_frame
		saw = saw or g.sees
	c["door_blocks_sight"] = not saw and g.aware < 0.05
	# dark and crouched vs lit and standing, 12 m in front of a calm guard
	await _fresh("carbine")
	g = _find("yard", -10.0)
	_isolate([g])
	g.patrol.clear()
	var dark := Vector3.INF
	var lit := Vector3.INF
	for l in fac.lamps:
		var below := Vector3(l.global_position.x, 0, l.global_position.z) + (g.global_position - l.global_position).normalized() * 1.0
		below.y = 0.0
		var dd := below.distance_to(g.global_position)
		if lit == Vector3.INF and dd > 9.0 and dd < 20.0 and game.los(g.eye(), below + Vector3.UP * 1.2) and fac.light_level(below, []) > 0.7:
			lit = below
	for i in 80:
		var ang := randf_range(-0.35, 0.35)
		var dist := randf_range(10.0, 14.0)
		var pt := g.global_position + Vector3(-sin(g.yaw + ang), 0, -cos(g.yaw + ang)) * dist
		if not game.los(g.eye(), pt + Vector3.UP * 1.0):
			continue
		var lv := fac.light_level(pt, [])
		if lv < 0.4 and dark == Vector3.INF:
			dark = pt
		if lv > 0.75 and lit == Vector3.INF:
			lit = pt
	c["found_spots"] = [dark != Vector3.INF, lit != Vector3.INF]
	if dark != Vector3.INF:
		p.global_position = dark
		p.crouch_toggle = true
		await _frames(60 * 5)
		c["dark_crouched_5s"] = {"aware": snappedf(g.aware, 0.01), "state": Soldier.State.keys()[g.state]}
	if lit != Vector3.INF:
		await _fresh("carbine")
		g = _find("yard", -10.0)
		_isolate([g])
		g.patrol.clear()
		var face := lit - g.global_position
		g.yaw = atan2(-face.x, -face.z)
		g.base_yaw = g.yaw
		g.post_yaw = g.yaw
		p.global_position = lit
		p.crouch_toggle = false
		var t := 0.0
		var reason := ""
		while t < 8.0 and g.state != Soldier.State.COMBAT:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if reason == "" and game.hud.status_items().size() > 0:
				reason = game.hud.status_items()[0][0]
		c["lit_standing_detect_s"] = snappedf(t, 0.1)
		c["reason_shown"] = reason
	# sprinting on the other side of a wall, inside the footstep radius
	await _fresh("carbine")
	g = _find("office", -15.0)
	_isolate([g])
	g.patrol.clear()
	p.global_position = Vector3(-19.5, 0, 21.2)
	p.yaw = -PI / 2
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	c["sprint_behind_wall"] = {"aware": snappedf(g.aware, 0.01), "state": Soldier.State.keys()[g.state], "dist": snappedf(g.global_position.distance_to(p.global_position), 0.1)}
	# a camera never sees through a wall: stand behind the booth from cam 2
	var cam2: Device = game.cameras()[1]
	var behind := Vector3(-12.5, 0, -14.5)
	c["camera_through_wall"] = cam2.sees_point(game, behind + Vector3.UP * 1.4) and not game.los(cam2.head.global_position, behind + Vector3.UP * 1.4)
	return c


## Stairs, ladders and the crawl duct, for the player and for guards.
func _vertical() -> Dictionary:
	var c := {}
	await _fresh("carbine")
	_isolate([])
	var p := game.player
	# climb the warehouse ladder onto the catwalk
	var l: Ladder = game.facility.ladders[0]
	p.global_position = l.bottom_exit()
	await _frames(5)
	c["ladder_prompt"] = game.ladder_near() == l
	p.grab_ladder(l)
	Input.action_press("move_forward")
	for _i in 300:
		await get_tree().physics_frame
		if p.ladder == null:
			break
	Input.action_release("move_forward")
	await _frames(30)
	c["player_on_catwalk"] = p.ladder == null and p.global_position.y > 4.0
	c["catwalk_area"] = game.facility.area_name(p.global_position)
	# walk up the west stairs to the mezzanine
	p.global_position = Vector3(13.5, 0.1, 9.0)
	p.yaw = PI
	await _frames(5)
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	c["stairs_top_y"] = snappedf(p.global_position.y, 0.1)
	# a guard sent to the catwalk takes the ladder
	await _fresh("carbine")
	var g := _find("wh", 14.0)
	_isolate([g])
	g.patrol.clear()
	g.post = Vector3(20.0, 4.2, 6.8)
	g.global_position = Vector3(14.0, 0, 4.0)
	var max_y := 0.0
	var climbed := false
	for _i in 60 * 20:
		await get_tree().physics_frame
		max_y = maxf(max_y, g.global_position.y)
		climbed = climbed or not g.climb.is_empty()
	c["guard_used_ladder"] = climbed
	c["guard_max_y"] = snappedf(max_y, 0.1)
	# take the grille off and crawl into the server room
	await _fresh("carbine")
	_isolate([])
	var vent: Device = null
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.VENT and dv.global_position.z < 20.0:
			vent = dv
	p.global_position = vent.global_position + Vector3(0, -0.72, -1.2)
	await _frames(3)
	_look_at(vent.use_point())
	await _frames(3)
	Input.action_press("interact")
	await _frames(int(vent.use_time(game) * 60.0) + 20)
	Input.action_release("interact")
	c["grille_open"] = vent.sabotaged
	var inner: Device = null
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.VENT and dv != vent:
			inner = dv
	inner.on_used(game)
	p.crouch_toggle = true
	await _frames(20)
	for wp: Vector3 in [Vector3(-30.85, 0.1, 28.4), Vector3(-28.5, 0, 28.4)]:
		for _k in 600:
			var to := wp - p.global_position
			to.y = 0.0
			if to.length() < 0.4:
				break
			p.yaw = atan2(-to.x, -to.z)
			Input.action_press("move_forward")
			await get_tree().physics_frame
		Input.action_release("move_forward")
	c["crawled_to"] = game.facility.area_name(p.global_position)
	return c


## Save the night mid-way, change everything, load it back.
func _quicksave() -> Dictionary:
	var c := {}
	await _fresh("carbine")
	var victim := _find("wh", 26.0)
	victim.die(Vector3.FORWARD, false, true)
	game.player.global_position = Vector3(-20, 0, -26)
	game.player.hp = 61.0
	game.player.weapons.mag[0] = 7
	game.hq.caution("test")
	_device("COMMS RELAY").on_used(game)
	await _frames(10)
	var pickups_before := game.facility.pickups.size()
	c["saved"] = SaveGame.save(game)
	await _fresh("carbine")
	c["loaded"] = SaveGame.load_into(game)
	await _frames(5)
	c["guard_dead"] = not _find("wh", 26.0).alive if _find("wh", 26.0) else not game.soldiers[10].alive
	c["player_pos"] = game.player.global_position.distance_to(Vector3(-20, 0, -26)) < 0.5
	c["hp"] = roundi(game.player.hp)
	c["mag"] = game.player.weapons.mag[0]
	c["caution"] = Command.Level.keys()[game.hq.level]
	c["comms_down"] = game.comms_down
	c["pickups"] = [pickups_before, game.facility.pickups.size()]
	return c


## Radio checks, alarms, comms and wounds.
func _consequences() -> Dictionary:
	var c := {}
	# a guard killed out of sight misses the next radio check; HQ goes to caution and sends people
	await _fresh("carbine")
	var victim := _find("wh", 26.0)
	victim.die(Vector3.FORWARD, false, true)
	victim.global_position = Vector3(26, 0, -9)
	game.player.global_position = Vector3(24, 0, -11)
	game.hq._check_t = 0.1
	var investigated := false
	for _i in 60 * 25:
		await get_tree().physics_frame
		if game.hq.stats.missed_checks > 0 and not c.has("level_after_check"):
			c["level_after_check"] = Command.Level.keys()[game.hq.level]
		investigated = investigated or game.soldiers.any(func(s: Soldier) -> bool: return s.alive and s.state == Soldier.State.SUSPICIOUS and s.investigate.distance_to(victim.post) < 1.0)
	c["missed_checks"] = game.hq.stats.missed_checks
	c["post_investigated"] = investigated
	c["level_later"] = Command.Level.keys()[game.hq.level]
	# a guard who spots you radios it in: alarm, and the reaction force is called
	await _fresh("carbine")
	var spotter := _find("yard", -10.0)
	spotter.alert(game.player.global_position, "saw")
	await _frames(60 * 5)
	c["alarm_after_contact"] = Command.Level.keys()[game.hq.level]
	c["qrf_called"] = game.hq.qrf_called
	# the same contact with the relay down never reaches HQ
	await _fresh("carbine")
	game.comms_down = true
	spotter = _find("yard", -10.0)
	spotter.alert(game.player.global_position, "saw")
	await _frames(60 * 5)
	c["alarm_with_comms_down"] = Command.Level.keys()[game.hq.level]
	# killing the spotter before the call goes out keeps HQ in the dark
	await _fresh("carbine")
	spotter = _find("yard", -10.0)
	spotter.alert(game.player.global_position, "saw")
	await _frames(30)
	spotter.die(Vector3.FORWARD, true, false)
	await _frames(60 * 5)
	c["alarm_if_spotter_killed"] = Command.Level.keys()[game.hq.level]
	# wounds bleed until bandaged; a leg hit stops sprinting until a medkit
	await _fresh("carbine")
	_isolate([])
	game.god_mode = false
	game.player.take_damage(30.0, game.player.global_position + Vector3.FORWARD * 10.0, false, "legs")
	var hp0 := game.player.hp
	await _frames(120)
	c["bleeds"] = game.player.hp < hp0 - 0.3
	c["leg_wound"] = game.player.leg_wound
	game.player.start_bandage()
	await _frames(int(Player.BANDAGE_TIME * 60.0) + 10)
	c["bandaged"] = game.player.bleed == 0.0
	game.player.treat()
	c["splinted"] = not game.player.leg_wound
	game.god_mode = true
	return c


func _sim(seconds: float) -> void:
	await _fresh("carbine")
	game.god_mode = false
	game.player.global_position = Vector3(-12, 0, -8)
	game.player.crouch_toggle = true
	var frames := int(seconds * 60.0)
	var t0 := Time.get_ticks_usec()
	var modes := {}
	for i in frames:
		if i % 6 == 0:
			var best: Soldier = null
			var bd := INF
			for s in game.soldiers:
				if s.alive and s.sees:
					var d := s.global_position.distance_to(game.player.global_position)
					if d < bd:
						bd = d
						best = s
			if best:
				_look_at(best.global_position + Vector3(randf_range(-0.3, 0.3), 1.3 if best.crouch_k < 0.5 else 0.8, 0))
				Input.action_press("aim")
				if randf() < 0.6:
					Input.action_press("fire")
				else:
					Input.action_release("fire")
			else:
				Input.action_release("fire")
			if game.player.weapons.mag[0] == 0:
				Input.action_release("fire")
				game.player.weapons.start_reload()
		await get_tree().physics_frame
		for s in game.soldiers:
			if s.alive:
				modes["%s:%s" % [s.profile.id, Soldier.Mode.keys()[s.mode]]] = true
		if not game.player.alive:
			break
	Input.action_release("fire")
	Input.action_release("aim")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("SIM ", JSON.stringify({"seconds": game.time, "alive": game.player.alive, "hp": roundi(game.player.hp), "kills": game.stats.kills,
		"shots": game.stats.shots, "hits": game.stats.hits, "enemy_shots": game.stats.enemy_shots, "enemy_hits": game.stats.enemy_hits, "god": game.god_mode, "dmg": game.stats.damage_taken, "ms_per_frame": snappedf(ms / maxf(1.0, game.time * 60.0), 0.01), "modes": modes.keys()}))


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_snap(dir + "/menu.png")
	await _fresh("carbine")
	game.god_mode = true
	var views := [
		["start", Vector3(-54.2, 0, -26.5), -0.92, 0.0],
		["breach", Vector3(-47, 0, -29.3), PI / 2, 0.0],
		["loading", Vector3(-20, 0, -26), -PI / 2, 0.0],
		["office", Vector3(-22, 0, 18.5), -PI / 2 - 0.4, -0.1],
		["tower", Vector3(-2, 0, -27), -PI * 0.62, 0.12],
		["catwalk", Vector3(12.5, 4.2, 6.8), -PI / 2, -0.15],
		["ladder", Vector3(14.0, 0, 2.5), PI, 0.3],
		["duct", Vector3(-30.85, 0, 14.5), PI, 0.0],
		["hatch", Vector3(-13.0, 0, 28.8), PI, 0.55],
		["drone", Vector3(-10, 0, 2), 0.0, 0.45],
		["fire_escape", Vector3(49.1, 0, -12), 0.0, 0.15],
		["culvert", Vector3(-41.3, 0, 32), 0.0, -0.1],
		["data_door", Vector3(41.7, 4.2, 20.5), 0.0, 0.0],
		["gate", Vector3(-11, 0, -24), PI, 0.02],
		["corridor", Vector3(-28, 0, 21.2), -PI / 2, 0.0],
		["warehouse", Vector3(12, 0, -10), PI + 0.3, 0.0],
		["mezzanine", Vector3(20, 4.2, 25), -PI / 2, 0.0],
		["roof", Vector3(-2, 3.7, 14), 1.2, -0.2],
	]
	for v: Array in views:
		if v[0] == "drone":
			var dr: Drone = game.facility.drones[0]
			dr.position = Vector3(-10, 5.6, -4)
			dr.mode = Drone.Mode.TRACK
			dr._led.emission = Color("ff3020")
		game.player.global_position = v[1]
		game.player.yaw = v[2]
		game.player.pitch = v[3]
		await get_tree().create_timer(0.6).timeout
		_snap("%s/%s.png" % [dir, v[0]])
	Settings.primary = "dmr"
	await _fresh("dmr")
	game.player.global_position = Vector3(-11, 0, -24)
	game.player.yaw = PI
	Input.action_press("aim")
	await get_tree().create_timer(0.8).timeout
	_snap(dir + "/scope.png")
	Input.action_release("aim")
	game.player.global_position = Vector3(-10, 0, 8)
	_look_at(Vector3(-10, -0.5, 3))
	game.player.weapons.begin_throw()
	await get_tree().create_timer(0.4).timeout
	_snap(dir + "/throw.png")
	game.player.weapons.cancel_throw()
	game.player.global_position = Vector3(-26, 0, -18)
	game.player.yaw = PI * 0.75
	game.player.pitch = 0.0
	game.spawn_gadget("smoke", game.player.global_position + game.player.forward() * 9.0 + Vector3.UP * 0.3, Vector3.ZERO, true)
	await get_tree().create_timer(4.5).timeout
	_snap(dir + "/smoke.png")
	game.has_badge = true
	var term := _device("SECURITY TERMINAL")
	game.player.global_position = Vector3(-12.5, 0, -17.2)
	await get_tree().create_timer(0.2).timeout
	_look_at(term.use_point())
	await get_tree().create_timer(0.1).timeout
	_snap(dir + "/terminal.png")
	term.on_used(game)
	await get_tree().create_timer(0.3).timeout
	for cmd: String in ["ls", "loop 2", "unlock server", "relay off"]:
		game.console.input = cmd
		game.console.submit()
		await get_tree().create_timer(0.15).timeout
	game.console.input = "pow"
	await get_tree().create_timer(0.2).timeout
	_snap(dir + "/tablet.png")
	game.close_tablet()
	await _sight_shots(dir)


## The interface in the situations it has to make clear.
func _ui_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _fresh("carbine")
	await get_tree().create_timer(1.0).timeout
	_snap(dir + "/ui_start.png")
	# a guard is starting to notice you
	game.player.global_position = Vector3(-17, 0, -12)
	var g := _find("yard", -10.0)
	_look_at(g.head_pos())
	g.aware = 0.55
	g.state = Soldier.State.SUSPICIOUS
	g.investigate = game.player.global_position
	await get_tree().create_timer(0.4).timeout
	_snap(dir + "/ui_noticed.png")
	# combat, site alarm, wounded and bleeding
	game.god_mode = false
	game.player.take_damage(28.0, g.global_position, false, "legs")
	g.alert(game.player.global_position, "saw")
	game.god_mode = true
	await get_tree().create_timer(0.3).timeout
	_snap(dir + "/ui_calling.png")
	await get_tree().create_timer(1.2).timeout
	_snap(dir + "/ui_combat.png")
	# reloading
	game.player.weapons.mag[0] = 4
	game.player.weapons.start_reload()
	await get_tree().create_timer(0.5).timeout
	_snap(dir + "/ui_reload.png")
	# using a device, comms down, data copying
	await _fresh("carbine")
	game.comms_down = true
	var lap := _device("LAPTOP")
	lap.on_used(game)
	var term := _device("SECURITY TERMINAL")
	game.player.global_position = Vector3(-12.5, 0, -17.2)
	await get_tree().create_timer(0.2).timeout
	_look_at(term.use_point())
	Input.action_press("interact")
	await get_tree().create_timer(0.8).timeout
	_snap(dir + "/ui_using.png")
	Input.action_release("interact")
	# extraction
	await _fresh("carbine")
	game.mission = "extract"
	game.hq.caution("test")
	game.player.global_position = Vector3(-40, 0, -28)
	game.player.yaw = PI / 2
	await get_tree().create_timer(0.8).timeout
	_snap(dir + "/ui_extract.png")
	game.pause()
	await get_tree().create_timer(0.3).timeout
	_snap(dir + "/ui_pause.png")
	game.resume()
	# guards up close: the three types side by side, calm and alert
	await _fresh("carbine")
	_isolate([])
	var lineup := [_find("yard", -10.0), _find("wh", 28.0), _find("office", -27.0)]
	for i in lineup.size():
		var u: Soldier = lineup[i]
		u.alive = true
		u.visible = true
		u.global_position = Vector3(-14.0 + i * 1.6, 0, -6.0)
		u.yaw = 0.0
		u.patrol.clear()
		u.post = u.global_position
		u.state = Soldier.State.CALM if i != 1 else Soldier.State.COMBAT
	game.player.global_position = Vector3(-12.4, 0, -11.0)
	_look_at(Vector3(-12.4, 1.1, -6.0))
	await get_tree().create_timer(0.6).timeout
	_snap(dir + "/ui_guards.png")


## Hip and aimed views of every weapon against the same backdrop.
func _sight_shots(dir: String) -> void:
	for id: String in ["carbine", "smg", "dmr", "pistol", "ar7", "lmg", "shotgun"]:
		var wd: WeaponData = load("res://resources/weapons/%s.tres" % id)
		if id == "pistol":
			game.player.weapons.switch_to(1)
		else:
			game.player.weapons.swap_primary(wd, wd.mag_size, [wd.mag_size])
		game.player.global_position = Vector3(-11, 0, -24)
		game.player.yaw = PI
		game.player.pitch = 0.0
		await get_tree().create_timer(0.7).timeout
		_snap("%s/hip_%s.png" % [dir, id])
		Input.action_press("aim")
		await get_tree().create_timer(0.7).timeout
		_snap("%s/ads_%s.png" % [dir, id])
		Input.action_release("aim")
		await get_tree().create_timer(0.3).timeout


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
