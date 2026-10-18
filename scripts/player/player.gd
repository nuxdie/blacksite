class_name Player
extends CharacterBody3D
## First-person operator: movement, stance, leaning, vaulting, aiming, and taking hits.

const GRAVITY := 20.0
const WALK := 4.3
const SPRINT := 6.8
const CROUCH_SPEED := 2.1
const DRAG_SPEED := 1.6
const ACCEL := 11.0
const JUMP := 5.6
const EYE_STAND := 1.62
const EYE_CROUCH := 0.98
const EYE_PEEK := 1.45
const H_STAND := 1.8
const H_CROUCH := 1.15
const LEAN := 0.42
const FOV := 74.0
const BREATH := 4.0
const MAX_HP := 100.0
const BANDAGE_TIME := 3.2
## You wear the same kit they do: a plate carrier and a bump helmet that won't stop a rifle round.
const ARMOR := 0.8
const HELMET := 1.0

@onready var col: CollisionShape3D = $Collision
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var viewmodel: ViewModel = $Head/Camera/ViewModel
@onready var weapons: Weapons = $Weapons

var game: Game
var active := false
var alive := true
var hp := MAX_HP
var yaw := PI
var pitch := 0.0
var crouch_toggle := false
var crouched := false
var crouch_k := 0.0
var eye_h := EYE_STAND
var peek := 0.0
var lean_k := 0.0
var lean_reach := 0.0
var ads := 0.0
var sprinting := false
var supp := 0.0
var last_hit := 99.0
var step_phase := 0.0
var land := 0.0
var bob := 0.0
var roll := 0.0
var recov := 0.0
var since_shot := 9.0
var bloom := 0.0
var sway_t := 0.0
var sway := Vector2.ZERO
var breath := BREATH
var breath_out := 0.0
var holding_breath := false
var drag_body: Soldier = null
## Set by the game while a hack is being held.
var hacking := false
## Working the security tablet: no moving, no looking around.
var in_tablet := false
var drag_snd := 0.0
## The ladder being climbed, if any.
var ladder: Ladder = null
var _climb_snd := 0.0
var _duct_snd := 0.0
## Wounds don't heal by themselves: open wounds bleed until bandaged, a leg hit stops you running
## until a medkit splints it.
var bleed := 0.0
var leg_wound := false
var bandages := 2
var bandage_t := -1.0
var vault_t := -1.0
var vault_from := Vector3.ZERO
var vault_to := Vector3.ZERO
var vault_ok := false
var trauma := 0.0
var kick := 0.0
var heart_t := 0.0
var step_acc := 0.0
var mouse_delta := Vector2.ZERO
var low_cover_ahead := false
var _probe_t := 0.0
var _shape: CapsuleShape3D
var _arc: MeshInstance3D
var _arc_mark: MeshInstance3D
var _arc_ring: MeshInstance3D


func _ready() -> void:
	_shape = col.shape as CapsuleShape3D
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.SOLDIERS | Layers.RAILING
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	_build_arc()


func spawn(pos: Vector3, facing := PI) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = facing
	pitch = 0.0
	hp = MAX_HP
	alive = true
	crouch_toggle = false
	_set_height(H_STAND)
	supp = 0.0
	last_hit = 99.0
	recov = 0.0
	ads = 0.0
	lean_k = 0.0
	drag_body = null
	vault_t = -1.0
	breath = BREATH
	breath_out = 0.0
	trauma = 0.0
	bleed = 0.0
	leg_wound = false
	bandages = 2
	bandage_t = -1.0
	ladder = null
	weapons.equip(Settings.primary, Settings.gadgets)


# ------------------------------------------------------------------ helpers

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func view_dir() -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


## Where the barrel actually points, including scope sway.
func aim_dir() -> Vector3:
	var y := yaw + sway.x
	var p := pitch + sway.y
	var cp := cos(p)
	return Vector3(-sin(y) * cp, sin(p), -cos(y) * cp)


func eye_pos() -> Vector3:
	return global_position + Vector3.UP * eye_h + right() * lean_reach


