class_name NetConsole
extends RefCounted
## The command console on the operator's nettop, used against facility security props.
##
## You reach it by putting the nettop down at an access port and running a cable to it. The
## nettop then logs in on its own: a cloned security badge is presented over the link (clean,
## admin), a login read off a box's cover is tried first (quick, quiet), and otherwise the
## nettop brute-forces the port's login from a list of factory defaults — slow, and every failed
## attempt lands in their logs. Once in, you map what is on the line with `nmap`, then address
## each prop by its name or address and act on it with a named command. Every command raises a
## trace meter that locks you out if it fills; a few need the admin session.
##
## This is entirely game fiction and operates only on in-game props (cameras, doors, breakers, the
## radio relay, drones). It performs no real scanning or networking of any kind.

enum Phase { LOGIN, SHELL }

## One terminal window on the deck: its own scrollback, command line and history. A scan runs in
## the terminal it was typed in, and you can work in another one meanwhile.
class Term:
	var input := ""
	var cursor := 0
	var log: Array[Dictionary] = []
	var history: Array[String] = []
	var hist_i := 0
	## A command still running here ("nmap"), how long for, and how far it got.
	var job := ""
	var job_t := 0.0
	var job_i := 0


const MAX_TERMS := 4
var terms: Array[Term] = []
var focus := 0
## Where output lands: a running job's own terminal while it prints, otherwise the focused one.
var _out_term: Term = null

var game: Game
var node: Device
var admin := false
var connected := false
var phase := Phase.SHELL
## How the login is being done: "badge", "creds" (read off the cover) or "brute".
var mode := ""
var attempts: Array[String] = []
var attempt_i := 0
var login_t := 0.0
var login_dur := 0.0
var _next_t := 0.0
# The command line, scrollback and history of the focused terminal.
var input: String:
	get:
		return term().input
	set(v):
		term().input = v
var cursor: int:
	get:
		return term().cursor
	set(v):
		term().cursor = v
var log: Array[Dictionary]:
	get:
		return term().log
var history: Array[String]:
	get:
		return term().history
var hist_i: int:
	get:
		return term().hist_i
	set(v):
		term().hist_i = v
var watch_cam := 0
## Riding a drone's camera instead of a fixed one.
var watch_drone: Drone = null
## Transient highlight of a device just acted on, for the feed/overlay.
var flash := ""
## True once nmap has listed the props this session.
var scanned := false

const PROMPT := "operator@nettop"
const SUBNET := "10.13.37.0/24"
const BRUTE_TIME := 15.0
const BRUTE_TRACE := 45.0
## Factory logins the brute-force walks through, in order. The port's real one goes last.
const DEFAULTS: Array[String] = [
	"admin:admin", "admin:password", "admin:1234", "root:root", "admin:12345", "root:toor",
	"admin:default", "service:service", "tech:tech", "admin:admin123", "operator:operator",
	"root:password", "admin:P@ssw0rd", "install:install", "root:1234", "guest:guest",
	"admin:changeme", "root:changeme", "admin:letmein", "maint:maint", "admin:cctv",
	"admin:facility", "admin:0000", "root:admin", "admin:1111", "admin:qwerty", "sec:sec",
	"admin:Welcome1", "admin:site", "supervisor:supervisor", "admin:security", "user:user",
	"admin:camera", "root:default", "admin:access", "admin:gate", "admin:123456", "root:service",
	"admin:ops", "field:field", "admin:node", "root:install", "admin:remote", "admin:secure",
	"admin:4321", "root:0000", "admin:blacksite",
]


