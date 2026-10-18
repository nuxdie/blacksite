class_name Soldier
extends CharacterBody3D
## A guard. Calm guards patrol or stand watch; suspicious ones investigate; in combat they work
## with their squad: take cover, peek, suppress, flank, grenade campers and search when contact is lost.

enum State { CALM, SUSPICIOUS, COMBAT }
enum Mode { IDLE, MOVE, HOLD, EXPOSED, FLANK, RUSH, ADVANCE, THROW, SEARCH, FLEE }

const GRAVITY := 20.0

@onready var agent: NavigationAgent3D = $Agent
@onready var model: SoldierModel = $Model

var profile: SoldierProfile
## The firearm they carry: their rounds follow the same rules as yours.
var weapon: WeaponData
var squad: Squad
var game: Game
var alive := true
var hp := 100.0
var yaw := 0.0
var base_yaw := 0.0
var look_yaw := 0.0
var look_t := 3.0
var state := State.CALM
var mode := Mode.IDLE
var aware := 0.0
var investigate := Vector3.ZERO
var patrol: Array[Vector3] = []
var patrol_i := 0
var wait_t := 0.0
var susp_t := 0.0
var search_t := 0.0
var sees := false
var sees_head := false
var sees_chest := false
var dist_p := 99.0
var fwd_dot := 0.0
var perc_t := 0.0
var think_t := 0.0
var react := 0.0
var cover_point := Vector3.ZERO
var fire_point := Vector3.ZERO
var has_cover := false
var low_cover := false
var peeking := false
var hide_t := 0.0
var peek_t := 0.0
var suppressing := false
var crouch := false
var crouch_k := 0.0
var mag := 30
var reloading := 0.0
var burst := 0
var shot_t := 0.5
var aim_err := 0.15
var supp := 0.0
var flinch := 0.0
var blind := 0.0
var grenades := 0
var flee_from: Gadget = null
var flee_t := 0.0
var throw_t := 0.0
var flank_done := false
var anim := 0.0
var voice_t := 0.0
var step_phase := 0.0
var had_sight := false
var acquire_t := -9.0
var death_t := 0.0
var fall_side := 0.0
var tagged := false
## Where a marked guard was last seen by the player, and when.
var tag_seen := Vector3.ZERO
var tag_seen_t := -99.0
var corpse_found := false
var corpse_check := 0.0
var stuck_t := 0.0
var stuck_pos := Vector3.ZERO
var repath := 0.0
## A job security sent this guard to do: walk to pos and work on device.
var task: Dictionary = {}
## Access levels on this guard's badge; dropped on death, and readable up close.
var badge: Array[String] = []
## Radio identity, and where they're supposed to be standing.
var callsign := ""
var call_order := 0
var post := Vector3.ZERO
var post_yaw := 0.0
## HQ already knows this one is gone (missed a check, or the body was found).
var accounted := false
## Why their awareness of you last went up: seen, lit, close, heard. Shown so you know why.
var notice := ""
## A hit to the legs slows them for good.
var limp := 1.0
## Climbing a ladder along a navigation link: {ladder, to_y, exit}.
var climb: Dictionary = {}
## Seconds left on a radio call to HQ (hand on the radio); killing them now stops it.
var radio_t := 0.0


func setup(p_profile: SoldierProfile, p_squad: Squad, pos: Vector3, p_yaw: float, p_patrol: Array) -> void:
	profile = p_profile
	squad = p_squad
	hp = profile.health
	weapon = load("res://resources/weapons/%s.tres" % profile.weapon_id)
	mag = weapon.mag_size
	grenades = profile.grenades
	position = pos
	post = pos
	post_yaw = p_yaw
	yaw = p_yaw
	base_yaw = p_yaw
	look_yaw = p_yaw
	for wp in p_patrol:
		patrol.append(Vector3(wp[0], pos.y, wp[1]))
	wait_t = randf_range(0.0, 2.0)
	perc_t = randf() * 0.1
	think_t = randf() * 0.5
	anim = randf() * 10.0
	squad.members.append(self)


func _ready() -> void:
	collision_layer = Layers.SOLDIERS
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.SOLDIERS | Layers.RAILING
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46.0)
	model.build(profile)
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	agent.radius = 0.4
	agent.height = 1.8
	agent.path_max_distance = 3.0
	agent.link_reached.connect(_on_link)


