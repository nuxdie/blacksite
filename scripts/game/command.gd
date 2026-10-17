class_name Command
extends RefCounted
## Facility security command (HQ) on the guard radio net.
##
## Tracks how alert the whole site is and makes it stick. Unexplained events (dark zones, dead
## cameras, a guard who doesn't answer a radio check) put the site on CAUTION for the rest of the
## night. A confirmed intruder that gets radioed in raises the ALARM: siren, guards sent to the
## contact, and a reaction force on its way. Everything here depends on the radio: kill the guard
## before they get the call out, or take down the relay, and HQ never hears about it.

enum Level { NORMAL, CAUTION, ALARM }

const CHECK_EVERY := 95.0
const QRF_DELAY := 70.0
const ALARM_HOLD := 120.0
const SPEAKERS := [Vector3(10.2, 7.0, 4.0), Vector3(-15.0, 4.2, 12.0), Vector3(-12.5, 3.0, -15.5), Vector3(-24.0, 6.5, -24.0), Vector3(30.0, 6.5, -24.0)]
const LINES := {
	"check": ["All posts, radio check.", "Radio check, all posts. Sound off."],
	"clear": ["%s, all clear.", "%s, nothing to report.", "%s here, quiet."],
	"respond": ["%s, respond.", "%s, radio check. Do you copy?"],
	"silent": ["%s isn't answering. Someone go check their post.", "Lost contact with %s. Send someone over."],
	"caution": ["All units, be advised: something's off. Stay sharp.", "All posts, heads up. Eyes open."],
	"alarm": ["All units: intruder on site! Lock it down!", "Contact reported. All units, respond!"],
	"qrf": ["Reaction force is on site.", "QRF is here. Moving in."],
	"stand": ["All units, hold positions and stay alert.", "No contact. Stay sharp, keep looking."],
}

var game: Game
var level := Level.NORMAL
var qrf_called := false
var last_contact := -999.0
var stats := {"alarms": 0, "missed_checks": 0}
var _check_t := CHECK_EVERY
var _check: Dictionary = {}
var _pending: Array[Dictionary] = []
var _siren_t := 0.0


func _init(p_game: Game) -> void:
	game = p_game


func reset() -> void:
	level = Level.NORMAL
	qrf_called = false
	last_contact = -999.0
	stats = {"alarms": 0, "missed_checks": 0}
	_check_t = CHECK_EVERY
	_check = {}
	_pending.clear()


## Perception multiplier for every guard on site.
func vigilance() -> float:
	return [1.0, 1.3, 1.5][level]


# ------------------------------------------------------------------ reports

## A guard has gone to combat. If the radio works and they live long enough to make the call,
## the whole site goes to ALARM.
func contact(s: Soldier, pos: Vector3, how: String) -> void:
	if how == "radio" or how == "shout":
		return
	if game.comms_down or level == Level.ALARM:
		return
	_pending.append({"t": game.time + randf_range(2.5, 4.0), "s": s, "pos": pos})


## Security saw it on camera: no guard needs to survive to report it.
func camera_contact(pos: Vector3) -> void:
	if not game.comms_down:
		raise_alarm(pos)


func caution(_reason: String) -> void:
	if level != Level.NORMAL:
		return
	level = Level.CAUTION
	_say_hq("caution")
	game.hud.hint_event("caution")


func raise_alarm(pos: Vector3) -> void:
	last_contact = game.time
	if level == Level.ALARM:
		return
	level = Level.ALARM
	stats.alarms += 1
	_siren_t = 0.0
	_say_hq("alarm")
	game.dispatch_to(pos, 3)
	if not qrf_called:
		qrf_called = true
		game.reinforce_t = QRF_DELAY


# ------------------------------------------------------------------ simulation

func tick(dt: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var r: Dictionary = _pending[i]
		if game.time < float(r.t):
			continue
		_pending.remove_at(i)
		var s: Soldier = r.s
		if is_instance_valid(s) and s.alive and not game.comms_down:
			raise_alarm(r.pos)
	for s in game.soldiers:
		if s.alive and s.sees and s.state == Soldier.State.COMBAT:
			last_contact = game.time
			break
	if level == Level.ALARM:
		_siren_t -= dt
		if _siren_t <= 0.0:
			_siren_t = 1.6
			var p := game.player.global_position
			var best: Vector3 = SPEAKERS[0]
			for sp: Vector3 in SPEAKERS:
				if sp.distance_to(p) < best.distance_to(p):
					best = sp
			Sfx.play_at("siren", best, 4.0)
		if game.time - last_contact > ALARM_HOLD:
			level = Level.CAUTION
			_say_hq("stand")
	_tick_checks(dt)


## Periodic radio checks. A guard who is dead (hidden or not) can't answer; HQ notices and sends
## someone to their post.
func _tick_checks(dt: float) -> void:
	if game.comms_down or level == Level.ALARM:
		_check = {}
		return
	if _check.is_empty():
		_check_t -= dt
		if _check_t > 0.0:
			return
		_check_t = CHECK_EVERY
		_check = {"t": 0.0, "stage": 0, "answered": [], "missing": []}
		_say_hq("check")
		return
	_check.t = float(_check.t) + dt
	var t := float(_check.t)
	if int(_check.stage) == 0:
		# answers come in one by one
		for s in game.soldiers:
			if s.alive and s.state != Soldier.State.COMBAT and not (_check.answered as Array).has(s) and t > 1.2 + s.call_order * 0.9:
				(_check.answered as Array).append(s)
				_say_from(s, (LINES.clear as Array).pick_random() % s.callsign)
		if t > 2.0 + game.soldiers.size() * 0.9:
			for s in game.soldiers:
				if not s.alive and not s.accounted:
					(_check.missing as Array).append(s)
			if (_check.missing as Array).is_empty():
				_check = {}
				return
			_check.stage = 1
			_check.t = 0.0
			_say_hq_text((LINES.respond as Array).pick_random() % (_check.missing[0] as Soldier).callsign)
	elif int(_check.stage) == 1 and t > 9.0:
		var who: Soldier = _check.missing[0]
		_say_hq_text((LINES.silent as Array).pick_random() % who.callsign)
		for m: Soldier in _check.missing:
			m.accounted = true
			stats.missed_checks += 1
			game.investigate_post(m.post)
		game.hud.hint_event("checkin")
		_check = {}
		caution("missed check-in")


# ------------------------------------------------------------------ radio traffic

## You only hear the net through a guard's radio: a living guard or a body nearby.
func _audible() -> bool:
	var p := game.player.global_position
	for s in game.soldiers:
		if s.global_position.distance_to(p) < 22.0:
			return true
	return false


func _say_hq(kind: String, always := false) -> void:
	_say_hq_text((LINES[kind] as Array).pick_random(), always)


func _say_hq_text(text: String, always := false) -> void:
	if always or _audible():
		Sfx.play("radio", -10.0)
		game.hud.subtitle("HQ", text)


func _say_from(s: Soldier, text: String) -> void:
	if s.global_position.distance_to(game.player.global_position) < 22.0:
		game.hud.subtitle(s.callsign.to_upper(), text)
