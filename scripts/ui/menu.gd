class_name Menu
extends CanvasLayer
## Title and loadout, pause, and debrief screens. No control lists up front — the game teaches
## its keys as they become relevant; a reference sheet sits in the pause menu for anyone who wants it.

var game: Game

var _root: Control
var _panel: VBoxContainer

const PRIMARIES := ["carbine", "smg", "dmr"]
const GADGET_DESC := {
	"frag": "Lethal within 4 m. Guards who see it land will run.",
	"flash": "Blinds anyone facing it for seconds. Don't watch it go off.",
	"smoke": "Blocks their sight for twenty seconds. Not their bullets.",
	"decoy": "Rattles after landing. Unalerted guards go to check it.",
}


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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = VBoxContainer.new()
	_panel.custom_minimum_size = Vector2(860, 0)
	_panel.add_theme_constant_override("separation", 14)
	center.add_child(_panel)


func hide_all() -> void:
	visible = false


func _clear() -> void:
	visible = true
	for c in _panel.get_children():
		c.queue_free()


func _title(text: String, color := Style.INK, size := 78) -> void:
	var l := Style.label(text, size, color, Style.bold)
	l.add_theme_font_override("font", Style.spaced(Style.bold, 18))
	_panel.add_child(l)


func _tag(text: String, color := Style.AMBER) -> void:
	var l := Style.label(text, 15, color)
	l.add_theme_font_override("font", Style.spaced(Style.semibold, 6))
	_panel.add_child(l)


func _section(text: String) -> void:
	var l := Style.label(text, 13, Style.DIM)
	l.add_theme_font_override("font", Style.spaced(Style.semibold, 4))
	_panel.add_child(l)


