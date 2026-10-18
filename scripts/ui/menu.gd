class_name Menu
extends CanvasLayer
## Title and loadout, pause, settings and debrief. One editorial column on the left, set in the
## same type as the HUD: a heading, a short amber rule, tracked labels, and plain sentences.
## No control lists up front; the game teaches its keys as they become relevant, and the
## reference sheet lives in settings for anyone who wants it.

var game: Game

var _root: Control
var _panel: VBoxContainer
var _loading_bar: ColorRect
var _loading_t := 0.0

const PRIMARIES := ["carbine", "smg", "dmr"]
const GADGET_DESC := {
	"frag": "Lethal within 4 m. Guards who see it land will run.",
	"flash": "Blinds anyone facing it for seconds. Don't watch it go off.",
	"smoke": "Blocks their sight for twenty seconds. Not their bullets.",
	"decoy": "Rattles after landing. Unalerted guards go to check it.",
}
const CONTROLS := [
	["move_forward", "Move (WASD)"], ["sprint", "Sprint · hold breath when scoped"], ["crouch", "Crouch"], ["crouch_hold", "Crouch while held"],
	["jump", "Jump · vault"], ["lean_left", "Lean left"], ["lean_right", "Lean right"], ["aim", "Aim · aim over low cover"],
	["fire", "Fire"], ["reload", "Reload"], ["fire_mode", "Fire mode"], ["primary", "Primary"], ["sidearm", "Sidearm"],
	["gadget", "Equipment (hold, release)"], ["gadget_cycle", "Switch equipment"], ["interact", "Interact · takedown · drag · multitool"],
	["bandage", "Bandage a wound"], ["quicksave", "Quicksave"], ["quickload", "Quickload"], ["pause", "Pause"],
]


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_panel = VBoxContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.position.x = 150
	_panel.custom_minimum_size = Vector2(760, 0)
	_panel.add_theme_constant_override("separation", 10)
	_root.add_child(_panel)


func _process(dt: float) -> void:
	if _loading_bar and is_instance_valid(_loading_bar):
		_loading_t += dt
		_loading_bar.position.x = fmod(_loading_t * 120.0, 260.0) - 50.0


func hide_all() -> void:
	visible = false


func _clear() -> void:
	visible = true
	_loading_bar = null
	for c in _panel.get_children():
		c.queue_free()


# ------------------------------------------------------------------ building blocks

func _title(text: String, color := Style.INK, size := 52) -> void:
	var l := Style.label(text, size, color, Style.bold, 12)
	_panel.add_child(l)
	var r := ColorRect.new()
	r.color = Style.AMBER
	r.custom_minimum_size = Vector2(44, 2)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(r)
	_panel.add_child(Style.spacer(2))


func _tag(text: String, color := Style.AMBER) -> void:
	_panel.add_child(Style.micro(text, color, 13))


func _section(text: String) -> void:
	_panel.add_child(Style.spacer(6))
	_panel.add_child(Style.micro(text, Style.DIM, 12))