# ------------------------------------------------------------------ geometry helpers

static func yaw_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func facing() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func eye() -> Vector3:
	return global_position + Vector3.UP * lerpf(1.62, 0.95, crouch_k)


func head_pos() -> Vector3:
	return global_position + Vector3.UP * lerpf(1.67, 1.0, crouch_k) + facing() * 0.03


## Hit zones: [zone, centre, radius].
func zones() -> Array:
	var k := crouch_k
	var p := global_position
	return [
		["head", p + Vector3.UP * lerpf(1.67, 1.0, k), 0.14],
		["body", p + Vector3.UP * lerpf(1.36, 0.78, k), 0.25],
		["body", p + Vector3.UP * lerpf(1.08, 0.6, k), 0.22],
		["legs", p + Vector3.UP * lerpf(0.55, 0.3, k), 0.21],
	]


func aim_point() -> Vector3:
	if sees:
		return game.player.chest_pos() if sees_chest else game.player.eye_pos()
	return squad.last_known + Vector3.UP * 1.1


func turn_to(target_yaw: float, rate: float, dt: float) -> void:
	yaw += clampf(angle_difference(yaw, target_yaw), -rate * dt, rate * dt)


func face(p: Vector3, rate: float, dt: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		turn_to(yaw_of(d), rate, dt)


func say(kind: String, force := false) -> void:
	game.say(self, kind, force)


# ------------------------------------------------------------------ ladders

func _on_link(details: Dictionary) -> void:
	var owner_node: Object = details.get("owner")
	if owner_node == null or not owner_node.has_meta("ladder"):
		return
	var l: Ladder = owner_node.get_meta("ladder")
	var exit: Vector3 = details.get("link_exit_position", l.top_exit)
	var up := exit.y > global_position.y + 0.5
	climb = {"ladder": l, "to_y": l.top_y() if up else l.global_position.y, "exit": l.top_exit if up else l.bottom_exit(), "up": up}
	global_position = l.climb_point(global_position.y if up else l.top_y() - 0.9)


func _climb(dt: float) -> void:
	var l: Ladder = climb.ladder
	var y := move_toward(global_position.y, float(climb.to_y), Ladder.CLIMB_SPEED * 0.85 * dt)
	global_position = l.climb_point(y)
	velocity = Vector3.ZERO
	yaw = yaw_of(-l.normal)
	if absf(y - float(climb.to_y)) < 0.02:
		global_position = climb.exit
		climb = {}
		repath = 0.0


# ------------------------------------------------------------------ navigation

func go_to(target: Vector3) -> bool:
	var map := get_world_3d().navigation_map
	var snapped := NavigationServer3D.map_get_closest_point(map, target)
	agent.target_position = snapped
	agent.get_next_path_position()
	return agent.is_target_reachable()


func path_done() -> bool:
	return agent.is_navigation_finished()


func steer() -> Vector3:
	if agent.is_navigation_finished():
		return Vector3.ZERO
	var next := agent.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


func ground_move(dir: Vector3, speed: float, dt: float) -> void:
	var k := minf(1.0, 10.0 * dt)
	velocity.x = lerpf(velocity.x, dir.x * speed * limp, k)
	velocity.z = lerpf(velocity.z, dir.z * speed * limp, k)


func steer_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.25 else Vector3.ZERO


# ------------------------------------------------------------------ perception

func alert(pos: Vector3, how: String) -> void:
	if not alive:
		return
	var now := game.time
	if how == "saw":
		squad.report(pos, now)
	elif not squad.known or squad.since_seen(now) > 2.0:
		squad.report(pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), now - 1.5)
	if state != State.COMBAT:
		state = State.COMBAT
		react = randf_range(0.25, 0.5) if how == "saw" else randf_range(0.4, 1.0)
		mode = Mode.IDLE
		think_t = react
		aim_err = 0.16
		game.detected = true
		var line := {"saw": "contact", "body": "body", "radio": "radio", "shout": "radio"}.get(how, "heard") as String
		say(line, how != "radio" and how != "shout")
		if how != "radio" and how != "shout":
			game.shout(self, pos)
			game.hq.contact(self, pos, how)
		for o in squad.members:
			if o != self and o.alive and o.state != State.COMBAT:
				game.radio_alert(o, randf_range(0.4, 1.4))


