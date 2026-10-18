class_name SaveGame
extends RefCounted
## Quicksave and quickload: a snapshot of the whole night in one file.
## Restoring rebuilds a fresh mission and then puts every guard, body, device, lamp, pickup and
## the player back the way they were. Equipment in flight is not saved.

const PATH := "user://quicksave.dat"


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func save(game: Game) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(capture(game))
	return true


static func load_into(game: Game) -> bool:
	if not exists():
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = f.get_var()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	restore(game, d)
	return true


static func capture(game: Game) -> Dictionary:
	var p := game.player
	var w := p.weapons
	var soldiers := []
	for s in game.soldiers:
		soldiers.append({
			"alive": s.alive, "pos": s.global_position, "yaw": s.yaw, "hp": s.hp, "state": s.state, "aware": s.aware,
			"patrol_i": s.patrol_i, "corpse_found": s.corpse_found, "accounted": s.accounted, "tagged": s.tagged,
			"tag_seen": s.tag_seen, "mag": s.mag, "limp": s.limp, "fall_side": s.fall_side, "badge": s.badge.duplicate(),
			"squad": s.squad.id, "type": s.profile.id,
		})
	var pickups := []
	for pk in game.facility.pickups:
		pickups.append({
			"kind": pk.kind, "pos": pk.global_position, "amount": pk.amount, "taken": pk.taken, "permanent": pk.permanent,
			"caliber": pk.caliber, "weapon": pk.weapon.id if pk.weapon else "", "mag": pk.mag_rounds, "spares": pk.spares, "access": pk.access,
		})
	var repairs := []
	for r in game._repairs:
		repairs.append({"device": game.facility.devices.find(r.device), "t": r.t})
	return {
		"version": 1,
		"time": game.time, "mission": game.mission, "detected": game.detected, "comms_down": game.comms_down,
		"access": game.access.duplicate(), "doors": game.facility.doors.map(func(dr: Door) -> Array: return [dr.unlocked, dr.powered]), "trace": game.trace, "reinforce_t": game.reinforce_t, "stats": game.stats.duplicate(),
		"repairs": repairs,
		"hq": {"level": game.hq.level, "qrf": game.hq.qrf_called, "stats": game.hq.stats.duplicate(), "check_t": game.hq._check_t, "last_contact": game.hq.last_contact},
		"player": {
			"pos": p.global_position, "yaw": p.yaw, "pitch": p.pitch, "hp": p.hp, "bleed": p.bleed, "leg": p.leg_wound,
			"bandages": p.bandages, "crouch": p.crouch_toggle,
			"slots": w.slots.map(func(x: WeaponData) -> String: return x.id), "mag": w.mag.duplicate(), "spare": w.spare.duplicate(true),
			"mode": w.mode.duplicate(), "cur": w.cur, "gadgets": w.gadgets.duplicate(true), "gsel": w.gsel,
		},
		"soldiers": soldiers,
		"devices": game.facility.devices.map(func(dv: Device) -> Dictionary: return dv.save_state()),
		"lamps": game.facility.lamps.map(func(l: Lamp) -> Array: return [l.dead, l.powered]),
		"drones": game.facility.drones.map(func(dr: Drone) -> Dictionary: return {"pos": dr.position, "destroyed": dr.destroyed, "down": dr.down_t, "hp": dr.hp, "mode": dr.mode, "aware": dr.aware, "i": dr._i}),
		"pickups": pickups,
	}