func chest_pos() -> Vector3:
	return global_position + Vector3.UP * lerpf(1.25, 0.68, crouch_k) + right() * lean_reach * 0.35


func is_scoped() -> bool:
	return weapons.current().scoped and ads > 0.85


func speed_2d() -> float:
	return Vector2(velocity.x, velocity.z).length()


func can_fire() -> bool:
	return alive and active and not hacking and not in_tablet and not sprinting and bandage_t < 0.0 and ladder == null and drag_body == null and not weapons.aiming_throw and weapons.throw_t <= 0.0 and vault_t < 0.0


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _set_height(h: float) -> void:
	_shape.height = h
	col.position.y = h * 0.5
	crouched = h < H_STAND


func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = _shape.radius - 0.02
	s.height = H_STAND - 0.05
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (H_STAND * 0.5 + 0.03))
	q.collision_mask = Layers.WORLD
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not active or not alive:
		return
	if in_tablet:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative
	if event.is_action_pressed("crouch"):
		crouch_toggle = not crouch_toggle
		Sfx.play("cloth")
		game.hud.learn("crouch")
	elif event.is_action_pressed("reload"):
		weapons.start_reload()
	elif event.is_action_pressed("fire_mode"):
		weapons.cycle_mode()
	elif event.is_action_pressed("primary"):
		weapons.switch_to(0)
	elif event.is_action_pressed("sidearm"):
		weapons.switch_to(1)
	elif event.is_action_pressed("swap"):
		weapons.switch_to(1 - weapons.cur)
	elif event.is_action_pressed("gadget"):
		weapons.begin_throw()
	elif event.is_action_released("gadget"):
		weapons.release_throw()
	elif event.is_action_pressed("gadget_cycle"):
		weapons.cycle_gadget()
	elif event.is_action_pressed("interact"):
		if ladder:
			ladder = null
		elif game.takedown_target() == null and game.use_target == null and game.ladder_near():
			grab_ladder(game.ladder_near())
		else:
			game.interact()
	elif event.is_action_pressed("bandage"):
		start_bandage()
	elif event.is_action_pressed("jump"):
		if ladder:
			velocity = ladder.normal * 2.5
			ladder = null
		elif vault_ok:
			_start_vault()
		elif is_on_floor() and not crouched:
			velocity.y = JUMP
			Sfx.play("cloth")
	elif event.is_action_pressed("aim") and weapons.aiming_throw:
		weapons.cancel_throw()


# ------------------------------------------------------------------ simulation