func make_suspicious(pos: Vector3, amount: float, line := "huh", delay := 0.0) -> void:
	if not alive or state == State.COMBAT:
		return
	if state == State.CALM:
		state = State.SUSPICIOUS
		susp_t = delay
		say(line)
	aware = maxf(aware, amount)
	investigate = pos


func _perceive(dt: float) -> void:
	perc_t -= dt
	var p := game.player
	if perc_t <= 0.0:
		perc_t = 0.1
		var e := eye()
		var h := p.eye_pos()
		var c := p.chest_pos()
		var to := h - e
		dist_p = to.length()
		var flat := Vector2(to.x, to.z)
		fwd_dot = (to.x * facing().x + to.z * facing().z) / maxf(flat.length(), 0.001)
		var fov := -0.3 if state == State.COMBAT else (0.15 if state == State.SUSPICIOUS else 0.4)
		var can := p.alive and dist_p < 85.0 and (fwd_dot > fov or dist_p < 2.2)
		sees_head = can and game.los(e, h) and not game.smoke_blocks(e, h)
		sees_chest = can and game.los(e, c) and not game.smoke_blocks(e, c)
		sees = sees_head or sees_chest
		if sees and state == State.COMBAT:
			squad.report(p.global_position, game.time)
	if state == State.COMBAT:
		return
	if sees:
		var stance := 0.45 if p.crouched else 1.0
		var hs := p.speed_2d()
		var move := 0.45 if hs < 0.5 else (1.6 if p.sprinting else 1.0)
		var center := clampf((fwd_dot - 0.2) / 0.7, 0.35, 1.0)
		var exposure := 1.0 if sees_chest else 0.55
		var rate := 1.9 / (1.0 + dist_p / 8.0) * stance * move * center * exposure * game.player_light * game.hq.vigilance()
		aware += rate * dt * (1.5 if state == State.SUSPICIOUS else 1.0) + (dt * 2.0 if dist_p < 3.5 else 0.0)
		investigate = p.global_position
		notice = "lit" if game.player_light >= 0.7 else ("close" if dist_p < 6.0 else "seen")
	else:
		aware = maxf(0.0, aware - dt * 0.06)
		if aware < 0.05:
			notice = ""
	var loud := 11.0 if p.sprinting else (0.0 if p.crouched else (4.0 if p.speed_2d() > 1.0 else 0.0))
	if game.hq.level == Command.Level.ALARM:
		loud *= 0.5
	if loud > 0.0 and global_position.distance_to(p.global_position) < loud:
		# footsteps carry half as far through a wall
		if sees_head or sees_chest or global_position.distance_to(p.global_position) < loud * 0.5:
			aware += dt * 0.6
			investigate = p.global_position
			notice = "heard"
	if aware >= 1.0:
		alert(p.global_position, "saw")
	elif aware > 0.4 and state == State.CALM:
		state = State.SUSPICIOUS
		susp_t = 0.0
		say("huh")


func _check_corpses(dt: float) -> void:
	corpse_check -= dt
	if corpse_check > 0.0:
		return
	corpse_check = 0.5
	for c in game.soldiers:
		if c.alive or c.corpse_found or c.death_t < 0.5:
			continue
		var d := global_position.distance_to(c.global_position)
		if d > 24.0:
			continue
		var to := c.global_position - global_position
		if (to.x * facing().x + to.z * facing().z) / maxf(Vector2(to.x, to.z).length(), 0.001) < 0.3:
			continue
		if d > 5.0 + 19.0 * game.facility.light_level(c.global_position, []):
			continue
		if game.los(eye(), c.global_position + Vector3.UP * 0.3):
			c.corpse_found = true
			c.accounted = true
			alert(c.global_position, "body")
			squad.last_known_time = game.time - 6.0
			return


# ------------------------------------------------------------------ behaviour

