class_name Hints
extends RefCounted
## Teaches the controls in context, once. A hint appears when its situation first comes up and
## retires for good when the player performs the action (or, for advice, once it has been read).

const SHOW_TIME := 11.0
const INFO_TIME := 7.0

var game: Game
var current: Dictionary = {}
var shown_t := 0.0
var alpha := 0.0
var _cooldown: Dictionary = {}
var _events: Dictionary = {}

# keys: list of actions shown as key caps; info hints need no action and retire when read.
var defs: Array[Dictionary] = [
	{"id": "move", "keys": ["move_forward", "move_left", "move_back", "move_right"], "text": "Move", "trigger": "start"},
	{"id": "crouch", "keys": ["crouch"], "text": "Crouch — slower, quieter, harder to spot", "trigger": "noticed_or_late"},
	{"id": "awareness", "keys": [], "text": "Arcs around your sights show who is noticing you", "trigger": "noticed", "info": true},
	{"id": "aim", "keys": ["aim"], "text": "Aim down sights", "trigger": "enemy_visible"},
	{"id": "tracked", "keys": [], "text": "Guards you've seen stay tracked: a hollow marker shows where you last saw them", "trigger": "tracked_hidden", "info": true},
	{"id": "lights", "keys": [], "text": "You're lit up. Lamps can be shot out", "trigger": "lit_near_guards", "info": true},
	{"id": "cameras", "keys": [], "text": "Cameras are wired to a security network — get to an access point to deal with them", "trigger": "camera_in_view", "info": true},
	{"id": "network", "keys": [], "text": "Junction boxes, the server cabinet and the booth terminal all reach the camera network", "trigger": "access_near", "info": true},
	{"id": "badge", "keys": [], "text": "Badges open doors at their access level. A security badge also logs into the cameras without a trace", "trigger": "badge", "info": true},
	{"id": "relay", "keys": [], "text": "Their radio runs through the relay on the office roof. Sabotage it and alarms go nowhere — until someone fixes it", "trigger": "camera_alarm", "info": true},
	{"id": "lean", "keys": ["lean_left", "lean_right"], "text": "Lean out from cover", "trigger": "combat"},
	{"id": "sprint", "keys": ["sprint"], "text": "Sprint — guards hear it", "trigger": "late_quiet"},
	{"id": "gadget", "keys": ["gadget"], "text": "Hold to aim equipment, release to throw", "trigger": "gadget_time"},
	{"id": "gadget_cycle", "keys": ["gadget_cycle"], "text": "Switch equipment", "trigger": "after_gadget"},
	{"id": "drag", "keys": ["interact"], "text": "Hold near a body to drag it out of sight", "trigger": "kill"},
	{"id": "calibers", "keys": [], "text": "Guards drop their own weapons. Rounds only fit weapons of the same caliber", "trigger": "scavenge_seen", "info": true},
	{"id": "fire_mode", "keys": ["fire_mode"], "text": "Semi-auto for long-range control", "trigger": "long_bursts"},
	{"id": "bleeding", "keys": ["bandage"], "text": "You're bleeding — wounds don't close on their own", "trigger": "bleeding"},
	{"id": "leg_wound", "keys": [], "text": "Leg wound: you can't run until a medkit splints it", "trigger": "leg_wound", "info": true},
	{"id": "checkin", "keys": [], "text": "Guards check in by radio. A dead guard can't answer — HQ will send someone to their post", "trigger": "checkin", "info": true},
	{"id": "caution", "keys": [], "text": "The site is on caution now: sharper eyes, flashlights on. It won't calm down tonight", "trigger": "caution", "info": true},
	{"id": "radio_call", "keys": [], "text": "A guard is calling you in. Drop them before the call goes through", "trigger": "radio_call", "info": true},
	{"id": "alarm", "keys": [], "text": "Alarm raised — a reaction force is on its way. Kill a guard before they radio it in and it never happens", "trigger": "alarm", "info": true},
	{"id": "quicksave", "keys": ["quicksave"], "text": "Quicksave while it's quiet", "trigger": "quiet_spot"},
	{"id": "penetrated", "keys": [], "text": "Thin walls don't stop rifle rounds — get behind concrete or steel", "trigger": "penetrated", "info": true},
]


func reset() -> void:
	current = {}
	alpha = 0.0
	_cooldown.clear()
	_events.clear()