func tick(dt: float) -> void:
	if not alive:
		return
	var w := weapons.current()
	var sens := Settings.sensitivity * lerpf(1.0, w.ads_fov / FOV, ads)
	yaw -= mouse_delta.x * sens
	pitch = clampf(pitch - mouse_delta.y * sens, -1.5, 1.5)
	viewmodel.sway += mouse_delta * 0.0004
	mouse_delta = Vector2.ZERO

	var f := 0.0 if in_tablet else Input.get_axis("move_back", "move_forward")
	var s := 0.0 if in_tablet else Input.get_axis("move_left", "move_right")
	var wish := forward() * f + right() * s
	if wish.length() > 1.0:
		wish = wish.normalized()
	if wish.length() > 0.1:
		game.hud.learn("move")

	# stance
	var sprint_key := Input.is_action_pressed("sprint")
	if sprint_key and f > 0.0 and crouch_toggle and ads < 0.3 and drag_body == null:
		crouch_toggle = false
	var want_crouch := crouch_toggle or Input.is_action_pressed("crouch_hold")
	if want_crouch and not crouched:
		_set_height(H_CROUCH)
	elif not want_crouch and crouched and _can_stand():
		_set_height(H_STAND)
	crouch_k = lerpf(crouch_k, 1.0 if crouched else 0.0, minf(1.0, dt * 10.0))
	sprinting = sprint_key and f > 0.0 and not crouched and ads < 0.3 and weapons.reload_t <= 0.0 and is_on_floor() and drag_body == null and not leg_wound and bandage_t < 0.0
	if sprinting:
		game.hud.learn("sprint")
	var aim_want := Input.is_action_pressed("aim") and bandage_t < 0.0 and not sprinting and weapons.switch_t <= 0.0 and not weapons.aiming_throw and weapons.throw_t <= 0.0 and drag_body == null and vault_t < 0.0
	ads = clampf(ads + (dt * (4.5 if w.scoped else 6.0) if aim_want else -dt * 7.0), 0.0, 1.0)
	if ads > 0.5:
		game.hud.learn("aim")

	# rise over low cover while aiming from a crouch
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = 0.12
		_probe_surroundings()
	var peek_want := 1.0 if crouched and ads > 0.3 and low_cover_ahead else 0.0
	peek = lerpf(peek, peek_want, minf(1.0, dt * 8.0))
	if peek > 0.5:
		game.hud.learn("peek")
	eye_h = lerpf(lerpf(EYE_STAND, EYE_CROUCH, crouch_k), EYE_PEEK, peek)

	_update_sway(dt, w)

	# lean, clipped against walls
	var lean_want := 0.0 if sprinting else Input.get_axis("lean_left", "lean_right")
	lean_k = lerpf(lean_k, lean_want, minf(1.0, dt * 9.0))
	if absf(lean_want) > 0.5:
		game.hud.learn("lean")
	var reach := lean_k * LEAN
	if absf(reach) > 0.01:
		var base := global_position + Vector3.UP * eye_h
		var hit := _ray(base, base + right() * signf(reach) * (absf(reach) + 0.15))
		if not hit.is_empty():
			reach = signf(reach) * maxf(0.0, base.distance_to(hit.position) - 0.15)
	lean_reach = reach

	if ladder:
		_climb(dt, f)
	elif vault_t >= 0.0:
		_update_vault(dt)
	else:
		_move(dt, wish, w)
	_duct_noise(dt)
	_update_drag(dt)

	var hs := speed_2d()
	if is_on_floor() and hs > 0.8:
		var prev := step_phase
		step_phase += hs * dt * 0.62
		if floori(prev) != floori(step_phase):
			Sfx.play("step", -6.0 if sprinting else (-24.0 if crouched else -13.0))
	bob = lerpf(bob, minf(1.0, hs / WALK) if is_on_floor() else 0.0, minf(1.0, dt * 8.0))
	roll = lerpf(roll, -s * 0.012 - lean_k * 0.16, minf(1.0, dt * 9.0))

	supp = maxf(0.0, supp - dt * 0.45)
	last_hit += dt
	_tick_wounds(dt)
	if not alive:
		return
	if hp < 30.0:
		heart_t -= dt
		if heart_t <= 0.0:
			Sfx.play("heart", -4.0, 0.0)
			heart_t = 0.85
	since_shot += dt
	bloom = maxf(0.0, bloom - dt * 0.08)
	if since_shot > 0.12 and recov > 0.0:
		var r := recov * minf(1.0, dt * 6.0)
		pitch -= r * 0.5
		recov -= r
	weapons.tick(dt, Input.is_action_pressed("fire") and active)
	_update_arc()


func _move(dt: float, wish: Vector3, w: WeaponData) -> void:
	var speed := WALK
	if crouched:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT
	if drag_body:
		speed = minf(speed, DRAG_SPEED)
	if hacking or bandage_t >= 0.0:
		speed *= 0.5
	if leg_wound:
		speed *= 0.7
	speed *= lerpf(1.0, 0.4 if w.scoped else 0.6, ads) * (0.6 if absf(lean_k) > 0.3 else 1.0) * (1.0 - supp * 0.25)
	var target := wish * speed
	if is_on_floor():
		var k := minf(1.0, ACCEL * dt)
		velocity.x = lerpf(velocity.x, target.x, k)
		velocity.z = lerpf(velocity.z, target.z, k)
	else:
		velocity.x += target.x * dt
		velocity.z += target.z * dt
		var hv := Vector2(velocity.x, velocity.z)
		var cap := maxf(speed, 4.5)
		if hv.length() > cap:
			hv = hv.normalized() * cap
			velocity.x = hv.x
			velocity.z = hv.y
		velocity.y -= GRAVITY * dt
	var was_air := not is_on_floor()
	var vy := velocity.y
	move_and_slide()
	if was_air and is_on_floor() and vy < -5.0:
		land = minf(0.2, -vy * 0.012)
		Sfx.play("land", -6.0)