static func restore(game: Game, d: Dictionary) -> void:
	game.start_mission()
	game.time = d.time
	game.mission = d.mission
	game.detected = d.detected
	game.comms_down = d.comms_down
	game.access = d.access
	var doors: Array = d.doors
	for i in mini(doors.size(), game.facility.doors.size()):
		game.facility.doors[i].unlocked = doors[i][0]
		game.facility.doors[i].powered = doors[i][1]
	game.trace = d.trace
	game.reinforce_t = d.reinforce_t
	game.stats = d.stats
	var hq: Dictionary = d.hq
	game.hq.level = hq.level
	game.hq.qrf_called = hq.qrf
	game.hq.stats = hq.stats
	game.hq._check_t = hq.check_t
	game.hq.last_contact = hq.last_contact
	game.set_beacon(game.mission == "extract")
	# devices and lamps
	var devs: Array = d.devices
	for i in mini(devs.size(), game.facility.devices.size()):
		game.facility.devices[i].load_state(devs[i])
	var lamps: Array = d.lamps
	for i in mini(lamps.size(), game.facility.lamps.size()):
		var l := game.facility.lamps[i]
		if lamps[i][0]:
			l.dead = true
			l.light.visible = false
			l.fixture_mat.emission_energy_multiplier = 0.0
		if not lamps[i][1]:
			l.power_off()
	var drones: Array = d.get("drones", [])
	for i in mini(drones.size(), game.facility.drones.size()):
		var dr := game.facility.drones[i]
		var e: Dictionary = drones[i]
		dr.position = e.pos
		dr.destroyed = e.destroyed
		dr.down_t = e.down
		dr.hp = e.hp
		dr.mode = e.mode
		dr.aware = e.aware
		dr._i = e.i
		if dr.destroyed:
			dr._cone.visible = false
	for r: Dictionary in d.repairs:
		if int(r.device) >= 0:
			game._repairs.append({"device": game.facility.devices[int(r.device)], "t": r.t})
	# pickups: permanent ones keep their place, dropped ones are recreated
	var perm := game.facility.pickups.filter(func(pk: Pickup) -> bool: return pk.permanent)
	var pi := 0
	for e: Dictionary in d.pickups:
		if e.permanent:
			if pi < perm.size():
				var pk: Pickup = perm[pi]
				pk.taken = e.taken
				pk.visible = not e.taken
			pi += 1
			continue
		if e.taken:
			continue
		var np: Pickup
		match int(e.kind):
			Pickup.Kind.WEAPON:
				np = Pickup.dropped_weapon(e.pos, load("res://resources/weapons/%s.tres" % e.weapon), e.mag, e.spares)
			Pickup.Kind.ROUNDS:
				np = Pickup.rounds(e.pos, e.caliber, e.amount)
			Pickup.Kind.BADGE:
				np = Pickup.badge(e.pos, e.access)
			_:
				np = Pickup.create(e.kind, e.pos, e.amount, false)
		game.facility.place(np)
	# guards: the roster is spawned fresh; reinforcements that had arrived are spawned again
	var saved: Array = d.soldiers
	var extra := 0
	while game.soldiers.size() < saved.size() and extra < Game.REINFORCEMENTS.size():
		game.spawn_soldier(Game.REINFORCEMENTS[extra])
		extra += 1
	for i in mini(saved.size(), game.soldiers.size()):
		game.soldiers[i].load_state(saved[i])
	# the player
	var ps: Dictionary = d.player
	var p := game.player
	var w := p.weapons
	p.global_position = ps.pos
	p.yaw = ps.yaw
	p.pitch = ps.pitch
	p.hp = ps.hp
	p.bleed = ps.bleed
	p.leg_wound = ps.leg
	p.bandages = ps.bandages
	p.crouch_toggle = ps.crouch
	var slots: Array[WeaponData] = []
	for id: String in ps.slots:
		slots.append(load("res://resources/weapons/%s.tres" % id))
	w.slots = slots
	for i in 2:
		w.mag[i] = ps.mag[i]
		w.mode[i] = ps.mode[i]
		var sp: Array[int] = []
		for m in ps.spare[i]:
			sp.append(int(m))
		w.spare[i] = sp
	w.cur = ps.cur
	w.gadgets.clear()
	for g: Dictionary in ps.gadgets:
		w.gadgets.append(g)
	w.gsel = ps.gsel
	p.viewmodel.show_weapon(w.current().id)
