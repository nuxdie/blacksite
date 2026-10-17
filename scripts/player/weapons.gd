class_name Weapons
extends Node
## The player's loadout: two firearms with individually tracked magazines, and two kinds of
## throwable equipment.

const SWITCH_TIME := 0.45

var slots: Array[WeaponData] = []
var cur := 0
var mag: Array[int] = [0, 0]
var spare: Array = [[], []]
var mode: Array[int] = [0, 0]
var cd := 0.0
var switch_t := 0.0
var pending := -1
var reload_t := 0.0
var reload_dur := 1.0
var reload_stage := 0
var trigger_held := false
var gadgets: Array[Dictionary] = []
var gsel := 0
var aiming_throw := false
var throw_t := 0.0
var auto_bursts := 0
var _burst_len := 0

@onready var player: Player = get_parent()


func equip(primary: String, gadget_types: Array[String]) -> void:
	slots = [load("res://resources/weapons/%s.tres" % primary) as WeaponData, load("res://resources/weapons/pistol.tres") as WeaponData]
	for i in 2:
		mag[i] = slots[i].mag_size
		var s: Array[int] = []
		for _k in slots[i].spare_mags:
			s.append(slots[i].mag_size)
		spare[i] = s
		mode[i] = 0
	gadgets.clear()
	for t in gadget_types:
		gadgets.append({"type": t, "n": 2})
	cur = 0
	cd = 0.3
	switch_t = 0.0
	pending = -1
	reload_t = 0.0
	gsel = 0
	aiming_throw = false
	throw_t = 0.0
	player.viewmodel.show_weapon(current().id)


func current() -> WeaponData:
	return slots[cur]


func fire_mode() -> String:
	return current().modes[mode[cur]]


func spares() -> Array:
	return spare[cur]


func switch_to(i: int) -> void:
	if (i == cur and pending < 0) or player.drag_body or i < 0 or i >= slots.size():
		return
	pending = i
	switch_t = SWITCH_TIME
	reload_t = 0.0
	Sfx.play("cloth")


func cycle_mode() -> void:
	var w := current()
	if w.modes.size() > 1:
		mode[cur] = (mode[cur] + 1) % w.modes.size()
		Sfx.play("dry")
		player.game.hud.learn("fire_mode")


## Swap in the fullest spare magazine; the partial one goes back in the pouch.
func start_reload() -> void:
	var w := current()
	var sp: Array = spare[cur]
	if reload_t > 0.0 or switch_t > 0.0 or aiming_throw or player.drag_body or mag[cur] >= w.mag_size:
		return
	if sp.is_empty():
		player.game.hud.toast("NO MAGAZINES LEFT")
		return
	if int(sp.max()) <= mag[cur]:
		player.game.hud.toast("NO FULLER MAGAZINE")
		return
	reload_dur = w.reload_empty_time if mag[cur] == 0 else w.reload_time
	reload_t = reload_dur
	reload_stage = 0
	Sfx.play("mag_out")


func _finish_reload() -> void:
	var sp: Array = spare[cur]
	var bi := 0
	for k in sp.size():
		if sp[k] > sp[bi]:
			bi = k
	var next: int = sp[bi]
	sp.remove_at(bi)
	if mag[cur] > 0:
		sp.append(mag[cur])
	mag[cur] = next
	sp.sort()
	sp.reverse()


func add_mag(slot: int, rounds: int) -> bool:
	var w := slots[slot]
	var sp: Array = spare[slot]
	if sp.size() < w.spare_mags + 2:
		sp.append(mini(rounds, w.mag_size))
	elif int(sp.min()) < w.mag_size:
		sp[sp.find(sp.min())] = w.mag_size
	else:
		return false
	sp.sort()
	sp.reverse()
	return true


func resupply() -> void:
	for i in slots.size():
		var s: Array[int] = []
		for _k in maxi(spare[i].size(), slots[i].spare_mags):
			s.append(slots[i].mag_size)
		spare[i] = s
	for g in gadgets:
		g.n = mini(3, int(g.n) + 1)


func gadget_info() -> Dictionary:
	return gadgets[gsel] if gsel < gadgets.size() else {}


func cycle_gadget() -> void:
	if gadgets.size() > 1 and not aiming_throw:
		gsel = (gsel + 1) % gadgets.size()
		Sfx.play("cloth")


func begin_throw() -> void:
	var g := gadget_info()
	if g.is_empty() or aiming_throw or throw_t > 0.0 or not player.alive or player.drag_body:
		return
	if int(g.n) <= 0:
		player.game.hud.toast("NO %s LEFT" % Gadget.INFO[g.type].name)
		return
	aiming_throw = true
	reload_t = 0.0
	player.viewmodel.set_gadget_color(Gadget.INFO[g.type].color)
	Sfx.play("pin")


func cancel_throw() -> void:
	aiming_throw = false


func release_throw() -> void:
	if not aiming_throw:
		return
	aiming_throw = false
	throw_t = 0.45
	var g := gadget_info()
	g.n = int(g.n) - 1
	var tp := player.throw_params()
	player.game.spawn_gadget(g.type, tp[0], tp[1], true)
	Sfx.play("throw")
	player.game.hud.learn("gadget")
	if int(g.n) <= 0:
		for k in gadgets.size():
			if int(gadgets[k].n) > 0:
				gsel = k
				break


func tick(dt: float, firing: bool) -> void:
	cd -= dt
	throw_t = maxf(0.0, throw_t - dt)
	if switch_t > 0.0:
		switch_t -= dt
		if pending >= 0 and switch_t <= 0.22:
			cur = pending
			pending = -1
			player.viewmodel.show_weapon(current().id)
	if reload_t > 0.0:
		reload_t -= dt
		var k := 1.0 - reload_t / reload_dur
		if reload_stage == 0 and k > 0.55:
			reload_stage = 1
			Sfx.play("mag_in")
		if reload_stage == 1 and k > 0.8 and reload_dur > current().reload_time:
			reload_stage = 2
			Sfx.play("bolt")
		if reload_t <= 0.0:
			_finish_reload()
	var w := current()
	if not firing:
		if _burst_len >= 8 and fire_mode() == "AUTO":
			auto_bursts += 1
		_burst_len = 0
		trigger_held = false
		return
	if cd > 0.0 or switch_t > 0.0 or reload_t > 0.0 or not player.can_fire():
		return
	if fire_mode() == "SEMI" and trigger_held:
		return
	trigger_held = true
	if mag[cur] <= 0:
		Sfx.play("dry")
		cd = 0.3
		if (spare[cur] as Array).any(func(m: int) -> bool: return m > 0):
			start_reload()
		return
	mag[cur] -= 1
	cd = 60.0 / w.rpm
	_burst_len += 1
	player.fire_weapon(w)