func _update_sway(dt: float, w: WeaponData) -> void:
	sway_t += dt
	var moving := speed_2d() > 0.5
	var amp := 0.0065 if is_scoped() else ads * 0.0012
	amp *= (1.0 + supp * 2.0) * (0.65 if crouched else 1.0) * (2.0 if moving else 1.0)
	var want_hold := is_scoped() and Input.is_action_pressed("sprint") and breath_out <= 0.0 and breath > 0.0
	if want_hold and not holding_breath:
		Sfx.play("breath_in", -6.0)
		game.hud.learn("breath")
	if not want_hold and holding_breath:
		Sfx.play("breath_out", -6.0)
	holding_breath = want_hold
	if holding_breath:
		amp *= 0.1
		breath -= dt
		if breath <= 0.0:
			breath_out = 2.2
	else:
		breath = minf(BREATH, breath + dt * 0.7)
	if breath_out > 0.0:
		breath_out -= dt
		amp *= 2.2
	sway = Vector2((sin(sway_t * 0.9) * 1.3 + sin(sway_t * 2.3) * 0.3) * amp, sin(sway_t * 1.8) * 0.9 * amp)


## Looks for vaultable ledges and low cover in front of the player.
func _probe_surroundings() -> void:
	var fwd := forward()
	var feet := global_position
	vault_ok = false
	low_cover_ahead = false
	var hit := _ray(feet + Vector3.UP * 0.55, feet + Vector3.UP * 0.55 + fwd * 1.0)
	if not hit.is_empty() and is_on_floor() and drag_body == null:
		var top_probe: Vector3 = hit.position + fwd * 0.3
		top_probe.y = feet.y + 1.8
		var down := _ray(top_probe, Vector3(top_probe.x, feet.y + 0.3, top_probe.z))
		if not down.is_empty():
			var rise: float = down.position.y - feet.y
			if rise > 0.45 and rise < 1.6:
				var q := PhysicsShapeQueryParameters3D.new()
				var sp := SphereShape3D.new()
				sp.radius = 0.3
				q.shape = sp
				q.transform = Transform3D(Basis.IDENTITY, Vector3(top_probe.x, down.position.y + 0.65, top_probe.z))
				q.collision_mask = Layers.WORLD
				if get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
					vault_ok = true
					vault_to = Vector3(top_probe.x, down.position.y + 0.02, top_probe.z)
	if crouched:
		var d := view_dir()
		d.y = 0.0
		d = d.normalized()
		var low := global_position + Vector3.UP * EYE_CROUCH
		var high := global_position + Vector3.UP * EYE_PEEK
		low_cover_ahead = not _ray(low, low + d * 1.3).is_empty() and _ray(high, high + d * 1.3).is_empty()


# ------------------------------------------------------------------ ladders and ducts

func grab_ladder(l: Ladder) -> void:
	ladder = l
	velocity = Vector3.ZERO
	drag_body = null
	crouch_toggle = false
	weapons.reload_t = 0.0
	weapons.tube_loading = false
	var y := global_position.y
	if y > l.top_y() - 0.6:
		y = l.top_y() - 1.0
	global_position = l.climb_point(y)
	Sfx.play("cloth")
	game.hud.learn("ladder")


## Forward climbs, back descends; off the top you step onto the platform, off the bottom you let go.
func _climb(dt: float, f: float) -> void:
	velocity = Vector3.ZERO
	var l := ladder
	var y := global_position.y + f * Ladder.CLIMB_SPEED * dt
	if y >= l.top_y() - 0.05 and f > 0.0:
		global_position = l.top_exit
		ladder = null
		Sfx.play("step", -10.0)
		return
	if y <= l.global_position.y and f < 0.0:
		global_position = l.bottom_exit()
		global_position.y = l.global_position.y
		ladder = null
		return
	global_position = l.climb_point(y)
	if absf(f) > 0.1:
		_climb_snd -= dt
		if _climb_snd <= 0.0:
			_climb_snd = 0.32
			Sfx.play("impact_metal", -18.0, 0.15)
			step_phase += 0.5


