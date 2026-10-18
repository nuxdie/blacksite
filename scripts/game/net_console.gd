class_name NetConsole
extends RefCounted
## A live command console on the facility's security network, opened at an access point.
##
## You type commands to work the network: list nodes, watch and loop cameras, release door locks,
## cut power, jam the relay, ground drones. Every command costs trace; some need an admin session
## (a security badge). It is self-documenting: `help` and the on-screen palette list what you can
## run right now, with cost and whether it needs admin, so nothing has to be memorised.
##
## This operates only on game objects (cameras, doors, breakers, the relay, drones). It is not a
## real shell and runs nothing on the host machine.

var game: Game
var node: Device
var admin := false
var connected := false
var input := ""
var cursor := 0
var log: Array[Dictionary] = []
var history: Array[String] = []
var hist_i := 0
var watch_cam := 0
## Transient highlight of a device just acted on, for the feed/overlay.
var flash := ""

const PROMPT := "sec@node"


func open(p_node: Device, p_admin: bool) -> void:
	node = p_node
	admin = p_admin
	connected = true
	input = ""
	cursor = 0
	log.clear()
	hist_i = 0
	_out("BLACKSITE SITE SECURITY  //  node %s" % _slug(node.label), "dim")
	_out("Session: %s" % ("ADMIN" if admin else "guest (exploited)"), "amber" if not admin else "green")
	_out("Type a command. `help` lists them, Tab completes.", "dim")


func close() -> void:
	connected = false
	node = null


# ------------------------------------------------------------------ typing

func type_text(t: String) -> void:
	for c in t:
		if c.unicode_at(0) >= 32:
			input = input.substr(0, cursor) + c + input.substr(cursor)
			cursor += 1


func backspace() -> void:
	if cursor > 0:
		input = input.substr(0, cursor - 1) + input.substr(cursor)
		cursor -= 1


func delete() -> void:
	if cursor < input.length():
		input = input.substr(0, cursor) + input.substr(cursor + 1)


func move_cursor(d: int) -> void:
	cursor = clampi(cursor + d, 0, input.length())


func recall(d: int) -> void:
	if history.is_empty():
		return
	hist_i = clampi(hist_i + d, 0, history.size())
	input = "" if hist_i >= history.size() else history[hist_i]
	cursor = input.length()


func autocomplete() -> void:
	var parts := input.split(" ", false)
	if parts.size() <= 1 and not input.ends_with(" "):
		var opts := _verbs().filter(func(v: String) -> bool: return v.begins_with(input))
		if opts.size() == 1:
			input = opts[0] + " "
			cursor = input.length()
		elif opts.size() > 1:
			_out("  ".join(opts), "dim")
	else:
		var verb: String = parts[0]
		var frag: String = parts[-1] if not input.ends_with(" ") else ""
		var opts := _targets(verb).filter(func(v: String) -> bool: return v.begins_with(frag))
		if opts.size() == 1:
			var base := input.substr(0, input.length() - frag.length())
			input = base + opts[0] + " "
			cursor = input.length()
		elif opts.size() > 1:
			_out("  ".join(opts), "dim")


# ------------------------------------------------------------------ running

func submit() -> void:
	var line := input.strip_edges()
	input = ""
	cursor = 0
	if line == "":
		return
	history.append(line)
	if history.size() > 40:
		history.pop_front()
	hist_i = history.size()
	_out(PROMPT + ":~$ " + line, "input")
	_run(line)


func _run(line: String) -> void:
	var parts := line.split(" ", false)
	var verb := parts[0].to_lower()
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i].to_lower())
	match verb:
		"help", "?": _cmd_help()
		"ls", "net", "scan": _cmd_ls()
		"cam", "watch": _cmd_watch(args)
		"loop": _cmd_loop(args)
		"kill", "disable": _cmd_kill(args)
		"restore": _cmd_restore(args)
		"blackout": _cmd_blackout()
		"door", "unlock": _cmd_unlock(args)
		"lock": _cmd_lock(args)
		"power": _cmd_power(args)
		"relay": _cmd_relay(args)
		"drones": _cmd_drones(args)
		"clear", "cls": log.clear()
		"logout", "exit", "quit": game.close_tablet()
		_: _out("unknown command: %s   (try `help`)" % verb, "red")


func _cmd_help() -> void:
	for c in _catalog():
		if c.admin and not admin:
			continue
		_out("  %-22s %s" % [c.usage, c.help], "dim")
	_out("  trace rises with every action; fill the bar and you're locked out.", "dim")