func _body(text: String, width := 620.0) -> void:
	var l := Style.label(text, 17, Style.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(l)


## A line of tracked labels, each in its own colour.
func _line(items: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for i in items.size():
		var it: Array = items[i]
		if i > 0:
			row.add_child(Style.micro("  ·  ", Style.FAINT))
		row.add_child(Style.micro(it[0], it[1]))
	_panel.add_child(row)


func _buttons(defs: Array) -> void:
	_panel.add_child(Style.spacer(10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for d: Array in defs:
		var b := Style.button(d[0], d.size() < 3 or d[2])
		b.pressed.connect(d[1])
		row.add_child(b)
	_panel.add_child(row)


## A selectable row: a mark, a name and one line about it. Selected rows carry amber.
func _option(name: String, desc: String, selected: bool, on_pick: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(760, 38)
	b.add_theme_stylebox_override("normal", Style.box(Color(1, 0.72, 0.29, 0.05) if selected else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("hover", Style.box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("pressed", Style.box(Color(1, 0.72, 0.29, 0.09), Color(0, 0, 0, 0), 0, 0))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 14)
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(8, 8)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_stylebox_override("panel", Style.box(Style.AMBER if selected else Color(0, 0, 0, 0), Style.AMBER if selected else Style.DIM, 1, 0, 4))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pad)
	h.add_child(mark)
	var n := Style.label(name, 16, Style.AMBER if selected else Style.INK, Style.semibold, 2)
	n.custom_minimum_size = Vector2(150, 0)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	var d := Style.label(desc, 14, Style.DIM)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(d)
	b.add_child(h)
	b.mouse_entered.connect(func() -> void: Sfx.ui("ui_move", -10.0))
	b.pressed.connect(func() -> void:
		Sfx.ui("ui_select", -6.0)
		on_pick.call())
	return b


# ------------------------------------------------------------------ screens

func show_loading() -> void:
	_clear()
	_title("BLACKSITE")
	_tag("PREPARING THE SITE", Style.DIM)
	var track := Control.new()
	track.custom_minimum_size = Vector2(210, 2)
	track.clip_contents = true
	var base := ColorRect.new()
	base.color = Style.FAINT
	base.size = Vector2(210, 2)
	track.add_child(base)
	_loading_bar = ColorRect.new()
	_loading_bar.color = Style.INK
	_loading_bar.size = Vector2(50, 2)
	track.add_child(_loading_bar)
	_panel.add_child(track)


func show_title() -> void:
	_clear()
	_title("BLACKSITE")
	_tag("ONE OPERATOR  ·  ONE NIGHT")
	_body("Go in through the breach in the west wall, copy the drive in the warehouse office, and leave the way you came. They don't know you're here. Yet.")
	_section("PRIMARY")
	for id: String in PRIMARIES:
		var w: WeaponData = load("res://resources/weapons/%s.tres" % id)
		_panel.add_child(_option(w.display_name, w.description, Settings.primary == id, func() -> void:
			Settings.primary = id
			Settings.save_settings()
			show_title()))
	_section("EQUIPMENT  ·  CHOOSE TWO")
	for id: String in GADGET_DESC:
		_panel.add_child(_option(Gadget.INFO[id].name, GADGET_DESC[id], id in Settings.gadgets, func() -> void:
			if id in Settings.gadgets:
				Settings.gadgets.erase(id)
			else:
				Settings.gadgets.append(id)
				if Settings.gadgets.size() > 2:
					Settings.gadgets.remove_at(0)
			Settings.save_settings()
			show_title()))
	if Settings.best_time > 0.0:
		_panel.add_child(Style.spacer(4))
		var t := int(Settings.best_time)
		_line([["BEST NIGHT  %d:%02d" % [t / 60, t % 60], Style.DIM]])
	_buttons([["DEPLOY", game.start_mission], ["SETTINGS", show_settings.bind(show_title), false], ["QUIT", _quit, false]])


func _stat_grid(rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 3)
	for r: Array in rows:
		grid.add_child(Style.label(r[0], 16, Style.DIM))
		var v := Style.label(r[1], 16, Style.AMBER, Style.semibold)
		v.custom_minimum_size = Vector2(170, 0)
		grid.add_child(v)
	_panel.add_child(grid)


func _stats() -> void:
	var s := game.stats
	var secs := int(game.time)
	var acc := roundi(float(s.hits) / maxf(1.0, float(s.shots)) * 100.0)
	_stat_grid([
		["Time", "%d:%02d" % [secs / 60, secs % 60]], ["Seen", "yes" if game.detected else "never"],
		["Hostiles neutralized", str(s.kills)], ["Bodies found", str(game.bodies_found())],
		["Silent takedowns", str(s.takedowns)], ["Missed radio checks", str(game.hq.stats.missed_checks)],
		["Accuracy", "%d%%  ·  %d headshots" % [acc, s.heads]], ["Alarm", "raised" if game.hq.stats.alarms > 0 else "never raised"],
		["Damage taken", str(roundi(s.damage_taken))], ["Reaction force", "called in" if game.hq.qrf_called else "never called"],
	])


func show_pause() -> void:
	_clear()
	_title("PAUSED", Style.INK, 44)
	var items: Array = [[game.objective_text(), Style.AMBER]]
	items.append_array(game.hud.status_items())
	_line(items)
	_panel.add_child(Style.spacer(4))
	var secs := int(game.time)
	_line([["%d:%02d ON SITE" % [secs / 60, secs % 60], Style.DIM], [game.player.weapons.slots[0].display_name, Style.DIM],
		["%d NEUTRALIZED" % int(game.stats.kills), Style.DIM], ["%s BANDAGES" % game.player.bandages, Style.DIM]])
	var row := [["RESUME", game.resume]]
	if SaveGame.exists():
		row.append(["LOAD QUICKSAVE", game.quickload, false])
	row.append_array([["RESTART", game.start_mission, false], ["SETTINGS", show_settings.bind(show_pause), false], ["ABANDON", game.to_menu, false]])
	_buttons(row)


func show_settings(back: Callable) -> void:
	_clear()
	_title("SETTINGS", Style.INK, 44)
	_section("INPUT AND PICTURE")
	_panel.add_child(Style.slider("Mouse sensitivity", 0.3, 6.0, 0.05, Settings.sensitivity * 1000.0, func(v: float) -> void:
		Settings.sensitivity = v / 1000.0
		Settings.save_settings()))
	_panel.add_child(Style.slider("Brightness", 0.6, 1.8, 0.05, Settings.brightness, func(v: float) -> void:
		Settings.brightness = v
		game.facility.apply_brightness()
		Settings.save_settings()))
	_section("SOUND")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	for def: Array in [["Master", "vol_master"], ["Effects", "vol_effects"], ["Voices", "vol_voice"], ["Ambience", "vol_ambience"]]:
		var key: String = def[1]
		grid.add_child(Style.slider(def[0], 0.0, 1.0, 0.02, Settings.get(key), func(v: float) -> void:
			Settings.set(key, v)
			Sfx.apply_volumes()
			Settings.save_settings(), 180.0))
	_panel.add_child(grid)
	_panel.add_child(Style.toggle("Subtitles", Settings.subtitles, func(v: bool) -> void:
		Settings.subtitles = v
		Settings.save_settings()))
	_section("CONTROLS  ·  THE GAME SHOWS THESE WHEN THEY MATTER")
	var cg := GridContainer.new()
	cg.columns = 4
	cg.add_theme_constant_override("h_separation", 24)
	cg.add_theme_constant_override("v_separation", 2)
	for r: Array in CONTROLS:
		var k := Style.label(Settings.glyph(r[0]), 14, Style.INK, Style.semibold, 1)
		k.custom_minimum_size = Vector2(56, 0)
		cg.add_child(k)
		var d := Style.label(r[1], 14, Style.DIM)
		d.custom_minimum_size = Vector2(250, 0)
		cg.add_child(d)
	_panel.add_child(cg)
	_buttons([["BACK", back], ["RESET TIPS", _reset_tips, false]])


func _quit() -> void:
	get_tree().quit()


func _reset_tips() -> void:
	Settings.reset_hints()
	Sfx.ui("hint", -6.0)


func show_debrief(success: bool, rating: String) -> void:
	_clear()
	_title("EXTRACTED" if success else "KILLED IN ACTION", Style.INK if success else Style.RED, 52)
	_tag(("RATING  ·  " + rating) if success else "THE NIGHT ENDS HERE", Style.AMBER if success else Style.DIM)
	_panel.add_child(Style.spacer(4))
	_stats()
	var row := [["REDEPLOY", game.start_mission]]
	if SaveGame.exists() and not success:
		row.insert(0, ["LOAD QUICKSAVE", game.quickload])
	row.append(["CHANGE LOADOUT", game.to_menu, false])
	_buttons(row)