## Crawling through sheet-metal ducts carries: guards close by hear something.
func _duct_noise(dt: float) -> void:
	if not game.facility.in_duct(global_position) or speed_2d() < 0.4:
		return
	_duct_snd -= dt
	if _duct_snd > 0.0:
		return
	_duct_snd = 0.45
	Sfx.play_at("impact_metal", global_position + Vector3.UP * 0.5, -14.0, false, 0.3)
	for s in game.soldiers:
		if s.alive and s.state == Soldier.State.CALM and s.global_position.distance_to(global_position) < 7.0:
			s.make_suspicious(global_position, 0.35, "noise", 0.6)


func _start_vault() -> void:
	vault_from = global_position
	vault_t = 0.0
	velocity = Vector3.ZERO
	Sfx.play("cloth")
	game.hud.learn("vault")


func _update_vault(dt: float) -> void:
	vault_t += dt / 0.38
	var t := minf(vault_t, 1.0)
	var up := sin(minf(t * 1.6, 1.0) * PI * 0.5)
	var fwd := smoothstep(0.25, 1.0, t)
	var p := vault_from.lerp(vault_to, fwd)
	p.y = lerpf(vault_from.y, vault_to.y + 0.15, up) - (0.15 * fwd)
	global_position = p
	if t >= 1.0:
		vault_t = -1.0
		velocity = forward() * 2.0


# ------------------------------------------------------------------ weapons

func fire_weapon(w: WeaponData) -> void:
	game.stats.shots += 1
	Sfx.play(w.sound, 0.0 if not w.suppressed else -4.0)
	var move_k := clampf(speed_2d() / WALK, 0.0, 1.5)
	var cone := lerpf(w.hip_spread, w.ads_spread, ads) + move_k * lerpf(0.03, 0.01, ads) + bloom * (1.0 - ads * 0.6)
	if not is_on_floor():
		cone += 0.06
	if w.scoped and not is_scoped():
		cone += 0.02
	cone *= 0.75 if crouched else 1.0
	cone += supp * 0.012
	bloom = minf(0.03, bloom + 0.004)
	var o := eye_pos()
	if w.pellets > 1:
		var center := Ballistics.spread(aim_dir(), cone * 0.3)
		for i in w.pellets:
			game.player_shot(o, Ballistics.spread(center, lerpf(w.hip_spread, w.ads_spread, ads)), w, i == 0)
	else:
		game.player_shot(o, Ballistics.spread(aim_dir(), cone), w)
	var k := w.kick * lerpf(1.0, 0.65, ads) * (0.85 if crouched else 1.0)
	pitch += k
	recov += k
	yaw += randf_range(-1.0, 1.0) * w.kick_yaw
	since_shot = 0.0
	viewmodel.fire_kick(2.5 if w.id == "dmr" else (1.8 if w.pellets > 1 else 1.0), w.suppressed, w)
	kick += 0.012 if w.id == "dmr" else 0.004
	if not w.suppressed:
		game.fx.flash_light(o + view_dir() * 0.8, Color("ffb060"), 3.0, 0.05, 9.0)
	game.hear_gunshot(global_position, w.loudness, w.suppressed)


func throw_params() -> Array:
	var o := eye_pos()
	var d := view_dir()
	var v := d * 15.0 + Vector3.UP * 3.5 + Vector3(velocity.x, 0.0, velocity.z)
	return [o + d * 0.4, v]