## Cable up and start the login. `p_mode` is "badge", "creds" or "brute".
func open(p_node: Device, p_mode: String) -> void:
	node = p_node
	mode = p_mode
	admin = false
	connected = true
	phase = Phase.LOGIN
	terms.clear()
	terms.append(Term.new())
	focus = 0
	_out_term = null
	scanned = false
	attempts.clear()
	attempt_i = 0
	login_t = 0.0
	_next_t = 0.9
	_out("nettop: link up on %s  ·  1000M full  ·  %s" % [_slug(node.label), SUBNET], "dim")
	_out("probe: ssh on %s  ·  open  ·  banner \"secnet-%s\"" % [_host_ip(), _slug(node.label)], "dim")
	match mode:
		"saved":
			login_dur = 0.7
			_out("auth: cached session key for %s …" % _host_ip(), "amber")
		"badge":
			login_dur = 1.8
			_out("auth: presenting security badge over the link …", "amber")
		"creds":
			login_dur = 2.4
			attempts = [node.password]
			_out("auth: trying the login written inside the cover …", "amber")
		_:
			login_dur = BRUTE_TIME
			for a in DEFAULTS:
				if a != node.password:
					attempts.append(a)
			attempts.append(node.password)
			_out("bruteforce: %d factory logins against ssh  ·  every miss is logged on their side" % attempts.size(), "amber")


func close() -> void:
	connected = false
	phase = Phase.SHELL
	node = null
	watch_drone = null


# ------------------------------------------------------------------ terminals

func term() -> Term:
	if terms.is_empty():
		terms.append(Term.new())
	focus = clampi(focus, 0, terms.size() - 1)
	return terms[focus]


func new_term() -> void:
	if terms.size() >= MAX_TERMS:
		_out("no more terminals: four is the deck's limit", "red")
		return
	terms.append(Term.new())
	focus = terms.size() - 1
	_out("terminal %d  ·  ctrl+tab moves between them, ctrl+w closes this one" % terms.size(), "dim")


func close_term() -> void:
	if terms.size() <= 1:
		_out("the last terminal stays open; `exit` pulls the cable", "dim")
		return
	terms.remove_at(focus)
	focus = clampi(focus, 0, terms.size() - 1)


func cycle(d: int) -> void:
	focus = wrapi(focus + d, 0, terms.size())


func focus_term(i: int) -> void:
	if i >= 0 and i < terms.size():
		focus = i


## Jobs print into their own terminal as they go.
func _tick_jobs(dt: float) -> void:
	for t in terms:
		if t.job == "":
			continue
		t.job_t += dt
		_out_term = t
		if t.job == "nmap":
			var hs := hosts()
			while t.job_i < hs.size() and t.job_t >= 0.22 * (t.job_i + 1):
				var h := hs[t.job_i]
				_out("  %-13s %-16s %-6s %s" % [h.ip, h.host, h.short, _host_state(h)], _state_tag(h), true)
				t.job_i += 1
			if t.job_i >= hs.size():
				t.job = ""
				scanned = true
				_out("%d props on the line  ·  name one to look closer:  nmap <name>" % hs.size(), "green")
		_out_term = null


## What the feed window shows: a drone you're riding, or the chosen fixed camera.
func feed_source() -> Node3D:
	if watch_drone and not watch_drone.destroyed:
		return watch_drone
	var cams := game.cameras()
	return cams[clampi(watch_cam, 0, cams.size() - 1)]


## The login runs itself; lines appear as attempts go by, and the shell opens on the hit.
func tick(dt: float) -> void:
	if not connected:
		return
	if phase == Phase.SHELL:
		_tick_jobs(dt)
		return
	login_t += dt
	if mode == "brute":
		var per := login_dur / attempts.size()
		while attempt_i < attempts.size() - 1 and login_t >= per * (attempt_i + 1):
			_out("  [%2d/%d]  %-24s denied" % [attempt_i + 1, attempts.size(), attempts[attempt_i]], "dim")
			Sfx.ui("key", -14.0)
			attempt_i += 1
			game.add_trace(BRUTE_TRACE / attempts.size(), "Failed login")
			if not connected:
				return
	elif mode == "creds" and attempt_i == 0 and login_t >= 1.0:
		_out("  [ 1/1]  %-24s …" % attempts[0], "dim")
		attempt_i = 1
	if login_t >= login_dur:
		finish_login()


