extends Node
## Persistent settings, loadout, learned hints and the input map.

const PATH := "user://settings.cfg"

var sensitivity := 0.0021
## Exposure multiplier for the night scene.
var brightness := 1.0
var primary := "carbine"
var gadgets: Array[String] = ["frag", "smoke"]
var learned: Dictionary = {}
var best_time := -1.0
var _glyphs: Dictionary = {}
## Automated test runs must not touch the player's saved settings.
var persist := true

# Default bindings. Keys are physical keycodes so the layout never matters.
const BINDINGS := {
	"move_forward": [["key", KEY_W]], "move_back": [["key", KEY_S]],
	"move_left": [["key", KEY_A]], "move_right": [["key", KEY_D]],
	"sprint": [["key", KEY_SHIFT]], "crouch": [["key", KEY_C]], "crouch_hold": [["key", KEY_CTRL]],
	"jump": [["key", KEY_SPACE]], "lean_left": [["key", KEY_Q]], "lean_right": [["key", KEY_E]],
	"fire": [["mouse", MOUSE_BUTTON_LEFT]], "aim": [["mouse", MOUSE_BUTTON_RIGHT]],
	"reload": [["key", KEY_R]], "fire_mode": [["key", KEY_B]],
	"primary": [["key", KEY_1]], "sidearm": [["key", KEY_2]], "swap": [["mouse", MOUSE_BUTTON_WHEEL_UP], ["mouse", MOUSE_BUTTON_WHEEL_DOWN]],
	"gadget": [["key", KEY_G]], "gadget_cycle": [["key", KEY_X]],
	"interact": [["key", KEY_F]], "bandage": [["key", KEY_T]], "hack": [["key", KEY_H]],
	"pause": [["key", KEY_ESCAPE]], "quicksave": [["key", KEY_F5]], "quickload": [["key", KEY_F6], ["key", KEY_F9]],
}


func _ready() -> void:
	_register_input()
	load_settings()


func _register_input() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for b: Array in BINDINGS[action]:
			if b[0] == "key":
				var ev := InputEventKey.new()
				ev.physical_keycode = b[1]
				InputMap.action_add_event(action, ev)
			else:
				var mb := InputEventMouseButton.new()
				mb.button_index = b[1]
				InputMap.action_add_event(action, mb)


## Human-readable label for the first binding of an action, e.g. "F" or "RMB".
func glyph(action: String) -> String:
	if _glyphs.has(action):
		return _glyphs[action]
	var g := _make_glyph(action)
	_glyphs[action] = g
	return g


func _make_glyph(action: String) -> String:
	if not InputMap.has_action(action):
		return action.to_upper()
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: Key = ev.physical_keycode
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
			var s := OS.get_keycode_string(code)
			match s:
				"Shift": return "SHIFT"
				"Ctrl": return "CTRL"
				"Space": return "SPACE"
				"Escape": return "ESC"
			return s.to_upper()
		if ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				_: return "WHEEL"
	return "?"


func is_learned(id: String) -> bool:
	return learned.get(id, false)


func learn(id: String) -> void:
	if not learned.get(id, false):
		learned[id] = true
		save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sensitivity = cfg.get_value("input", "sensitivity", sensitivity)
	brightness = cfg.get_value("video", "brightness", brightness)
	primary = cfg.get_value("loadout", "primary", primary)
	var g: Array = cfg.get_value("loadout", "gadgets", gadgets)
	gadgets.clear()
	for x in g:
		gadgets.append(String(x))
	learned = cfg.get_value("hints", "learned", {})
	best_time = cfg.get_value("records", "best_time", -1.0)


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("loadout", "primary", primary)
	cfg.set_value("loadout", "gadgets", gadgets)
	cfg.set_value("hints", "learned", learned)
	cfg.set_value("records", "best_time", best_time)
	cfg.save(PATH)


func reset_hints() -> void:
	learned.clear()
	save_settings()