func _build_arc() -> void:
	_arc = MeshInstance3D.new()
	_arc.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.55)
	_arc.material_override = m
	_arc.top_level = true
	_arc.visible = false
	add_child(_arc)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 0.72, 0.29, 0.9)
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arc_mark = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.26
	_arc_mark.mesh = tm
	_arc_mark.material_override = ring_mat
	_arc_mark.top_level = true
	_arc_mark.visible = false
	add_child(_arc_mark)
	_arc_ring = MeshInstance3D.new()
	var tr := TorusMesh.new()
	tr.inner_radius = 0.99
	tr.outer_radius = 1.0
	tr.rings = 64
	_arc_ring.mesh = tr
	var rm := ring_mat.duplicate() as StandardMaterial3D
	rm.albedo_color = Color(1.0, 0.72, 0.29, 0.35)
	_arc_ring.material_override = rm
	_arc_ring.top_level = true
	_arc_ring.visible = false
	add_child(_arc_ring)


## Simulates the throw with the same bounce rules the gadget body uses, closely enough to plan with.
func _update_arc() -> void:
	var show := weapons.aiming_throw and alive
	_arc.visible = show
	_arc_mark.visible = show
	var info := weapons.gadget_info()
	_arc_ring.visible = show and not info.is_empty() and float(Gadget.INFO[info.type].radius) > 0.0
	if not show:
		return
	var tp := throw_params()
	var p: Vector3 = tp[0]
	var v: Vector3 = tp[1]
	var im := _arc.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_add_vertex(p)
	var n := Vector3.UP
	var dt := 1.0 / 60.0
	for i in 180:
		v.y -= GRAVITY * dt
		var next := p + v * dt
		var hit := _ray(p, next + v.normalized() * 0.06)
		if not hit.is_empty():
			n = hit.normal
			p = hit.position + n * 0.06
			v = v.bounce(n) * 0.38
			if n.y > 0.7 and v.length() < 1.3:
				im.surface_add_vertex(p)
				break
		else:
			p = next
		if i % 2 == 0:
			im.surface_add_vertex(p)
	im.surface_end()
	var side := Vector3.RIGHT if absf(n.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(n).normalized()
	_arc_mark.global_transform = Transform3D(Basis(x, n, x.cross(n)), p + n * 0.02)
	var r := float(Gadget.INFO[info.type].radius)
	_arc_ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), Vector3(p.x, p.y + 0.03, p.z))


# ------------------------------------------------------------------ bodies

func start_drag(s: Soldier) -> void:
	drag_body = s
	weapons.reload_t = 0.0
	weapons.tube_loading = false
	Sfx.play("cloth")
	game.hud.learn("drag")


func _update_drag(dt: float) -> void:
	if drag_body == null:
		return
	if not Input.is_action_pressed("interact") or not alive:
		drag_body = null
		return
	var target := global_position + forward() * 1.1
	var e := drag_body
	var to := target - e.global_position
	to.y = 0.0
	var d := to.length()
	if d > 2.6:
		drag_body = null
		return
	if d > 0.05:
		var stepv := to / d * minf(d, 3.0 * dt)
		var np := e.global_position + stepv
		var down := _ray(np + Vector3.UP * 0.6, np + Vector3.DOWN * 0.6)
		var clear := _ray(e.global_position + Vector3.UP * 0.3, np + Vector3.UP * 0.3).is_empty()
		if not down.is_empty() and clear and absf(down.position.y - e.global_position.y) < 0.6:
			e.global_position = Vector3(np.x, down.position.y, np.z)
	e.model.rotation.y = atan2(global_position.x - e.global_position.x, global_position.z - e.global_position.z)
	drag_snd -= dt
	if speed_2d() > 0.3 and drag_snd <= 0.0:
		Sfx.play("drag", -8.0)
		drag_snd = 0.6


# ------------------------------------------------------------------ damage

## Hit zones for incoming fire: returns {t, zone} or {}.
func ray_hit(o: Vector3, d: Vector3) -> Dictionary:
	var head_p := eye_pos() + Vector3.UP * 0.04
	var zones := [
		["head", head_p, 0.15],
		["body", chest_pos(), lerpf(0.27, 0.3, crouch_k)],
		["body", global_position + Vector3.UP * lerpf(0.95, 0.45, crouch_k), 0.24],
		["legs", global_position + Vector3.UP * lerpf(0.5, 0.25, crouch_k), 0.2],
	]
	var best := {}
	for z: Array in zones:
		var t := Ballistics.ray_sphere(o, d, z[1], z[2])
		if t >= 0.0 and (best.is_empty() or t < float(best.t)):
			best = {"t": t, "zone": z[0]}
	return best