func _cmd_ls() -> void:
	_out("CAMERAS", "amber")
	for i in game.cameras().size():
		var c := game.cameras()[i]
		var st := "live"
		if c.destroyed: st = "no signal"
		elif c.disabled: st = "offline"
		elif c.looped > 0.0: st = "looped %ds" % ceili(c.looped)
		elif c.alarm: st = "ALARM"
		_out("  cam %d  %-14s %s" % [i + 1, _slug(c.label), st], "green" if st == "live" else "red")
	_out("DOORS", "amber")
	for d in game.facility.doors:
		var st2: String = "open" if not d.secured() else ("unlocked" if d.unlocked else d.access.to_upper())
		if not d.reader_live(): st2 = "reader dead"
		_out("  %-16s %s  [%s]" % [_slug(d.label), st2, d.zone.to_lower()], "dim")
	_out("ZONES (power)", "amber")
	var zones := {}
	for l in game.facility.lamps:
		zones[l.zone] = l.powered
	for z: String in zones:
		_out("  %-16s %s" % [z.to_lower(), "on" if zones[z] else "off"], "dim")
	_out("relay  %s   drones  %d aloft" % ["jammed" if game.comms_down else "up", game.facility.drones.filter(func(dr: Drone) -> bool: return dr.scanning()).size()], "dim")


func _cam(args: Array) -> int:
	if args.is_empty():
		return -1
	if args[0].is_valid_int():
		return int(args[0]) - 1
	for i in game.cameras().size():
		if _slug(game.cameras()[i].label).begins_with(args[0]):
			return i
	return -1


func _cmd_watch(args: Array) -> void:
	var i := _cam(args)
	if i < 0 or i >= game.cameras().size():
		_out("usage: cam <n>", "red"); return
	watch_cam = i
	game.tablet_cam = i
	_out("feed: %s" % _slug(game.cameras()[i].label), "green")


func _cmd_loop(args: Array) -> void:
	var i := _cam(args)
	var cams := game.cameras()
	if i < 0 or i >= cams.size():
		_out("usage: loop <n>", "red"); return
	if not cams[i].camera_live():
		_out("cam %d is not live" % (i + 1), "red"); return
	cams[i].loop_feed()
	game.add_trace(12.0, "Feed buffer anomaly")
	flash = "cam"
	watch_cam = i
	game.tablet_cam = i
	_out("looping %s for %ds — nobody's watching now" % [_slug(cams[i].label), int(Device.LOOP_TIME)], "green")


func _cmd_kill(args: Array) -> void:
	var i := _cam(args)
	var cams := game.cameras()
	if i < 0 or i >= cams.size():
		_out("usage: kill <n>", "red"); return
	if cams[i].disabled or cams[i].destroyed:
		_out("already down", "dim"); return
	cams[i].disable()
	game.add_trace(25.0, "Camera offline")
	game._schedule_repair(cams[i], 20.0)
	_out("%s offline — maintenance will be dispatched" % _slug(cams[i].label), "amber")


func _cmd_restore(args: Array) -> void:
	var i := _cam(args)
	var cams := game.cameras()
	if i < 0 or i >= cams.size() or not cams[i].disabled:
		_out("usage: restore <n>", "red"); return
	cams[i].repaired(game)
	_out("%s back online" % _slug(cams[i].label), "green")


func _cmd_blackout() -> void:
	if not admin:
		_out("blackout: admin session required", "red"); return
	for c in game.cameras():
		if not c.destroyed:
			c.disable()
	game.add_trace(40.0, "Camera system shutdown")
	game._schedule_repair(game._terminal(), 15.0)
	_out("all cameras down. this will be noticed fast.", "amber")


func _door(args: Array) -> Door:
	if args.is_empty():
		return null
	for d in game.facility.doors:
		if _slug(d.label).begins_with(args[0]):
			return d
	return null


func _cmd_unlock(args: Array) -> void:
	var d := _door(args)
	if d == null:
		_out("usage: unlock <door>   (see `ls`)", "red"); return
	if not d.reader_live():
		_out("%s reader is dead — no power to the strike" % _slug(d.label), "red"); return
	d.unlocked = true
	game.add_trace(15.0, "Door forced: %s" % d.label)
	_out("%s unlocked" % _slug(d.label), "green")


func _cmd_lock(args: Array) -> void:
	var d := _door(args)
	if d == null:
		_out("usage: lock <door>", "red"); return
	d.unlocked = false
	_out("%s re-secured" % _slug(d.label), "dim")