func tick(dt: float) -> void:
	if not alive:
		_tick_dead(dt)
		return
	anim += dt
	voice_t -= dt
	radio_t = maxf(0.0, radio_t - dt)
	flinch -= dt
	supp = maxf(0.0, supp - dt * (0.6 if profile.id == "heavy" else 0.35))
	if blind > 0.0:
		blind -= dt
		sees = false
		sees_head = false
		sees_chest = false
		crouch = false
		ground_move(Vector3(sin(anim * 1.3), 0, cos(anim * 0.9)), 0.7, dt)
		turn_to(yaw + sin(anim * 3.0), 2.0, dt)
		if blind <= 0.0:
			think_t = 0.0
			aim_err = 0.2
	elif not climb.is_empty():
		_perceive(dt)
		_climb(dt)
		crouch_k = 0.0
		model.rotation.y = yaw
		model.animate(dt, self)
		return
	else:
		_perceive(dt)
		if not task.is_empty() and state == State.COMBAT:
			cancel_task()
		if not task.is_empty() and game.player.alive:
			_do_task(dt)
		elif game.player.alive:
			match state:
				State.CALM: _calm(dt)
				State.SUSPICIOUS: _suspicious(dt)
				State.COMBAT: _combat(dt)
		else:
			ground_move(Vector3.ZERO, 0.0, dt)
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	else:
		velocity.y = -0.5
	move_and_slide()
	_check_stuck(dt)
	var hs := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hs > 0.6:
		var prev := step_phase
		step_phase += hs * dt * 0.6
		if floori(prev) != floori(step_phase) and global_position.distance_to(game.player.global_position) < 24.0:
			Sfx.play_at("enemy_step", global_position, -2.0 if hs > 3.0 else -8.0)
	crouch_k = lerpf(crouch_k, 1.0 if crouch else 0.0, minf(1.0, dt * 7.0))
	model.rotation.y = yaw
	model.animate(dt, self)
	model.flashlight.visible = alive and blind <= 0.0 and (state == State.SUSPICIOUS or mode == Mode.SEARCH or (state == State.CALM and (not patrol.is_empty() or game.hq.level != Command.Level.NORMAL)))


func _check_stuck(dt: float) -> void:
	if path_done() or not is_on_floor():
		stuck_t = 0.0
		return
	stuck_t += dt
	if stuck_t > 1.2:
		if stuck_pos.distance_to(global_position) < 0.4:
			agent.target_position = global_position
			think_t = 0.0
			repath = 0.0
			if state == State.COMBAT and mode != Mode.HOLD:
				mode = Mode.IDLE
		stuck_pos = global_position
		stuck_t = 0.0


func _calm(dt: float) -> void:
	crouch = false
	if not patrol.is_empty():
		var wp := patrol[patrol_i]
		if wait_t > 0.0:
			wait_t -= dt
			ground_move(Vector3.ZERO, 0.0, dt)
			turn_to(look_yaw, 1.2, dt)
			if randf() < dt * 0.4:
				look_yaw = yaw + randf_range(-1.2, 1.2)
		else:
			repath -= dt
			if repath <= 0.0:
				go_to(wp)
				repath = 6.0
			var dir := steer()
			if dir == Vector3.ZERO or Vector2(wp.x - global_position.x, wp.z - global_position.z).length() < 0.8:
				patrol_i = (patrol_i + 1) % patrol.size()
				wait_t = randf_range(1.5, 4.0)
				repath = 0.0
				look_yaw = yaw + randf_range(-1.0, 1.0)
			else:
				ground_move(dir, profile.walk_speed, dt)
				turn_to(yaw_of(dir), 3.0, dt)
	elif Vector2(post.x - global_position.x, post.z - global_position.z).length() > 1.2:
		repath -= dt
		if repath <= 0.0:
			go_to(post)
			repath = 4.0
		var back := steer()
		if back == Vector3.ZERO:
			back = steer_to(post)
		ground_move(back, profile.walk_speed, dt)
		if back != Vector3.ZERO:
			turn_to(yaw_of(back), 3.0, dt)
		base_yaw = post_yaw
	else:
		ground_move(Vector3.ZERO, 0.0, dt)
		look_t -= dt
		if look_t <= 0.0:
			look_t = randf_range(3.0, 7.0) / game.hq.vigilance()
			look_yaw = base_yaw + randf_range(-0.9, 0.9) * game.hq.vigilance()
		turn_to(look_yaw, 0.8, dt)
	_check_corpses(dt)