func take_damage(amount: float, from: Vector3, through_wall := false, zone := "body") -> void:
	if not alive or game.god_mode:
		return
	hp -= amount
	last_hit = 0.0
	game.stats.damage_taken += amount
	trauma = minf(1.0, trauma + clampf(amount / 30.0, 0.1, 0.4))
	supp = minf(1.0, supp + 0.25)
	bleed = minf(2.0, bleed + amount * 0.008)
	if zone == "legs" and not leg_wound:
		leg_wound = true
		game.hud.hint_event("leg_wound")
	game.hud.on_damage(amount, from)
	if through_wall:
		game.hud.hint_event("penetrated")
	Sfx.play("hurt", -3.0)
	if hp <= 0.0:
		_die()


func _die() -> void:
	hp = 0.0
	alive = false
	drag_body = null
	bandage_t = -1.0
	weapons.aiming_throw = false
	game.on_player_died()


func _tick_wounds(dt: float) -> void:
	if bandage_t >= 0.0:
		bandage_t += dt
		if bandage_t >= BANDAGE_TIME:
			bandage_t = -1.0
			bleed = 0.0
			Sfx.play("cloth")
			game.hud.learn("bleeding")
	if bleed > 0.0 and not game.god_mode:
		hp -= bleed * dt
		bleed = maxf(0.0, bleed - dt * 0.004)
		game.hud.hint_event("bleeding")
		if hp <= 0.0:
			_die()


func start_bandage() -> void:
	if bandage_t >= 0.0 or bleed <= 0.0 or not alive:
		return
	if bandages <= 0:
		game.hud.toast("NO BANDAGES  ·  FIND A MEDKIT")
		return
	bandages -= 1
	bandage_t = 0.0
	weapons.reload_t = 0.0
	weapons.tube_loading = false
	drag_body = null
	Sfx.play("cloth")


## Medkit: closes wounds, splints a leg, restores health.
func treat() -> void:
	hp = minf(MAX_HP, hp + 50.0)
	bleed = 0.0
	leg_wound = false
	bandages = maxi(bandages, 2)


func needs_treatment() -> bool:
	return hp < MAX_HP or bleed > 0.0 or leg_wound


func near_miss(amount: float, point: Vector3) -> void:
	supp = minf(1.0, supp + amount)
	Sfx.play_at("whizz", point, 0.0, false)


# ------------------------------------------------------------------ camera

func update_camera(dt: float) -> void:
	step_acc *= exp(-dt * 12.0)
	land = maxf(0.0, land - dt)
	trauma = maxf(0.0, trauma - dt * 1.4)
	kick *= exp(-dt * 14.0)
	var sh := trauma * trauma
	var t := Time.get_ticks_msec() / 1000.0
	var b := absf(sin(step_phase * PI)) * 0.035 * bob * (1.0 - ads * 0.8)
	rotation.y = yaw
	head.position = Vector3(lean_reach, eye_h + b - land, 0.0)
	if not alive:
		head.position = Vector3(0.0, 0.3, 0.0)
	head.rotation = Vector3(pitch + sway.y + kick + sin(t * 31.0) * sh * 0.04, sway.x + sin(t * 27.0 + 1.0) * sh * 0.04, 0.0)
	camera.rotation.z = roll + sin(t * 21.0 + 2.0) * sh * 0.03 + (0.0 if alive else 1.2)
	var w := weapons.current()
	var fov := FOV
	if w.scoped:
		fov = w.ads_fov if ads > 0.85 else lerpf(FOV, 50.0, ads / 0.85)
	else:
		fov = lerpf(FOV, w.ads_fov, ads) + (4.0 if sprinting else 0.0)
	camera.fov = fov if (w.scoped and ads > 0.85) else lerpf(camera.fov, fov, minf(1.0, dt * 14.0))
	viewmodel.animate(dt, self, w, weapons)
	Sfx.set_muffle(supp * 0.35 + minf(0.85, game.hud.flash * 0.7))