func _cmd_power(args: Array) -> void:
	if not admin:
		_out("power: admin session required", "red"); return
	if args.size() < 2 or not (args[1] in ["on", "off"]):
		_out("usage: power <zone> on|off", "red"); return
	var on: bool = args[1] == "on"
	var hit := false
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.BREAKER and _slug(dv.zone).begins_with(args[0]):
			dv.sabotaged = not on
			game.set_zone_power(dv, on)
			hit = true
	if hit:
		game.add_trace(10.0, "Power circuit toggled")
		_out("power %s: %s" % [args[0], "on" if on else "off"], "green" if on else "amber")
	else:
		_out("no such zone", "red")


func _cmd_relay(args: Array) -> void:
	if args.is_empty() or not (args[0] in ["off", "on", "down", "up"]):
		_out("usage: relay off|on", "red"); return
	var off: bool = args[0] in ["off", "down"]
	var relay: Device = null
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.RELAY:
			relay = dv
	if off and not game.comms_down:
		relay.sabotaged = true
		game.jam_comms(relay)
		game.add_trace(20.0, "Relay link dropped")
		_out("radio net down — alarms go nowhere now", "green")
	elif not off and game.comms_down:
		relay.sabotaged = false
		game.comms_restored()
		_out("relay back up", "amber")
	else:
		_out("relay already %s" % ("down" if off else "up"), "dim")


func _cmd_drones(args: Array) -> void:
	if args.is_empty() or args[0] != "ground":
		_out("usage: drones ground", "red"); return
	if not admin:
		_out("drones: admin session required", "red"); return
	for dr in game.facility.drones:
		if dr.scanning():
			dr.mode = Drone.Mode.RETURN
	game.add_trace(15.0, "Drone fleet recalled")
	_out("drones recalled to base", "green")


# ------------------------------------------------------------------ catalog / palette

func _catalog() -> Array[Dictionary]:
	return [
		{"usage": "ls", "verb": "ls", "help": "list cameras, doors, zones", "admin": false},
		{"usage": "cam <n>", "verb": "cam", "help": "watch a camera feed", "admin": false},
		{"usage": "loop <n>", "verb": "loop", "help": "loop a feed (+12)", "admin": false},
		{"usage": "kill <n>", "verb": "kill", "help": "disable a camera (+25)", "admin": false},
		{"usage": "restore <n>", "verb": "restore", "help": "bring a camera back", "admin": false},
		{"usage": "unlock <door>", "verb": "unlock", "help": "release a door lock (+15)", "admin": false},
		{"usage": "lock <door>", "verb": "lock", "help": "re-secure a door", "admin": false},
		{"usage": "relay off", "verb": "relay", "help": "jam guard radio (+20)", "admin": false},
		{"usage": "blackout", "verb": "blackout", "help": "all cameras off (+40)", "admin": true},
		{"usage": "power <zone> off", "verb": "power", "help": "cut a zone's power (+10)", "admin": true},
		{"usage": "drones ground", "verb": "drones", "help": "recall the drones (+15)", "admin": true},
		{"usage": "help", "verb": "help", "help": "this list", "admin": false},
		{"usage": "logout", "verb": "logout", "help": "disconnect", "admin": false},
	]


func _verbs() -> Array:
	var out: Array = []
	for c in _catalog():
		if not c.admin or admin:
			out.append(c.verb)
	return out


func _targets(verb: String) -> Array:
	match verb:
		"cam", "watch", "loop", "kill", "restore":
			return range(1, game.cameras().size() + 1).map(func(i: int) -> String: return str(i))
		"unlock", "lock", "door":
			return game.facility.doors.map(func(d: Door) -> String: return _slug(d.label))
		"power":
			var z := {}
			for l in game.facility.lamps:
				z[_slug(l.zone)] = true
			return z.keys()
		"relay":
			return ["off", "on"]
		"drones":
			return ["ground"]
	return []


## The on-screen palette: what you can usefully type next.
func suggestions() -> Array:
	var parts := input.split(" ", false)
	if parts.size() <= 1 and not input.ends_with(" "):
		var out: Array = []
		for c in _catalog():
			if (not c.admin or admin) and c.verb.begins_with(input.to_lower()):
				out.append({"text": c.usage, "help": c.help, "admin": c.admin})
		return out
	var verb: String = parts[0].to_lower()
	var frag: String = parts[-1].to_lower() if not input.ends_with(" ") else ""
	return _targets(verb).filter(func(t: String) -> bool: return t.begins_with(frag)).map(func(t: String) -> Dictionary: return {"text": t, "help": "", "admin": false})


# ------------------------------------------------------------------ helpers

func _out(text: String, tag := "plain") -> void:
	log.append({"text": text, "tag": tag})
	if log.size() > 80:
		log.pop_front()


static func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "-")