func _suspicious(dt: float) -> void:
	susp_t += dt
	crouch = false
	if susp_t < 1.2:
		ground_move(Vector3.ZERO, 0.0, dt)
		face(investigate, 2.5, dt)
		return
	repath -= dt
	if repath <= 0.0:
		go_to(investigate)
		repath = 2.0
	var dir := steer()
	if dir != Vector3.ZERO and global_position.distance_to(investigate) > 2.0:
		ground_move(dir, profile.walk_speed * 1.1, dt)
		turn_to(yaw_of(dir), 2.5, dt)
	else:
		ground_move(Vector3.ZERO, 0.0, dt)
		turn_to(yaw + 1.0, 1.2, dt)
	_check_corpses(dt)
	if (aware < 0.15 and susp_t > 8.0 * game.hq.vigilance()) or susp_t > 20.0 * game.hq.vigilance():
		state = State.CALM
		aware = 0.0
		say("calm")
		if not patrol.is_empty():
			wait_t = 1.0
			repath = 0.0


func assign_task(pos: Vector3, device: Device, work: float) -> void:
	task = {"pos": pos, "device": device, "work": work, "routed": false}
	if device.kind != Device.Kind.LAPTOP:
		say("repair")


## Dropped the job (combat, death): it goes back on the list for someone else later.
func cancel_task() -> void:
	if task.is_empty():
		return
	var dv: Device = task.device
	dv.repair_pending = false
	task = {}
	if dv.kind != Device.Kind.LAPTOP:
		game.requeue_repair(dv)


func _do_task(dt: float) -> void:
	var dv: Device = task.device
	var pos: Vector3 = task.pos
	crouch = false
	if not task.routed:
		go_to(pos)
		task.routed = true
	var flat := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	if flat > 1.3:
		var dir := steer()
		if dir == Vector3.ZERO:
			dir = steer_to(pos)
		ground_move(dir, profile.walk_speed * 1.4, dt)
		if dir != Vector3.ZERO:
			turn_to(yaw_of(dir), 3.0, dt)
		return
	ground_move(Vector3.ZERO, 0.0, dt)
	face(dv.global_position, 3.0, dt)
	task.work = float(task.work) - dt
	if float(task.work) > 0.0:
		return
	task = {}
	if dv.kind == Device.Kind.LAPTOP:
		dv.repair_pending = false
		dv.drive_pulled()
		say("pulled", true)
		alert(dv.global_position, "heard")
	else:
		dv.repaired(game)


func flee(g: Gadget) -> void:
	if flee_from:
		return
	flee_from = g
	flee_t = 0.0
	say("nade_warn", true)
	if state != State.COMBAT:
		alert(game.player.global_position, "heard")
	var best := global_position
	var bd := 0.0
	var map := get_world_3d().navigation_map
	for _k in 16:
		var p := NavigationServer3D.map_get_closest_point(map, global_position + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9)))
		var d := p.distance_to(g.global_position)
		if d > bd and absf(p.y - global_position.y) < 1.5:
			bd = d
			best = p
	go_to(best)
	has_cover = false
	mode = Mode.FLEE


func _min_aim_err() -> float:
	var p := game.player
	return (0.014 + clampf(p.speed_2d() / Player.WALK, 0.0, 1.6) * 0.02 - p.crouch_k * 0.004 + supp * 0.05 + dist_p * 0.0004) * (2.0 if flinch > 0.0 else 1.0)


func _try_shoot(dt: float, target: Vector3, extra := 0.0, suppressive := false) -> bool:
	if reloading > 0.0 or flinch > 0.0 or blind > 0.0:
		return false
	if mag <= 0:
		reloading = 2.6
		say("reload")
		return false
	if absf(angle_difference(yaw, yaw_of(target - global_position))) > 0.3:
		return false
	shot_t -= dt
	if shot_t > 0.0:
		return false
	if burst <= 0:
		burst = randi_range(profile.burst_min, profile.burst_max)
	mag -= 1
	game.soldier_shot(self, target, extra, suppressive)
	burst -= 1
	shot_t = 60.0 / weapon.rpm * randf_range(1.0, 1.3) if burst > 0 else randf_range(profile.pause_min, profile.pause_max)
	return true


