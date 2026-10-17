class_name TestRunner
extends Node
## Automated checks, enabled with user arguments after "--":
##   --autotest          run gameplay checks and print results as JSON, then quit
##   --shots=<dir>       capture screenshots at fixed viewpoints (needs a window)
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
	_look_at(Vector3(-12, 0.6, -1.4))
	await _fire(3)
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
	_tap("interact")
	await _frames(2)
	hk["cam1_looped"] = cams[0].looped > 0.0
	_tap("lean_right")
	_tap("lean_right")
	_tap("gadget_cycle")
	await _frames(2)
	hk["cam3_disabled"] = cams[2].disabled
	_tap("lean_right")
	_tap("gadget_cycle")
	await _frames(2)
	hk["intrusion_locked"] = junction.locked > 0.0
	hk["tablet_closed"] = game.tablet_access == null
	await _frames(60 * 22)
	hk["repair_dispatched"] = cams[2].repair_pending or not cams[2].disabled
	# badge: the booth guard carries one; with it the terminal logs in cleanly
	await _fresh("carbine")
	var booth := _find("yard", -12.5)
	booth.die(Vector3.FORWARD, false, true)
	await _frames(60)
	for p in game.facility.pickups:
		if not p.taken and p.kind == Pickup.Kind.BADGE:
			game.player.global_position = p.global_position
	await _frames(10)
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
	_tap("reload")
	await _frames(2)
	hk["all_cameras_down"] = cams.all(func(d: Device) -> bool: return d.disabled)
	_tap("hack")
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
		["gate", Vector3(-11, 0, -24), PI, 0.02],
		["corridor", Vector3(-28, 0, 21.2), -PI / 2, 0.0],
		["warehouse", Vector3(12, 0, -10), PI + 0.3, 0.0],
		["mezzanine", Vector3(20, 4.2, 25), -PI / 2, 0.0],
		["roof", Vector3(-2, 3.7, 14), 1.2, -0.2],
	]
	for v: Array in views:
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
	await get_tree().create_timer(0.8).timeout
	_snap(dir + "/tablet.png")
	game.close_tablet()
	await _sight_shots(dir)


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