func event(name: String) -> void:
	_events[name] = true


func learn(id: String) -> void:
	Settings.learn(id)
	if current.get("id", "") == id:
		_retire()


func _retire() -> void:
	if current.get("info", false):
		Settings.learn(current.id)
	else:
		_cooldown[current.id] = game.time + 45.0
	current = {}


func update(dt: float) -> void:
	if not current.is_empty():
		shown_t += dt
		var limit := INFO_TIME if current.get("info", false) else SHOW_TIME
		if Settings.is_learned(current.id) or shown_t > limit:
			_retire()
	alpha = move_toward(alpha, 1.0 if not current.is_empty() and shown_t < (INFO_TIME if current.get("info", false) else SHOW_TIME) - 0.4 else 0.0, dt * 3.0)
	if not current.is_empty():
		return
	for d in defs:
		if Settings.is_learned(d.id) or game.time < float(_cooldown.get(d.id, 0.0)):
			continue
		if _condition(d.trigger):
			current = d
			shown_t = 0.0
			Sfx.play("hint", -10.0, 0.0)
			return


func _condition(trigger: String) -> bool:
	var p := game.player
	match trigger:
		"start":
			return game.time > 1.0
		"noticed":
			return _any(func(s: Soldier) -> bool: return s.state != Soldier.State.COMBAT and s.aware > 0.05)
		"noticed_or_late":
			return not p.crouched and (game.time > 14.0 or _any(func(s: Soldier) -> bool: return s.aware > 0.05))
		"enemy_visible":
			return _any(func(s: Soldier) -> bool: return _in_view(s, 45.0))
		"calm_enemy_visible":
			return _any(func(s: Soldier) -> bool: return s.state != Soldier.State.COMBAT and not s.tagged and _in_view(s, 60.0))
		"lit_near_guards":
			return game.player_light > 0.7 and _any(func(s: Soldier) -> bool: return s.state != Soldier.State.COMBAT and s.global_position.distance_to(p.global_position) < 30.0)
		"combat":
			return game.detected and _any(func(s: Soldier) -> bool: return s.state == Soldier.State.COMBAT and s.sees)
		"late_quiet":
			return game.time > 25.0 and not game.detected
		"gadget_time":
			return game.time > 40.0 or game.detected
		"after_gadget":
			return Settings.is_learned("gadget") and p.weapons.gadgets.size() > 1
		"kill":
			return _events.has("kill") and not game.detected
		"long_bursts":
			return p.weapons.auto_bursts >= 3 and p.weapons.current().modes.size() > 1
		"tracked_hidden":
			return game.soldiers.any(func(s: Soldier) -> bool: return s.alive and s.tagged and game.time - s.tag_seen_t > 1.5 and game.time - s.tag_seen_t < 10.0)
		"quiet_spot":
			return game.time > 35.0 and not game.soldiers.any(func(s: Soldier) -> bool: return s.alive and s.state != Soldier.State.CALM)
		"checkin", "caution":
			return _events.has(trigger)
		"alarm":
			return game.hq.level == Command.Level.ALARM
		"radio_call":
			return game.soldiers.any(func(s: Soldier) -> bool: return s.alive and s.radio_t > 0.0)
		"bleeding":
			return _events.has("bleeding") and p.bleed > 0.0 and p.bandage_t < 0.0
		"leg_wound":
			return _events.has("leg_wound")
		"scavenge_seen":
			return _events.has("kill") and game.player.alive
		"camera_in_view":
			for dv in game.facility.devices:
				if dv.camera_live() and dv.global_position.distance_to(p.global_position) < 26.0 and (dv.global_position - p.eye_pos()).normalized().dot(p.view_dir()) > 0.8:
					return true
			return false
		"access_near":
			return game.use_target != null and game.use_target.kind == Device.Kind.ACCESS
		"badge":
			return _events.has("badge")
		"camera_alarm":
			return _events.has("camera_alarm") and not game.comms_down
		"penetrated":
			return _events.has("penetrated")
	return false


func _any(f: Callable) -> bool:
	for s in game.soldiers:
		if s.alive and f.call(s):
			return true
	return false


func _in_view(s: Soldier, max_d: float) -> bool:
	var e := game.player.eye_pos()
	var to := s.head_pos() - e
	if to.length() > max_d or to.normalized().dot(game.player.view_dir()) < 0.85:
		return false
	return game.los(e, s.head_pos())