## Jump to the end of the login (the hit, the badge accepted).
func finish_login() -> void:
	if phase != Phase.LOGIN:
		return
	phase = Phase.SHELL
	match mode:
		"saved":
			admin = node.cracked_admin
			_out("session resumed: %s  ·  no login, nothing logged" % ("admin" if admin else "user"), "green")
		"badge":
			admin = true
			_out("auth: badge accepted  ·  session: admin", "green")
		"creds":
			_out("  [ 1/1]  %-24s OK" % attempts[0], "green")
			_out("session: user (cover login)", "green")
			game.add_trace(5.0, "Login")
		_:
			_out("  [%2d/%d]  %-24s OK" % [attempts.size(), attempts.size(), attempts[-1]], "green")
			_out("session: user (brute-forced)  ·  %d failed logins on record" % (attempts.size() - 1), "amber")
	_out("run `nmap` to list what's on the line. `help` lists commands, Tab completes.", "dim")
	game.session_opened()


## Login progress, 0..1, for the interface.
func login_progress() -> float:
	return clampf(login_t / login_dur, 0.0, 1.0) if phase == Phase.LOGIN else 1.0


## Whether the nettop's activity light is on this instant.
func busy_blink(t: float) -> bool:
	if phase == Phase.LOGIN:
		return fmod(t, 0.16) < 0.08
	return fmod(t, 1.4) < 0.1


func _host_ip() -> String:
	match node.label:
		"SECURITY TERMINAL": return "10.13.37.1"
		"SERVER CABINET": return "10.13.37.3"
	return "10.13.37.4"


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
	if term().job != "":
		return
	var line := input.strip_edges()
	input = ""
	cursor = 0
	if line == "" or phase != Phase.SHELL:
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
		"help", "?", "man": _cmd_help()
		"nmap", "scan", "ls", "net": _cmd_nmap(args)
		"cam", "watch", "view": _cmd_watch(args)
		"loop", "replay": _cmd_loop(args)
		"kill", "disable": _cmd_kill(args)
		"restore": _cmd_restore(args)
		"blackout": _cmd_blackout()
		"door", "unlock", "lock": _cmd_door(verb, args)
		"power", "breaker": _cmd_power(args)
		"relay", "jam": _cmd_relay(args)
		"drones": _cmd_drones(args)
		"uav", "drone": _cmd_uav(args)
		"term", "new": new_term()
		"close": close_term()
		"clear", "cls": log.clear()
		"logout", "exit", "quit", "disconnect": game.close_tablet()
		_: _out("%s: command not found   (try `help`)" % verb, "red")


func _cmd_help() -> void:
	_out("address a prop by its name or address — see `nmap`", "dim")
	for c in _catalog():
		if c.admin and not admin:
			continue
		_out("  %-20s %s%s" % [c.usage, c.help, "   [admin]" if c.admin else ""], "dim")
	_out("  every command raises trace; fill the bar and you're locked out.", "dim")


# ------------------------------------------------------------------ the props list (nmap)

## The props on the line, built from live game objects. Addresses are stable by role.
func hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.RELAY:
			out.append({"ip": "10.13.37.2", "host": "relay-gw", "short": "relay", "desc": "radio relay",
				"type": "relay", "dev": dv})
	var i := 11
	for c in game.cameras():
		out.append({"ip": "10.13.37.%d" % i, "host": _slug(c.label), "short": "cam", "desc": "pan/tilt camera",
			"type": "camera", "dev": c})
		i += 1
	i = 21
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.BREAKER:
			out.append({"ip": "10.13.37.%d" % i, "host": "plc-%s" % _slug(dv.zone), "short": "plc", "desc": "power breaker",
				"type": "breaker", "dev": dv, "zone": _slug(dv.zone)})
			i += 1
	i = 31
	for d in game.facility.doors:
		out.append({"ip": "10.13.37.%d" % i, "host": "rdr-%s" % _slug(d.label), "short": "door", "desc": "door reader",
			"type": "door", "door": d})
		i += 1
	var lap := game.laptop()
	if lap:
		out.append({"ip": "10.13.37.50", "host": "ws-intel", "short": "host", "desc": "data workstation",
			"type": "laptop", "dev": lap})
	i = 41
	for dr in game.facility.drones:
		out.append({"ip": "10.13.37.%d" % i, "host": "uav-%02d" % (i - 40), "short": "uav", "desc": "patrol drone",
			"type": "drone", "drone": dr})
		i += 1
	return out


func _resolve(token: String) -> Dictionary:
	for h in hosts():
		if token == h.ip or token == h.host or (token.length() >= 2 and h.host.begins_with(token)) or h.ip.ends_with("." + token):
			return h
	return {}