func _combat(dt: float) -> void:
	var since := squad.since_seen(game.time)
	if react > 0.0:
		react -= dt
		face(squad.last_known, 4.0, dt)
		ground_move(Vector3.ZERO, 0.0, dt)
		return
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			mag = weapon.mag_size
			burst = 0
	if sees:
		if not had_sight and game.time - acquire_t > 2.5:
			aim_err = maxf(aim_err, 0.09 + dist_p * 0.002)
		had_sight = true
		aim_err = maxf(_min_aim_err(), aim_err - dt * 0.055 * (0.7 if profile.id == "heavy" else 1.0))
	else:
		if had_sight:
			acquire_t = game.time
		had_sight = false
		aim_err = minf(0.2, aim_err + dt * 0.03)
	if mode == Mode.FLEE:
		flee_t += dt
		crouch = false
		var fd := steer()
		ground_move(fd, profile.run_speed, dt)
		if fd != Vector3.ZERO:
			turn_to(yaw_of(fd), 8.0, dt)
		if flee_t > 2.6 or not is_instance_valid(flee_from):
			flee_from = null
			mode = Mode.IDLE
			think_t = 0.0
		return
	think_t -= dt
	if think_t <= 0.0:
		_think()
	var tp := aim_point()
	var lkp_aim := squad.last_known + Vector3.UP * 1.1
	match mode:
		Mode.MOVE, Mode.RUSH, Mode.ADVANCE, Mode.FLANK:
			crouch = false
			var dir := steer()
			var speed := profile.run_speed * (0.6 if mode == Mode.FLANK and sees else 1.0)
			ground_move(dir, speed, dt)
			if sees and (mode != Mode.MOVE or dist_p < 32.0):
				face(tp, 6.0, dt)
				_try_shoot(dt, tp, 0.01 if mode == Mode.ADVANCE else 0.025)
			elif dir != Vector3.ZERO:
				turn_to(yaw_of(dir), 6.0, dt)
			if mode == Mode.ADVANCE and not sees and since < 3.0 and game.los(eye(), lkp_aim):
				face(lkp_aim, 4.0, dt)
				_try_shoot(dt, lkp_aim, 0.05, true)
			if path_done():
				if mode == Mode.FLANK:
					flank_done = true
					mode = Mode.EXPOSED
					game.release_flanker_later(squad, self)
				elif mode == Mode.MOVE:
					mode = Mode.HOLD
					peeking = false
					hide_t = randf_range(0.3, 0.9)
				else:
					think_t = 0.0
		Mode.HOLD:
			if not peeking:
				hide_t -= dt
				crouch = low_cover or fire_point.distance_to(cover_point) < 0.1
				ground_move(steer_to(cover_point), 2.2, dt)
				face(tp if sees else lkp_aim, 3.0, dt)
				if hide_t <= 0.0 and reloading <= 0.0 and supp < 0.55:
					peeking = true
					peek_t = randf_range(1.8, 3.2)
					suppressing = since < 2.5 and randf() < 0.45
			else:
				peek_t -= dt
				crouch = false
				ground_move(steer_to(fire_point), 2.2, dt)
				if sees:
					face(tp, 6.0, dt)
					_try_shoot(dt, tp)
				elif suppressing and since < 3.0 and game.los(eye(), lkp_aim):
					face(lkp_aim, 5.0, dt)
					if _try_shoot(dt, lkp_aim, 0.04, true) and randf() < 0.08:
						say("supp")
				else:
					face(lkp_aim, 4.0, dt)
				if peek_t <= 0.0 or supp > 0.75 or reloading > 0.0:
					peeking = false
					hide_t = randf_range(0.8, 1.8) + supp * 2.0
		Mode.EXPOSED:
			crouch = profile.id == "rifleman" and dist_p > 10.0
			ground_move(Vector3.ZERO, 0.0, dt)
			if sees:
				face(tp, 6.0, dt)
				_try_shoot(dt, tp)
			else:
				face(lkp_aim, 4.0, dt)
				var blind_fire := profile.doctrine == "advance" or game.smoke_blocks(eye(), lkp_aim)
				if blind_fire and since < 3.0 and game.los(eye(), lkp_aim):
					_try_shoot(dt, lkp_aim, 0.05, true)
		Mode.THROW:
			ground_move(Vector3.ZERO, 0.0, dt)
			crouch = false
			face(squad.last_known, 6.0, dt)
			throw_t -= dt
			if throw_t <= 0.0:
				var from := eye() + facing() * 0.3 + Vector3.UP * 0.2
				var tgt := squad.last_known + Vector3(randf_range(-1.5, 1.5), 0.1, randf_range(-1.5, 1.5))
				game.enemy_throw(from, tgt)
				mode = Mode.IDLE
				think_t = 0.3
				has_cover = false
		Mode.SEARCH:
			crouch = false
			search_t += dt
			var sd := steer()
			ground_move(sd, profile.walk_speed * 1.3, dt)
			if sees:
				think_t = 0.0
			elif sd != Vector3.ZERO:
				turn_to(yaw_of(sd) + sin(game.time * 1.3) * 0.5, 3.0, dt)
			else:
				turn_to(yaw + 1.0, 1.5, dt)
				if randf() < dt * 0.5:
					go_to(squad.last_known + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9)))
			_check_corpses(dt)
			if search_t > 28.0:
				for o in squad.members:
					if o.alive and o.state == State.COMBAT:
						o.state = State.SUSPICIOUS
						o.aware = 0.6
						o.investigate = squad.last_known
						o.susp_t = 0.0
						o.mode = Mode.IDLE
						o.has_cover = false
				squad.known = false
				squad.searcher = null
				say("lost")
		_:
			ground_move(Vector3.ZERO, 0.0, dt)
			face(tp if sees else lkp_aim, 4.0, dt)
			if sees:
				_try_shoot(dt, tp, 0.01)