func _spacer(h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	_panel.add_child(s)


func _buttons(defs: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for d: Array in defs:
		var b := Style.button(d[0], d.size() < 3 or d[2])
		b.pressed.connect(d[1])
		row.add_child(b)
	_panel.add_child(row)


func show_loading() -> void:
	_clear()
	_title("BLACKSITE")
	_tag("PREPARING THE SITE", Style.DIM)


func show_title() -> void:
	_clear()
	_title("BLACKSITE")
	_tag("ONE OPERATOR  ·  ONE NIGHT")
	var brief := Style.label("Go in through the breach in the west wall, copy the drive in the warehouse office, and leave the way you came. They don't know you're here — yet.", 17, Style.INK)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(brief)
	_spacer(6)
	_section("PRIMARY")
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	for id: String in PRIMARIES:
		var w: WeaponData = load("res://resources/weapons/%s.tres" % id)
		prow.add_child(_card(w.display_name, w.description, Settings.primary == id, func() -> void:
			Settings.primary = id
			Settings.save_settings()
			show_title()))
	_panel.add_child(prow)
	_section("EQUIPMENT  ·  CHOOSE TWO")
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 10)
	for id: String in GADGET_DESC:
		grow.add_child(_card(Gadget.INFO[id].name, GADGET_DESC[id], id in Settings.gadgets, func() -> void:
			if id in Settings.gadgets:
				Settings.gadgets.erase(id)
			else:
				Settings.gadgets.append(id)
				if Settings.gadgets.size() > 2:
					Settings.gadgets.remove_at(0)
			Settings.save_settings()
			show_title()))
	_panel.add_child(grow)
	_spacer(10)
	_buttons([["DEPLOY", game.start_mission], ["QUIT", _quit, false]])


func _card(title: String, desc: String, selected: bool, on_pick: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 104)
	var border := Style.AMBER if selected else Style.FAINT
	b.add_theme_stylebox_override("normal", Style.box(Color(1, 0.72, 0.29, 0.06) if selected else Color(1, 1, 1, 0.015), border, 1, 12))
	b.add_theme_stylebox_override("hover", Style.box(Color(1, 1, 1, 0.05), Style.AMBER if selected else Style.DIM, 1, 12))
	b.add_theme_stylebox_override("pressed", Style.box(Color(1, 0.72, 0.29, 0.1), Style.AMBER, 1, 12))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 10
	v.offset_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label(title, 16, Style.AMBER if selected else Style.INK)
	t.add_theme_font_override("font", Style.spaced(Style.semibold, 2))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := Style.label(desc, 13, Style.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	v.add_child(d)
	b.add_child(v)
	b.mouse_entered.connect(func() -> void: Sfx.play("ui_move", -8.0, 0.0))
	b.pressed.connect(func() -> void:
		Sfx.play("ui_select", -4.0, 0.0)
		on_pick.call())
	return b


func _stats() -> void:
	var s := game.stats
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	var secs := int(game.time)
	var acc := roundi(float(s.hits) / maxf(1.0, float(s.shots)) * 100.0)
	var rows := [
		["Time", "%d:%02d" % [secs / 60, secs % 60]],
		["Loadout", "%s  ·  %s" % [game.player.weapons.slots[0].display_name, "  ·  ".join(Settings.gadgets.map(func(g: String) -> String: return Gadget.INFO[g].name))]],
		["Hostiles neutralized", str(s.kills)],
		["Silent takedowns", str(s.takedowns)],
		["Accuracy", "%d%%  (%d headshots)" % [acc, s.heads]],
		["Damage taken", str(roundi(s.damage_taken))],
		["Seen", "yes" if game.detected else "never"],
		["Bodies found", str(game.bodies_found())],
		["Missed radio checks", str(game.hq.stats.missed_checks)],
		["Alarm", "raised" if game.hq.stats.alarms > 0 else "never raised"],
		["Reaction force", "called in" if game.hq.qrf_called else "never called"],
	]
	for r: Array in rows:
		grid.add_child(Style.label(r[0], 18, Style.DIM))
		grid.add_child(Style.label(r[1], 18, Style.AMBER, Style.semibold))
	_panel.add_child(grid)


func show_pause() -> void:
	_clear()
	_title("PAUSED", Style.INK, 56)
	_tag(game.objective_text())
	var items: Array = game.hud.status_items()
	if not items.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		for it: Array in items:
			row.add_child(Style.label(it[0], 15, it[1], Style.semibold))
		_panel.add_child(row)
	_spacer(8)
	_stats()
	_spacer(10)
	var row := [["RESUME", game.resume]]
	if SaveGame.exists():
		row.append(["LOAD QUICKSAVE", game.quickload, false])
	row.append_array([["RESTART", game.start_mission, false], ["CONTROLS", show_controls, false], ["ABANDON", game.to_menu, false]])
	_buttons(row)


func show_controls() -> void:
	_clear()
	_title("CONTROLS", Style.INK, 44)
	_tag("THE GAME SHOWS THESE WHEN THEY MATTER", Style.DIM)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 3)
	var rows := [
		["move_forward", "Move (WASD)"], ["sprint", "Sprint · hold breath when scoped"], ["crouch", "Crouch"], ["crouch_hold", "Crouch while held"],
		["jump", "Jump · vault"], ["lean_left", "Lean left"], ["lean_right", "Lean right"], ["aim", "Aim · aim over low cover"],
		["fire", "Fire"], ["reload", "Reload"], ["fire_mode", "Fire mode"], ["primary", "Primary"], ["sidearm", "Sidearm"],
		["hack", "Disconnect tablet"], ["gadget", "Equipment (hold, release)"], ["gadget_cycle", "Switch equipment"], ["interact", "Interact · takedown · drag"], ["bandage", "Bandage a wound"], ["quicksave", "Quicksave"], ["quickload", "Quickload"],
	]
	for r: Array in rows:
		grid.add_child(Style.label(Settings.glyph(r[0]), 16, Style.INK, Style.semibold))
		grid.add_child(Style.label(r[1], 16, Style.DIM))
	_panel.add_child(grid)
	_spacer(6)
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 16)
	sens_row.add_child(Style.label("Mouse sensitivity", 16, Style.DIM))
	var slider := HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 6.0
	slider.step = 0.05
	slider.value = Settings.sensitivity * 1000.0
	slider.custom_minimum_size = Vector2(320, 24)
	slider.value_changed.connect(func(v: float) -> void:
		Settings.sensitivity = v / 1000.0
		Settings.save_settings())
	sens_row.add_child(slider)
	sens_row.add_child(Style.label("Brightness", 16, Style.DIM))
	var bright := HSlider.new()
	bright.min_value = 0.6
	bright.max_value = 1.8
	bright.step = 0.05
	bright.value = Settings.brightness
	bright.custom_minimum_size = Vector2(240, 24)
	bright.value_changed.connect(func(v: float) -> void:
		Settings.brightness = v
		game.facility.apply_brightness()
		Settings.save_settings())
	sens_row.add_child(bright)
	_panel.add_child(sens_row)
	_spacer(8)
	_buttons([["BACK", show_pause], ["RESET TIPS", _reset_tips, false]])


func _quit() -> void:
	get_tree().quit()


func _reset_tips() -> void:
	Settings.reset_hints()
	show_pause()


func show_debrief(success: bool, rating: String) -> void:
	_clear()
	_title("EXTRACTED" if success else "KIA", Style.INK if success else Style.RED, 64)
	_tag(("RATING  ·  " + rating) if success else "MISSION FAILED")
	_spacer(4)
	_stats()
	_spacer(10)
	var row := [["REDEPLOY", game.start_mission]]
	if SaveGame.exists() and not success:
		row.insert(0, ["LOAD QUICKSAVE", game.quickload])
	row.append(["CHANGE LOADOUT", game.to_menu, false])
	_buttons(row)