func _cmd_nmap(args: Array) -> void:
	var target := ""
	for a: String in args:
		if not a.begins_with("-"):
			target = a
	if target == "":
		_nmap_list()
	else:
		_nmap_host(target)


## A scan of the whole line takes a few seconds and prints hosts as it finds them; it runs in
## this terminal, so open another one if you want to keep working.
func _nmap_list() -> void:
	var t := term()
	t.job = "nmap"
	t.job_t = 0.0
	t.job_i = 0
	_out("nmap %s  ·  probing %d addresses" % [SUBNET, hosts().size()], "dim")


func _nmap_host(token: String) -> void:
	var h := _resolve(token)
	if h.is_empty():
		_out("nmap: no prop named '%s' — run `nmap` for the list" % token, "red")
		return
	_out("%s  ·  %s  ·  %s  [%s]" % [h.host, h.ip, h.desc, _host_state(h)], "amber")
	_out("  → %s" % _host_hint(h), "dim")


func _host_state(h: Dictionary) -> String:
	match h.type:
		"camera":
			var c: Device = h.dev
			if c.destroyed: return "no signal"
			if c.disabled: return "offline"
			if c.looped > 0.0: return "looped %ds" % ceili(c.looped)
			if c.alarm: return "ALARM"
			return "live"
		"door":
			var d: Door = h.door
			if not d.reader_live(): return "reader dead"
			if not d.secured(): return "open"
			return "locked (%s)" % d.access.to_lower()
		"breaker":
			return "off" if (h.dev as Device).sabotaged else "on"
		"relay":
			return "jammed" if game.comms_down else "up"
		"laptop":
			var l: Device = h.dev
			return {"idle": "idle", "copying": "copying %d%%" % roundi(l.copy_progress * 100.0), "done": "staged", "taken": "pulled"}.get(l.copy_state, "idle")
		"drone":
			var dr: Drone = h.drone
			if dr.destroyed: return "wrecked"
			if dr.down_t > 0.0: return "rebooting"
			if dr.mode == Drone.Mode.DIVE: return "ATTACK RUN"
			if dr.mode == Drone.Mode.TRACK: return "TRACKING"
			if dr.recall_t > 0.0: return "recalled %ds" % ceili(dr.recall_t)
			if dr.mode == Drone.Mode.RETURN: return "returning"
			return "patrol"
	return ""


func _state_tag(h: Dictionary) -> String:
	var s := _host_state(h)
	if s in ["ALARM", "jammed", "ATTACK RUN", "TRACKING"]:
		return "red"
	if s in ["live", "up", "on", "patrol"]:
		return "green"
	return "dim"


func _host_hint(h: Dictionary) -> String:
	match h.type:
		"camera": return "cam %s to watch, loop %s to hold its feed, kill %s to drop it" % [h.host, h.host, h.host]
		"door": return "door %s open|lock" % h.host
		"breaker": return "power %s off  (admin)" % h.zone
		"relay": return "relay down to jam the radio"
		"laptop": return "copy the drive at the machine itself"
		"drone": return "cam %s to ride its camera, uav %s ground to send it home" % [h.host, h.host]
	return ""


# ------------------------------------------------------------------ cameras

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
	var dr := _uav(args)
	if dr:
		if not dr.feed_live():
			_out("%s: no picture" % _uav_name(dr), "red"); return
		watch_drone = dr
		_out("feed: %s  ·  live from the air" % _uav_name(dr), "green")
		return
	var i := _cam(args)
	if i < 0 or i >= game.cameras().size():
		_out("usage: cam <camera|uav>", "red"); return
	watch_drone = null
	watch_cam = i
	game.tablet_cam = i
	_out("feed: %s" % _slug(game.cameras()[i].label), "green")


# ------------------------------------------------------------------ drones

func _uav_name(dr: Drone) -> String:
	return "uav-%02d" % (game.facility.drones.find(dr) + 1)


func _uav(args: Array) -> Drone:
	if args.is_empty():
		return null
	for dr in game.facility.drones:
		if _uav_name(dr).begins_with(args[0]) or ("uav" + args[0]) == _uav_name(dr).replace("-", ""):
			return dr
	return null