func _think() -> void:
	var since := squad.since_seen(game.time)
	var threat: Vector3 = game.player.global_position if sees else squad.last_known
	think_t = randf_range(0.5, 0.9)
	# a squad with a fresh fix on the player sends someone around
	if since < 4.0 and squad.flanker == null and game.time > squad.flank_cooldown:
		var cands: Array[Soldier] = []
		for o in squad.members:
			if o.alive and o.profile.doctrine != "advance" and o.reloading <= 0.0 and o.state == State.COMBAT and o.blind <= 0.0:
				cands.append(o)
		if cands.size() >= 2 or (cands.size() == 1 and cands[0].profile.doctrine == "rush"):
			var f: Soldier = cands.pick_random()
			for o in cands:
				if o.profile.doctrine == "rush":
					f = o
			squad.flanker = f
			f.flank_done = false
			if f.mode != Mode.RUSH:
				f.mode = Mode.IDLE
	# grenade a player who stays put
	if since < 3.0:
		if squad.camp_pos.distance_to(game.player.global_position) > 3.5:
			squad.camp_pos = game.player.global_position
			squad.camp_time = game.time
		if game.time - squad.camp_time > 5.0 and game.time > squad.grenade_cooldown and grenades > 0 and reloading <= 0.0 and mode != Mode.THROW:
			var d := global_position.distance_to(squad.last_known)
			if d > 7.0 and d < 30.0:
				mode = Mode.THROW
				throw_t = 0.7
				grenades -= 1
				squad.grenade_cooldown = game.time + 12.0
				say("nade", true)
				return
	if mode == Mode.THROW:
		return
	if profile.doctrine == "rush":
		if supp > 0.7 and dist_p > 8.0 and mode != Mode.HOLD:
			var c := Cover.find(self, threat, Cover.HOLD)
			if not c.is_empty():
				_goto_cover(c)
				return
		if since > 12.0:
			_start_search()
			return
		repath -= 0.7
		if mode != Mode.RUSH or repath <= 0.0:
			if go_to(threat):
				if mode != Mode.RUSH:
					say("push")
				mode = Mode.RUSH
				repath = 1.2
		return
	if squad.flanker == self:
		if not flank_done and mode != Mode.FLANK:
			var c := Cover.find(self, squad.last_known, Cover.FLANK)
			if not c.is_empty() and go_to(c.point):
				mode = Mode.FLANK
				cover_point = c.point
				fire_point = c.point
				has_cover = true
				low_cover = false
				say("flank")
				return
			squad.flanker = null
			squad.flank_cooldown = game.time + 5.0
		if mode == Mode.FLANK:
			return
	if profile.doctrine == "advance" and hp > profile.health * 0.4:
		if since > 12.0:
			_start_search()
			return
		if global_position.distance_to(threat) > 16.0 or not sees:
			repath -= 0.7
			if mode != Mode.ADVANCE or repath <= 0.0:
				go_to(threat)
				mode = Mode.ADVANCE
				repath = 2.0
				if randf() < 0.3:
					say("push")
		else:
			mode = Mode.EXPOSED
		return
	if since > 9.0:
		_start_search()
		return
	if mode == Mode.MOVE and not path_done():
		return
	var at_cover := has_cover and Vector2(cover_point.x - global_position.x, cover_point.z - global_position.z).length() < 1.6
	if at_cover and Cover.protects(game, cover_point, threat):
		if mode != Mode.HOLD:
			mode = Mode.HOLD
			peeking = false
			hide_t = randf_range(0.4, 1.0)
		return
	var cov := Cover.find(self, threat, Cover.RETREAT if hp < profile.health * 0.45 else Cover.HOLD)
	if not cov.is_empty():
		_goto_cover(cov)
	else:
		mode = Mode.EXPOSED


