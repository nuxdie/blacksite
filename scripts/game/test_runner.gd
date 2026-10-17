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
			s.collision_layer = 0


func _find(squad: String, x: float) -> Soldier:
	for s in game.soldiers:
		if s.squad.id == squad and absf(s.global_position.x - x) < 1.0:
			return s
	return null


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
		["start", Vector3(-44, 0, -32), PI, 0.0],
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


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