## One drone at a time: send it home for a while, or let it go back to work.
func _cmd_uav(args: Array) -> void:
	var dr := _uav(args)
	if dr == null or args.size() < 2 or not (args[1] in ["ground", "release"]):
		_out("usage: uav <id> ground|release", "red"); return
	if dr.destroyed:
		_out("%s: wrecked" % _uav_name(dr), "dim"); return
	if args[1] == "ground":
		if dr.mode == Drone.Mode.DIVE:
			_out("%s: not answering" % _uav_name(dr), "red"); return
		dr.recall(90.0)
		game.add_trace(12.0, "Drone recalled")
		_out("%s: return-to-base sent  ·  holds at the pad 90 s" % _uav_name(dr), "amber")
	else:
		dr.recall_t = 0.0
		_out("%s: released to patrol" % _uav_name(dr), "green")


func _cmd_loop(args: Array) -> void:
	var i := _cam(args)
	var cams := game.cameras()
	if i < 0 or i >= cams.size():
		_out("usage: loop <camera>", "red"); return
	if not cams[i].camera_live():
		_out("%s is not live" % _slug(cams[i].label), "red"); return
	cams[i].loop_feed()
	game.add_trace(12.0, "Feed buffer anomaly")
	flash = "cam"
	watch_cam = i
	game.tablet_cam = i
	_out("looping %s for %ds — nobody's watching it now" % [_slug(cams[i].label), int(Device.LOOP_TIME)], "green")


func _cmd_kill(args: Array) -> void:
	var i := _cam(args)
	var cams := game.cameras()
	if i < 0 or i >= cams.size():
		_out("usage: kill <camera>", "red"); return
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
		_out("usage: restore <camera>", "red"); return
	cams[i].repaired(game)
	_out("%s back online" % _slug(cams[i].label), "green")


func _cmd_blackout() -> void:
	if not admin:
		_out("blackout: needs an admin session", "red"); return
	for c in game.cameras():
		if not c.destroyed:
			c.disable()
	game.add_trace(40.0, "Camera system shutdown")
	game._schedule_repair(game._terminal(), 15.0)
	_out("all cameras down. this will be noticed fast.", "amber")


# ------------------------------------------------------------------ doors

func _door(args: Array) -> Door:
	if args.is_empty():
		return null
	var tok: String = args[0]
	for d in game.facility.doors:
		if _slug(d.label).begins_with(tok) or ("rdr-" + _slug(d.label)).begins_with(tok):
			return d
	return null


func _cmd_door(verb: String, args: Array) -> void:
	var d := _door(args)
	var action := ""
	if verb == "unlock":
		action = "open"
	elif verb == "lock":
		action = "lock"
	elif args.size() >= 2:
		action = args[1]
	if d == null or not (action in ["open", "lock"]):
		_out("usage: door <reader> open|lock   (names from `nmap`)", "red"); return
	if action == "open":
		if not d.reader_live():
			_out("%s: reader is dead, no power to the strike" % _slug(d.label), "red"); return
		d.unlocked = true
		game.add_trace(15.0, "Door forced: %s" % d.label)
		_out("%s open" % _slug(d.label), "green")
	else:
		d.unlocked = false
		_out("%s re-secured" % _slug(d.label), "dim")


# ------------------------------------------------------------------ power / relay / drones

func _cmd_power(args: Array) -> void:
	if not admin:
		_out("power: needs an admin session", "red"); return
	if args.size() < 2 or not (args[1] in ["on", "off"]):
		_out("usage: power <zone> on|off", "red"); return
	var on: bool = args[1] == "on"
	var zone_tok: String = args[0].trim_prefix("plc-")
	var hit := false
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.BREAKER and _slug(dv.zone).begins_with(zone_tok):
			dv.sabotaged = not on
			game.set_zone_power(dv, on)
			hit = true
	if hit:
		game.add_trace(10.0, "Power circuit toggled")
		_out("power %s: %s" % [zone_tok, "on" if on else "off"], "green" if on else "amber")
	else:
		_out("no such zone", "red")