func _goto_cover(c: Dictionary) -> void:
	if not go_to(c.point):
		mode = Mode.EXPOSED
		return
	cover_point = c.point
	fire_point = c.fire
	low_cover = c.low
	has_cover = true
	mode = Mode.MOVE
	peeking = false


func _start_search() -> void:
	if squad.searcher and squad.searcher != self and squad.searcher.alive and squad.searcher.mode == Mode.SEARCH:
		mode = Mode.HOLD if has_cover else Mode.EXPOSED
		return
	if mode != Mode.SEARCH:
		squad.searcher = self
		mode = Mode.SEARCH
		search_t = 0.0
		say("search" if squad.alive_members().size() > 1 else "lost")
		go_to(squad.last_known)
		has_cover = false


# ------------------------------------------------------------------ damage

func take_hit(amount: float, dir: Vector3, zone: String, from_player: bool, quiet := false) -> void:
	if not alive:
		return
	hp -= amount
	flinch = 0.22
	if zone == "legs":
		limp = 0.55
	aim_err += 0.04
	supp = minf(1.0, supp + 0.3)
	if hp <= 0.0:
		die(dir, zone == "head", false)
		return
	if state != State.COMBAT:
		alert(game.player.global_position, "saw" if from_player and not quiet else "heard")
	if hp < profile.health * 0.5:
		say("hit")
	if mode == Mode.HOLD and peeking:
		peeking = false
		hide_t = randf_range(1.2, 2.2)


func die(dir: Vector3, headshot: bool, takedown: bool) -> void:
	alive = false
	hp = 0.0
	blind = 0.0
	death_t = 0.0
	fall_side = randf_range(-0.4, 0.4)
	if dir.length() > 0.1:
		yaw = yaw_of(dir)
	model.rotation.y = yaw
	collision_layer = 0
	collision_mask = Layers.WORLD
	velocity = Vector3.ZERO
	cancel_task()
	if squad.flanker == self:
		squad.flanker = null
	if squad.searcher == self:
		squad.searcher = null
	game.on_soldier_killed(self, headshot, takedown)


## Quickload: put this guard back as saved, without any of the side effects of dying again.
func load_state(d: Dictionary) -> void:
	global_position = d.pos
	yaw = d.yaw
	hp = d.hp
	aware = d.aware
	patrol_i = d.patrol_i
	corpse_found = d.corpse_found
	accounted = d.accounted
	tagged = d.tagged
	tag_seen = d.tag_seen
	mag = d.mag
	limp = d.limp
	badge.clear()
	for a: String in d.badge:
		badge.append(a)
	model.rotation.y = yaw
	if not d.alive:
		alive = false
		hp = 0.0
		fall_side = d.fall_side
		death_t = 1.0
		collision_layer = 0
		collision_mask = Layers.WORLD
		for _i in 30:
			model.animate_death(0.1, 1.0, fall_side)
		return
	state = d.state
	if state == State.COMBAT:
		squad.report(game.player.global_position, game.time - 2.0)
		react = 0.5
	elif state == State.SUSPICIOUS:
		investigate = global_position + facing() * 3.0


func _tick_dead(dt: float) -> void:
	if game.player.drag_body == self:
		return
	if death_t < 1.0:
		death_t = minf(1.0, death_t + dt * 1.6)
		model.animate_death(dt, death_t, fall_side)
		if not is_on_floor():
			velocity.y -= GRAVITY * dt
			move_and_slide()