func _cmd_relay(args: Array) -> void:
	if args.is_empty() or not (args[0] in ["off", "on", "down", "up"]):
		_out("usage: relay down|up", "red"); return
	var off: bool = args[0] in ["off", "down"]
	var relay: Device = null
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.RELAY:
			relay = dv
	if off and not game.comms_down:
		relay.sabotaged = true
		game.jam_comms(relay)
		game.add_trace(20.0, "Relay link dropped")
		_out("radio relay jammed — alarms go nowhere now", "green")
	elif not off and game.comms_down:
		relay.sabotaged = false
		game.comms_restored(relay)
		_out("relay back up", "amber")
	else:
		_out("relay already %s" % ("down" if off else "up"), "dim")


func _cmd_drones(args: Array) -> void:
	if args.is_empty() or args[0] != "ground":
		_out("usage: drones ground", "red"); return
	if not admin:
		_out("drones: needs an admin session", "red"); return
	for dr in game.facility.drones:
		if dr.scanning():
			dr.mode = Drone.Mode.RETURN
	game.add_trace(15.0, "Drone fleet recalled")
	_out("drones recalled to base", "green")


# ------------------------------------------------------------------ catalog / palette

func _catalog() -> Array[Dictionary]:
	return [
		{"usage": "nmap [name]", "verb": "nmap", "help": "list the props, or look at one", "admin": false},
		{"usage": "cam <cam|uav>", "verb": "cam", "help": "watch a camera, or ride a drone's", "admin": false},
		{"usage": "loop <cam>", "verb": "loop", "help": "hold a feed on a loop (+12)", "admin": false},
		{"usage": "kill <cam>", "verb": "kill", "help": "drop a camera (+25)", "admin": false},
		{"usage": "restore <cam>", "verb": "restore", "help": "bring a camera back", "admin": false},
		{"usage": "door <r> open|lock", "verb": "door", "help": "work a door reader (+15)", "admin": false},
		{"usage": "relay down", "verb": "relay", "help": "jam the guard radio (+20)", "admin": false},
		{"usage": "power <zone> off", "verb": "power", "help": "cut a zone's power (+10)", "admin": true},
		{"usage": "blackout", "verb": "blackout", "help": "all cameras off (+40)", "admin": true},
		{"usage": "uav <id> ground", "verb": "uav", "help": "send one drone home for 90 s (+12)", "admin": false},
		{"usage": "drones ground", "verb": "drones", "help": "recall the whole fleet (+15)", "admin": true},
		{"usage": "term", "verb": "term", "help": "another terminal (ctrl+n)", "admin": false},
		{"usage": "help", "verb": "help", "help": "this list", "admin": false},
		{"usage": "exit", "verb": "logout", "help": "unplug and pack up", "admin": false},
	]


func _verbs() -> Array:
	var out: Array = ["nmap"]
	for c in _catalog():
		if (not c.admin or admin) and c.verb != "nmap":
			out.append(c.verb)
	return out


func _targets(verb: String) -> Array:
	match verb:
		"nmap", "scan":
			return hosts().map(func(h: Dictionary) -> String: return h.host)
		"cam", "watch":
			var names: Array = game.cameras().map(func(c: Device) -> String: return _slug(c.label))
			for dr in game.facility.drones:
				names.append(_uav_name(dr))
			return names
		"loop", "replay", "kill", "disable", "restore":
			return game.cameras().map(func(c: Device) -> String: return _slug(c.label))
		"door", "unlock", "lock":
			return game.facility.doors.map(func(d: Door) -> String: return _slug(d.label))
		"power", "breaker":
			var z := {}
			for l in game.facility.lamps:
				z[_slug(l.zone)] = true
			return z.keys()
		"relay", "jam":
			return ["down", "up"]
		"drones":
			return ["ground"]
		"uav", "drone":
			return game.facility.drones.map(func(dr: Drone) -> String: return _uav_name(dr))
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

func _out(text: String, tag := "plain", quiet := false) -> void:
	var t := _out_term if _out_term else term()
	t.log.append({"text": text, "tag": tag})
	if not quiet:
		if tag == "red":
			Sfx.ui("term_err", -8.0)
		elif tag == "green":
			Sfx.ui("term_ok", -10.0)
	if t.log.size() > 120:
		t.log.pop_front()


static func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "-")
