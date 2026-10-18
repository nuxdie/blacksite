class_name Hud
extends CanvasLayer
## The in-game interface. One overlay, four quiet corners and an empty centre.
##
## Every element answers one question an operator keeps asking:
##   top left      where am I, and what state is the site in
##   top centre    where am I going (heading arc, objective, distance)
##   centre        who is noticing me, from where, and how badly; what can I do right now
##   bottom left   how visible and how loud am I; how hurt
##   bottom right  what is in my hands
## Nothing is drawn until it matters: ammunition appears when it is low or changing, vitals when
## you are hurt, the attention line only while someone is interested in you. The sound mix says
## the same things in parallel, so none of this needs to shout.

const M := 40.0
const AMBER := Style.AMBER
const RED := Style.RED
const GREEN := Style.GREEN
const INK := Style.INK
const DIM := Style.DIM
const FAINT := Style.FAINT

var game: Game
var flash := 0.0
var hints := Hints.new()

var _fx: ColorRect
var _fx_mat: ShaderMaterial
var _flash_rect: ColorRect
var _overlay: Control
var _map: Control
var _damage := 0.0
var _dmg_dirs: Array[Dictionary] = []
var _subs: Array[Dictionary] = []
var _toast := ""
var _toast_t := 0.0
var _banner := ""
var _banner_t := 0.0
var _feed_vp: SubViewport
var _feed_cam: Camera3D
var _feed_rect: TextureRect
var _trace_reason := ""
var _trace_t := 0.0
var _vitals_a := 0.0
var _ammo_a := 0.0
var _ammo_seen := {}
var _area := ""
var _area_t := 0.0
var _gadget_seen := ""
var _gadget_flash := 0.0
var _alert := 0.0
var _alert_red := 0.0
var _caps: Dictionary = {}

var _f_micro: FontVariation
var _f_label: FontVariation
var _f_wide: FontVariation
var _f_body: Font
var _f_num: Font


func _ready() -> void:
	layer = 1
	hints.game = game
	_f_micro = Style.spaced(Style.semibold, 3)
	_f_label = Style.spaced(Style.semibold, 2)
	_f_wide = Style.spaced(Style.bold, 12)
	_f_body = Style.medium
	_f_num = Style.bold
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = preload("res://shaders/screen_fx.gdshader")
	_fx.material = _fx_mat
	add_child(_fx)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	add_child(_flash_rect)
	_feed_vp = SubViewport.new()
	_feed_vp.size = Vector2i(640, 360)
	_feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_feed_cam = Camera3D.new()
	_feed_cam.fov = 70.0
	_feed_cam.cull_mask = 1
	_feed_vp.add_child(_feed_cam)
	add_child(_feed_vp)
	_feed_rect = TextureRect.new()
	_feed_rect.texture = _feed_vp.get_texture()
	_feed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_feed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/cctv.gdshader")
	_feed_rect.material = fm
	_feed_rect.visible = false
	add_child(_feed_rect)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_map = Control.new()
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.visible = false
	_map.draw.connect(_draw_map)
	add_child(_map)
	visible = false


func reset() -> void:
	flash = 0.0
	_damage = 0.0
	_dmg_dirs.clear()
	_subs.clear()
	_toast_t = 0.0
	_banner_t = 0.0
	_alert = 0.0
	_alert_red = 0.0
	_vitals_a = 0.0
	_ammo_a = 0.0
	hints.reset()


# ------------------------------------------------------------------ events

func learn(id: String) -> void:
	hints.learn(id)


func hint_event(name: String) -> void:
	hints.event(name)


func trace_event(reason: String) -> void:
	_trace_reason = "LOGGED  ·  " + reason.to_upper()
	_trace_t = 3.0


## A small confirmation. Pass sound=false when the event already made its own noise.
func toast(text: String, sound := true) -> void:
	_toast = text
	_toast_t = 1.8
	if sound:
		Sfx.ui("toast", -10.0)


## A turning point, written large.
func banner(text: String, sound := true) -> void:
	_banner = text
	_banner_t = 3.2
	if sound:
		Sfx.ui("banner", -6.0)


## A spoken line, with who said it and whether it came over a radio.
func subtitle(who: String, text: String, radio := false) -> void:
	if not Settings.subtitles:
		return
	_subs.append({"who": who.to_upper(), "text": text, "t": 3.2, "radio": radio})
	if _subs.size() > 3:
		_subs.pop_front()


func on_damage(amount: float, from: Vector3) -> void:
	_damage = minf(1.0, _damage + amount / 25.0)
	_dmg_dirs.append({"pos": from, "t": 1.6})


func refresh(dt: float) -> void:
	var p := game.player
	_damage = maxf(0.0, _damage - dt * 1.2)
	flash = maxf(0.0, flash - dt * 0.45)
	_toast_t = maxf(0.0, _toast_t - dt)
	_banner_t = maxf(0.0, _banner_t - dt)
	for i in range(_subs.size() - 1, -1, -1):
		_subs[i].t = float(_subs[i].t) - dt
		if float(_subs[i].t) <= 0.0:
			_subs.remove_at(i)
	for i in range(_dmg_dirs.size() - 1, -1, -1):
		_dmg_dirs[i].t = float(_dmg_dirs[i].t) - dt
		if float(_dmg_dirs[i].t) <= 0.0:
			_dmg_dirs.remove_at(i)
	hints.update(dt)
	_trace_t = maxf(0.0, _trace_t - dt)
	var w := p.weapons
	var ammo_key := {"cur": w.cur, "mag": w.mag[w.cur], "sp": (w.spare[w.cur] as Array).size(), "id": w.current().id, "mode": w.mode[w.cur]}
	if ammo_key != _ammo_seen:
		_ammo_seen = ammo_key
		_ammo_a = 4.0
	var ammo_on := w.reload_t > 0.0 or p.ads > 0.5 or w.aiming_throw or w.mag[w.cur] <= w.current().mag_size * 0.25
	_ammo_a = maxf(1.0 if ammo_on else 0.0, _ammo_a - dt)
	var vit_on := p.hp < 70.0 or p.bleed > 0.0 or p.leg_wound or p.bandage_t >= 0.0 or p.last_hit < 4.0
	_vitals_a = minf(1.0, _vitals_a + dt * 4.0) if vit_on else maxf(0.0, _vitals_a - dt * 0.5)
	# the frame itself warms when someone is interested in you, reddens when they are sure
	var att := attention_items()
	var want := 0.0
	var red := 0.0
	if not att.is_empty():
		want = 1.0
		red = 1.0 if att[0][1] == RED else 0.0
	_alert = move_toward(_alert, want, dt * (2.0 if want > _alert else 0.6))
	_alert_red = move_toward(_alert_red, red, dt * 2.5)
	var open := game.tablet_access != null and game.console.phase == NetConsole.Phase.SHELL
	_feed_rect.visible = open
	_feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	if open:
		var ci: int = clampi(game.console.watch_cam, 0, game.cameras().size() - 1)
		var cam := game.cameras()[ci]
		_feed_cam.global_transform = cam.feed_transform()
		var sig := 0.0 if cam.destroyed or cam.disabled else 1.0
		(_feed_rect.material as ShaderMaterial).set_shader_parameter("signal", sig)
	_fx_mat.set_shader_parameter("suppression", p.supp)
	_fx_mat.set_shader_parameter("damage", _damage)
	_fx_mat.set_shader_parameter("low_health", clampf((30.0 - p.hp) / 30.0, 0.0, 1.0) * 0.6 if p.alive else 0.0)
	_fx_mat.set_shader_parameter("alert", _alert if p.alive else 0.0)
	_fx_mat.set_shader_parameter("alert_red", _alert_red)
	_flash_rect.color.a = minf(1.0, flash)
	var show_map := p.alive and not game.tablet_access and not p.is_scoped()
	_map.visible = show_map
	if show_map:
		var ms := 196.0
		_map.position = Vector2(_overlay.size.x - M - ms, M)
		_map.size = Vector2(ms, ms)
		_map.queue_redraw()
	_overlay.queue_redraw()


# ------------------------------------------------------------------ drawing helpers

func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, font: Font = null) -> float:
	var f := font if font else _f_label
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	_overlay.draw_string(f, Vector2(x + 1, pos.y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.55))
	_overlay.draw_string(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


func _width(text: String, size: int, font: Font = null) -> float:
	return (font if font else _f_label).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Tracked small capitals: the voice of every label on this screen.
func _micro(pos: Vector2, text: String, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	return _text(pos, text, 12, color, align, _f_micro)


func _rule(a: Vector2, b: Vector2, color: Color, width := 1.0) -> void:
	_overlay.draw_line(a, b, color, width)


## A thin vertical tick between groups of a line.
func _sep(x: float, y: float, alpha := 1.0) -> void:
	_overlay.draw_line(Vector2(x, y - 11), Vector2(x, y + 1), Color(INK, 0.18 * alpha), 1.0)


func _dot(pos: Vector2, color: Color, pulse := false) -> void:
	var a := 0.55 + 0.45 * absf(sin(game.time * 4.0)) if pulse else 1.0
	_overlay.draw_circle(pos, 2.6, Color(color, a))


func _cap_box(alpha: float) -> StyleBoxFlat:
	var k := roundi(alpha * 10.0)
	if not _caps.has(k):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.42 * alpha)
		sb.border_color = Color(INK, 0.62 * alpha)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		_caps[k] = sb
	return _caps[k]


func _keycap_width(glyph: String) -> float:
	return maxf(24.0, _f_label.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0)


func _keycap(pos: Vector2, glyph: String, alpha := 1.0) -> float:
	var w := _keycap_width(glyph)
	var r := Rect2(pos.x, pos.y - 17, w, 23)
	_overlay.draw_style_box(_cap_box(alpha), r)
	_text(Vector2(pos.x + w * 0.5, pos.y), glyph, 13, Color(INK, alpha), HORIZONTAL_ALIGNMENT_CENTER, _f_label)
	return w


## A row of key caps followed by a label; returns its width. dry=true measures only.
func _prompt_row(pos: Vector2, keys: Array, label: String, alpha: float, dry := false) -> float:
	var x := pos.x
	for k: String in keys:
		var g := Settings.glyph(k)
		if dry:
			x += _keycap_width(g) + 5
		else:
			x += _keycap(Vector2(x, pos.y), g, alpha) + 5
	if not keys.is_empty():
		x += 7
	var lw := _f_body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	if not dry:
		_text(Vector2(x, pos.y), label, 17, Color(INK, alpha), HORIZONTAL_ALIGNMENT_LEFT, _f_body)
	return x + lw - pos.x


func _screen_angle(world: Vector3) -> float:
	var cam := game.player.camera
	var local := cam.global_transform.affine_inverse() * world
	return atan2(local.x, -local.z) - PI / 2.0


## Three small arcs: a radio transmission.
func _radio_glyph(pos: Vector2, color: Color) -> void:
	for i in 3:
		_overlay.draw_arc(pos, 3.0 + i * 3.0, -PI * 0.75, -PI * 0.25, 8, Color(color, 1.0 - i * 0.25), 1.2)


# ------------------------------------------------------------------ the overlay

func _draw_overlay() -> void:
	var p := game.player
	var size := _overlay.size
	var c := size * 0.5
	if p.is_scoped():
		_draw_scope(size, c)
	if game.tablet_access:
		_draw_tablet(size)
	_draw_place(size)
	_draw_heading(size)
	_draw_attention(size)
	_draw_markers()
	if not game.tablet_access:
		_draw_guard_states()
	if p.alive and not game.tablet_access:
		_draw_sights(c)
		_draw_working(c)
	if not game.tablet_access:
		_draw_arcs(c)
	_draw_self(size)
	_draw_hands(size)
	_draw_prompts(size)
	if not game.tablet_access:
		_draw_hint(size)
	_draw_subtitles(size)
	if _toast_t > 0.0:
		_micro(Vector2(c.x, size.y * 0.40), _toast, Color(DIM, minf(1.0, _toast_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER)
	if _banner_t > 0.0:
		var a := minf(1.0, _banner_t * 2.0)
		var y := size.y * 0.28
		var w := _width(_banner, 30, _f_wide) + 60.0
		_rule(Vector2(c.x - w * 0.5, y - 36), Vector2(c.x + w * 0.5, y - 36), Color(INK, 0.35 * a))
		_rule(Vector2(c.x - w * 0.5, y + 12), Vector2(c.x + w * 0.5, y + 12), Color(INK, 0.35 * a))
		_text(Vector2(c.x + 6, y), _banner, 30, Color(INK, a), HORIZONTAL_ALIGNMENT_CENTER, _f_wide)


# --- top left: where you are, what the night is like

func _draw_place(size: Vector2) -> void:
	var a := game.facility.area_name(game.player.global_position)
	if a != _area:
		_area = a
		_area_t = 0.0
	_area_t += get_process_delta_time()
	var alpha := 1.0 if _area_t < 3.0 else maxf(0.6, 1.0 - (_area_t - 3.0))
	_text(Vector2(M, M), _area, 14, Color(INK, alpha), HORIZONTAL_ALIGNMENT_LEFT, _f_label)
	var secs := int(game.time)
	var x := M
	var y := M + 21.0
	x += _micro(Vector2(x, y), "%02d:%02d" % [secs / 60, secs % 60], Color(DIM, 0.8)) + 14.0
	for it: Array in site_items():
		_sep(x, y)
		x += 12.0
		var col: Color = it[1]
		if col == RED:
			_dot(Vector2(x + 3, y - 4.5), col, true)
			x += 12.0
		x += _micro(Vector2(x, y), it[0], col) + 14.0


# --- top centre: heading and objective

func _draw_heading(size: Vector2) -> void:
	var p := game.player
	var heading := atan2(-sin(p.yaw), -cos(p.yaw))
	var cx := size.x * 0.5
	var top := 38.0
	var R := 1500.0
	var ctr := Vector2(cx, top + R)
	var half_px := 240.0
	var half_a := half_px / R
	var span := deg_to_rad(150.0)
	# the tape: a faint arc with radial ticks that fade toward the ends; names ride above it
	var pts := PackedVector2Array()
	for i in 41:
		var a := -PI / 2.0 - half_a + 2.0 * half_a * i / 40.0
		pts.append(ctr + Vector2(cos(a), sin(a)) * R)
	_overlay.draw_polyline(pts, Color(INK, 0.22), 1.0)
	for deg in range(0, 360, 15):
		var rel := angle_difference(deg_to_rad(deg), heading)
		if absf(rel) > span / 2.0:
			continue
		var k := rel / (span / 2.0)
		var a := -PI / 2.0 + k * half_a
		var dir := Vector2(cos(a), sin(a))
		var fade := 1.0 - absf(k) * 0.8
		var card := deg % 90 == 0
		_rule(ctr + dir * (R - (7.0 if card else 3.0)), ctr + dir * (R + (4.0 if card else 2.0)), Color(INK, 0.8 * fade), 1.0)
		if card:
			_text(ctr + dir * (R + 14.0) + Vector2(0, -2), "NESW"[deg / 90], 14, Color(INK, fade), HORIZONTAL_ALIGNMENT_CENTER)
		elif deg % 45 == 0:
			_micro(ctr + dir * (R + 12.0) + Vector2(0, -2), str(deg), Color(DIM, fade), HORIZONTAL_ALIGNMENT_CENTER)
	# heading index, under the tape
	_overlay.draw_colored_polygon(PackedVector2Array([Vector2(cx, top + 4), Vector2(cx - 4, top + 11), Vector2(cx + 4, top + 11)]), INK)
	# objective: a diamond riding under the arc, a chevron when it is off the tape
	var tgt := game.objective_target()
	var orel := angle_difference(atan2(tgt.x - p.global_position.x, tgt.z - p.global_position.z), heading)
	var ok := clampf(orel / (span / 2.0), -1.0, 1.0)
	var oa := -PI / 2.0 + ok * half_a
	var odir := Vector2(cos(oa), sin(oa))
	var op := ctr + odir * (R - 22.0)
	if absf(orel) > span / 2.0:
		var s := signf(orel)
		_overlay.draw_polyline(PackedVector2Array([op + Vector2(-4 * s, -6), op + Vector2(3 * s, 0), op + Vector2(-4 * s, 6)]), AMBER, 1.8)
	else:
		_overlay.draw_colored_polygon(PackedVector2Array([op + Vector2(0, -6), op + Vector2(5, 0), op + Vector2(0, 6), op + Vector2(-5, 0)]), AMBER)
	var dist := Vector2(tgt.x - p.global_position.x, tgt.z - p.global_position.z).length()
	var label := game.objective_text()
	var dtxt := "%d M" % roundi(dist)
	var lw := _width(label, 13, _f_micro)
	var dw := _width(dtxt, 13, _f_micro)
	var y := top + 56.0
	var x0 := cx - (lw + 14.0 + dw) * 0.5
	_text(Vector2(x0, y), label, 13, INK, HORIZONTAL_ALIGNMENT_LEFT, _f_micro)
	_text(Vector2(x0 + lw + 14.0, y), dtxt, 13, AMBER, HORIZONTAL_ALIGNMENT_LEFT, _f_micro)
	# the copy, while it runs
	var lap := game.laptop()
	if lap and lap.copy_state == "copying":
		var bw := 150.0
		_overlay.draw_rect(Rect2(cx - bw * 0.5, y + 10, bw, 2), FAINT)
		_overlay.draw_rect(Rect2(cx - bw * 0.5, y + 10, bw * lap.copy_progress, 2), INK)
		_micro(Vector2(cx, y + 28), "COPYING  %d%%" % roundi(lap.copy_progress * 100.0), DIM, HORIZONTAL_ALIGNMENT_CENTER)
	elif lap and lap.copy_state == "done" and game.mission == "infil":
		_micro(Vector2(cx, y + 20), "COPY COMPLETE", GREEN, HORIZONTAL_ALIGNMENT_CENTER)


# --- top right: a heading-up plan of the compound, oriented to your view (forward is up)

func _draw_map() -> void:
	var p := game.player
	var ms := _map.size.x
	var center := Vector2(ms, ms) * 0.5
	_map.draw_rect(Rect2(0, 0, ms, ms), Color(0.02, 0.03, 0.05, 0.42))
	_map.draw_rect(Rect2(0, 0, ms, ms), Color(INK, 0.12), false, 1.0)
	var view := 42.0
	var scale := (ms * 0.5) / view
	var cy := cos(p.yaw)
	var sy := sin(p.yaw)
	var px := p.global_position.x
	var pz := p.global_position.z
	# world x-z to map: rotate so the player's forward points up and their right points right
	var w2m := func(wx: float, wz: float) -> Vector2:
		var dx := wx - px
		var dz := wz - pz
		return center + Vector2(dx * cy - dz * sy, dx * sy + dz * cy) * scale
	# structure
	for rr: Rect2 in game.facility.footprints:
		_map.draw_colored_polygon(PackedVector2Array([
			w2m.call(rr.position.x, rr.position.y),
			w2m.call(rr.position.x + rr.size.x, rr.position.y),
			w2m.call(rr.position.x + rr.size.x, rr.position.y + rr.size.y),
			w2m.call(rr.position.x, rr.position.y + rr.size.y)]), Color(INK, 0.17))
	# doors
	for d in game.facility.doors:
		_map.draw_circle(w2m.call(d.global_position.x, d.global_position.z), 2.0, GREEN if not d.secured() else Color(INK, 0.7))
	# cameras
	for dv in game.cameras():
		if dv.destroyed:
			continue
		var col := DIM
		if dv.camera_live():
			col = RED if dv.alarm else (AMBER if dv.aware > 0.1 else GREEN)
		var cc: Vector2 = w2m.call(dv.global_position.x, dv.global_position.z)
		_map.draw_rect(Rect2(cc - Vector2(2, 2), Vector2(4, 4)), col)
	# tracked guards, fading like their world markers
	for s in game.soldiers:
		if not s.alive or not s.tagged:
			continue
		var age := game.time - s.tag_seen_t
		var a := clampf(1.0 - (age - 10.0) / 10.0, 0.0, 0.85)
		if a <= 0.0:
			continue
		var gc := RED if s.state == Soldier.State.COMBAT else (AMBER if s.state == Soldier.State.SUSPICIOUS else INK)
		_map.draw_circle(w2m.call(s.tag_seen.x, s.tag_seen.z), 2.4, Color(gc, a))
	# objective
	var tgt := game.objective_target()
	var op: Vector2 = w2m.call(tgt.x, tgt.z)
	_map.draw_colored_polygon(PackedVector2Array([op + Vector2(0, -4), op + Vector2(4, 0), op + Vector2(0, 4), op + Vector2(-4, 0)]), AMBER)
	# the operator, fixed at centre, facing up
	_map.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6.5), center + Vector2(4.5, 4.5), center + Vector2(-4.5, 4.5)]), Color(1, 1, 1, 0.95))
	# a mark for north, swinging with your heading
	var nd := Vector2(-sy, cy)
	_map.draw_string(_f_micro, center + nd * (ms * 0.42) + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.55))


# --- the attention line: are you being noticed, and why

## What concerns you right now, most urgent first: [text, colour].
func attention_items() -> Array:
	var out := []
	var spotted := false
	var hunted := false
	var top: Soldier = null
	var camera_on := false
	var drone_tracking := false
	for s in game.soldiers:
		if not s.alive:
			continue
		if s.state == Soldier.State.COMBAT:
			hunted = true
			spotted = spotted or s.sees
		elif (s.state == Soldier.State.SUSPICIOUS or s.aware > 0.15) and s.notice != "" and (top == null or s.aware > top.aware):
			top = s
	for dv in game.facility.devices:
		if dv.camera_live() and dv.sees_player and dv.aware > 0.1:
			camera_on = true
	for dr in game.facility.drones:
		if dr.scanning() and dr.sees_player and dr.aware > 0.1:
			if dr.mode == Drone.Mode.TRACK:
				drone_tracking = true
			else:
				camera_on = true
	if spotted:
		out.append(["SPOTTED", RED])
	elif drone_tracking:
		out.append(["DRONE TRACKING YOU", RED])
	elif hunted:
		out.append(["THEY'RE SEARCHING", AMBER])
	elif top:
		var why: String = {"lit": "YOU'RE LIT", "close": "TOO CLOSE", "seen": "IN THEIR VIEW", "heard": "TOO LOUD"}.get(top.notice, "")
		out.append(["BEING NOTICED  ·  " + why, AMBER])
	if camera_on and not spotted and not drone_tracking:
		out.append(["EYES ON YOU", AMBER])
	return out


## The state of the site: [text, colour]. Quiet nights say so.
func site_items() -> Array:
	var out := []
	match game.hq.level:
		Command.Level.NORMAL:
			out.append(["SITE QUIET", Color(DIM, 0.8)])
		Command.Level.CAUTION:
			out.append(["SITE ON CAUTION", AMBER])
		Command.Level.ALARM:
			out.append(["ALARM", RED])
	if game.reinforce_t > 0.0:
		var t := ceili(game.reinforce_t)
		out.append(["REACTION FORCE  %d:%02d" % [t / 60, t % 60], RED])
	if game.comms_down:
		out.append(["THEIR RADIO IS DOWN", GREEN])
	if game.trace > 0.5 and not game.tablet_access:
		out.append(["TRACE  %d%%" % roundi(game.trace), RED if game.trace > 70.0 else DIM])
	return out


## Everything in one list, for the pause screen and tests.
func status_items() -> Array:
	var out := attention_items()
	for it: Array in site_items():
		if it[0] != "SITE QUIET":
			out.append(it)
	return out


func _draw_attention(size: Vector2) -> void:
	var items := attention_items()
	if items.is_empty():
		return
	var y := size.y * 0.5 - 150.0
	var gap := 26.0
	var total := 0.0
	var widths: Array[float] = []
	for it: Array in items:
		var w := 14.0 + _width(it[0], 13, _f_micro)
		widths.append(w)
		total += w
	total += gap * (items.size() - 1)
	var x := size.x * 0.5 - total * 0.5
	for i in items.size():
		var col: Color = items[i][1]
		_dot(Vector2(x + 3, y - 4.5), col, col == RED)
		_text(Vector2(x + 14, y), items[i][0], 13, col, HORIZONTAL_ALIGNMENT_LEFT, _f_micro)
		x += widths[i] + gap


# --- centre

## Over the heads of guards you can see: how aware each one is, and who is on the radio right now.
func _draw_guard_states() -> void:
	var cam := game.player.camera
	var eye := game.player.eye_pos()
	for s in game.soldiers:
		if not s.alive:
			continue
		var calling := s.radio_t > 0.0
		if s.state == Soldier.State.CALM and s.aware < 0.08 and not calling:
			continue
		var wp := s.head_pos() + Vector3.UP * 0.45
		if cam.is_position_behind(wp) or wp.distance_to(eye) > 50.0 or not game.los(eye, s.head_pos()):
			continue
		var sp := cam.unproject_position(wp)
		var tri := PackedVector2Array([sp + Vector2(0, 7), sp + Vector2(-7, -6), sp + Vector2(7, -6)])
		if s.state == Soldier.State.COMBAT:
			_overlay.draw_colored_polygon(tri, RED)
		else:
			var k := clampf(s.aware, 0.0, 1.0)
			var outline := tri.duplicate()
			outline.append(tri[0])
			_overlay.draw_polyline(outline, AMBER, 1.5)
			var top := lerpf(7.0, -6.0, k)
			var w := 7.0 * (1.0 - (top + 6.0) / 13.0)
			if w > 0.6:
				_overlay.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, 7), sp + Vector2(-w, top), sp + Vector2(w, top)]), Color(AMBER, 0.9))
		if calling:
			var left := clampf(s.radio_t / 4.0, 0.0, 1.0)
			_overlay.draw_arc(sp, 13.0, -PI / 2.0, -PI / 2.0 + TAU * left, 32, RED, 2.0)
			_micro(sp + Vector2(0, -20), "CALLING IT IN", RED, HORIZONTAL_ALIGNMENT_CENTER)


## Tracked guards out of sight: a hollow marker where you last saw them, fading over 20 s.
func _draw_markers() -> void:
	var cam := game.player.camera
	for s in game.soldiers:
		if not s.alive or not s.tagged:
			continue
		var age := game.time - s.tag_seen_t
		if age < 0.6:
			continue
		var a := clampf(1.0 - (age - 10.0) / 10.0, 0.0, 0.8)
		if a <= 0.0:
			continue
		var wp := s.tag_seen + Vector3.UP * 2.05
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var col := RED if s.state == Soldier.State.COMBAT else (AMBER if s.state == Soldier.State.SUSPICIOUS else INK)
		var pts := PackedVector2Array([sp + Vector2(0, -6), sp + Vector2(5, 0), sp + Vector2(0, 6), sp + Vector2(-5, 0), sp + Vector2(0, -6)])
		_overlay.draw_polyline(pts, Color(col, a), 1.5)
		_micro(sp + Vector2(0, -11), "%d M" % roundi(s.tag_seen.distance_to(game.player.global_position)), Color(col, 0.7 * a), HORIZONTAL_ALIGNMENT_CENTER)


## No crosshair: at the hip there is only a faint dot where the eye rests; aiming uses the
## weapon's own sights.
func _draw_sights(c: Vector2) -> void:
	var p := game.player
	var w := p.weapons
	if p.ads > 0.2 or p.sprinting or w.aiming_throw or w.reload_t > 0.0 or p.drag_body != null or p.vault_t >= 0.0 or p.bandage_t >= 0.0:
		return
	_overlay.draw_circle(c, 1.5, Color(1, 1, 1, 0.35 * (1.0 - p.ads * 5.0)))


## A ring that fills while you hold an interaction, named underneath.
func _draw_working(c: Vector2) -> void:
	var prog := 0.0
	var label := ""
	if game.use_target and game.using:
		prog = game.use_progress.get(game.use_target, 0.0)
		label = game.use_target.use_label(game)
	elif not game.tool_target.is_empty():
		prog = game.tool_progress
		label = game.tool_target.label
	if prog <= 0.0:
		return
	_overlay.draw_arc(c, 26.0, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 2.0)
	_overlay.draw_arc(c, 26.0, -PI / 2.0, -PI / 2.0 + TAU * prog, 48, AMBER, 2.5)
	_text(c + Vector2(0, 5), "%d" % roundi(prog * 100.0), 13, AMBER, HORIZONTAL_ALIGNMENT_CENTER, _f_label)
	_micro(c + Vector2(0, 48), label.to_upper().split("  ·  ")[0], DIM, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_arcs(c: Vector2) -> void:
	for d: Dictionary in _dmg_dirs:
		var a := _screen_angle(d.pos)
		_overlay.draw_arc(c, 130.0, a - 0.22, a + 0.22, 18, Color(1, 0.24, 0.16, minf(0.9, float(d.t))), 5.0)
	for s in game.soldiers:
		if not s.alive:
			continue
		var col: Color
		var amt := 1.0
		if s.state == Soldier.State.COMBAT:
			if not s.sees:
				continue
			col = RED
		elif s.aware > 0.03:
			amt = minf(1.0, s.aware)
			col = AMBER if s.state == Soldier.State.SUSPICIOUS else INK
		else:
			continue
		var a := _screen_angle(s.global_position + Vector3.UP * 1.5)
		_overlay.draw_arc(c, 100.0, a - 0.16, a + 0.16, 12, Color(col, 0.18), 3.0)
		_overlay.draw_arc(c, 100.0, a - 0.16 * amt, a + 0.16 * amt, 12, Color(col, 0.95), 3.0)
	for dr in game.facility.drones:
		if not dr.scanning() or dr.aware <= 0.03:
			continue
		var dcol := RED if dr.mode == Drone.Mode.TRACK else AMBER
		var damt := minf(1.0, dr.aware)
		var da := _screen_angle(dr.global_position)
		_overlay.draw_arc(c, 114.0, da - 0.1, da + 0.1, 10, Color(dcol, 0.18), 2.5)
		_overlay.draw_arc(c, 114.0, da - 0.1 * damt, da + 0.1 * damt, 10, Color(dcol, 0.95), 2.5)
	for dv in game.facility.devices:
		if not dv.camera_live():
			continue
		var col2: Color
		var amt2 := minf(1.0, dv.aware)
		if dv.alarm and dv.sees_player:
			col2 = RED
			amt2 = 1.0
		elif dv.aware > 0.03:
			col2 = AMBER
		else:
			continue
		var a2 := _screen_angle(dv.global_position)
		_overlay.draw_arc(c, 108.0, a2 - 0.12, a2 + 0.12, 10, Color(col2, 0.18), 2.5)
		_overlay.draw_arc(c, 108.0, a2 - 0.12 * amt2, a2 + 0.12 * amt2, 10, Color(col2, 0.95), 2.5)
	for g in game.gadgets:
		if g.type != "frag" or g.global_position.distance_to(game.player.global_position) > 11.0:
			continue
		var a := _screen_angle(g.global_position)
		var pos := c + Vector2(cos(a), sin(a)) * 165.0
		var blink := 1.0 if fmod(game.time * 10.0, 2.0) < 1.0 else 0.4
		_overlay.draw_circle(pos, 9.0, Color(RED if not g.owner_is_player else AMBER, blink))
		_text(pos + Vector2(0, 5), "!", 14, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, Style.bold)


# --- bottom left: how exposed you are, how hurt

## How far your footsteps carry, the way the guards compute it.
func _noise_reach() -> float:
	var p := game.player
	var loud := 11.0 if p.sprinting else (0.0 if p.crouched else (4.0 if p.speed_2d() > 1.0 else 0.0))
	if game.facility.in_duct(p.global_position) and p.speed_2d() > 0.4:
		loud = maxf(loud, 7.0)
	if game.hq.level == Command.Level.ALARM:
		loud *= 0.5
	return loud


func _draw_self(size: Vector2) -> void:
	var p := game.player
	var x := M
	var y := size.y - M
	# light: a short bar and a word
	var lit := game.player_light
	var light_txt := "IN SHADOW" if lit < 0.45 else ("LOW LIGHT" if lit < 0.7 else "LIT")
	var light_col := DIM if lit < 0.45 else (INK if lit < 0.7 else AMBER)
	var bw := 84.0
	_overlay.draw_rect(Rect2(x, y - 8, bw, 3), FAINT)
	_overlay.draw_rect(Rect2(x, y - 8, bw * clampf(lit, 0.04, 1.0), 3), Color(light_col, 0.95))
	x += bw + 12.0
	x += _micro(Vector2(x, y), light_txt, light_col) + 16.0
	# sound
	var reach := _noise_reach()
	var in_duct := game.facility.in_duct(p.global_position)
	var noise_txt := "QUIET"
	var noise_col := DIM
	if reach > 0.0:
		noise_txt = ("DUCT NOISE" if in_duct else "FOOTSTEPS") + "  %d M" % roundi(reach)
		noise_col = AMBER if reach >= 7.0 else INK
	_sep(x, y)
	x += 12.0
	x += _micro(Vector2(x, y), noise_txt, noise_col) + 16.0
	# stance
	var stance := "DRAGGING" if p.drag_body else ("CROUCHED" if p.crouched else ("SPRINTING" if p.sprinting else "STANDING"))
	if absf(p.lean_k) > 0.5:
		stance += "  ·  LEAN " + ("L" if p.lean_k < 0.0 else "R")
	_sep(x, y)
	x += 12.0
	_micro(Vector2(x, y), stance, DIM)
	# health and wounds, while they matter
	var a := clampf(_vitals_a, 0.0, 1.0)
	if a <= 0.01:
		return
	var low := p.hp < 30.0
	var col := Color(RED if low else INK, a)
	var hy := y - 40.0
	var nw := _text(Vector2(M, hy), str(ceili(p.hp)), 34, col, HORIZONTAL_ALIGNMENT_LEFT, _f_num)
	var bar := Rect2(M, hy + 8, 180, 3)
	_overlay.draw_rect(bar, Color(FAINT, FAINT.a * a))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * p.hp / Player.MAX_HP, bar.size.y)), col)
	if p.bleed > 0.0:
		var lost := minf(p.hp, p.bleed * 10.0) / Player.MAX_HP * bar.size.x
		var pulse := 0.45 + 0.4 * sin(game.time * 6.0)
		_overlay.draw_rect(Rect2(bar.position.x + bar.size.x * p.hp / Player.MAX_HP - lost, bar.position.y, lost, bar.size.y), Color(RED, pulse * a))
	var wx := M + nw + 16.0
	if p.bandage_t >= 0.0:
		wx += _micro(Vector2(wx, hy), "BANDAGING  %d%%" % roundi(p.bandage_t / Player.BANDAGE_TIME * 100.0), Color(AMBER, a)) + 14.0
	elif p.bleed > 0.0:
		wx += _micro(Vector2(wx, hy), "BLEEDING", Color(RED, a)) + 14.0
	if p.leg_wound:
		_micro(Vector2(wx, hy), "LEG WOUND", Color(AMBER, a))


# --- bottom right: what is in your hands

func _draw_hands(size: Vector2) -> void:
	var w := game.player.weapons
	var cur := w.current()
	var x := size.x - M
	var y := size.y - M
	# equipment, always: the one G throws carries the key
	if not w.gadgets.is_empty():
		var key := "%d:%s" % [w.gsel, w.gadget_info().get("type", "")]
		if key != _gadget_seen:
			if _gadget_seen != "":
				_gadget_flash = 1.2
			_gadget_seen = key
		_gadget_flash = maxf(0.0, _gadget_flash - get_process_delta_time())
		var gx := x
		for i in range(w.gadgets.size() - 1, -1, -1):
			var g: Dictionary = w.gadgets[i]
			var n := int(g.n)
			var sel := i == w.gsel
			var t := "%s  ×%d" % [Gadget.INFO[g.type].name, n]
			var col := AMBER if sel else DIM
			if n == 0:
				col = Color(col, 0.4)
			var tw := _width(t, 12, _f_micro)
			if sel:
				if _gadget_flash > 0.0:
					_overlay.draw_rect(Rect2(gx - tw - 6, y - 15, tw + 12, 21), Color(AMBER, 0.16 * _gadget_flash))
				_micro(Vector2(gx, y), t, col, HORIZONTAL_ALIGNMENT_RIGHT)
				_overlay.draw_rect(Rect2(gx - tw, y + 5, tw, 1.5), col)
				var glyph := Settings.glyph("gadget")
				var cw := _keycap_width(glyph)
				_keycap(Vector2(gx - tw - 10 - cw, y), glyph, 0.9)
				gx -= tw + cw + 10 + 24
			else:
				_micro(Vector2(gx, y), t, col, HORIZONTAL_ALIGNMENT_RIGHT)
				gx -= tw + 24
	# ammunition, while it matters
	var a := clampf(_ammo_a, 0.0, 1.0)
	if a <= 0.01:
		return
	var m: int = w.mag[w.cur]
	var col := Color(RED if m == 0 else (AMBER if m <= cur.mag_size * 0.25 else INK), a)
	var busy := w.reload_t > 0.0 and not w.tube_loading
	var ny := y - 44.0
	var nw := _text(Vector2(x, ny), "—" if busy else str(m), 40, col, HORIZONTAL_ALIGNMENT_RIGHT, _f_num)
	var sp: Array = w.spares()
	if cur.tube_fed:
		var n := w.loose_shells()
		_micro(Vector2(x - nw - 14, ny), "+%d SHELLS" % n if n > 0 else "NO SHELLS", Color(DIM if n > 0 else RED, a), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var px := x - nw - 14.0
		for i in range(sp.size() - 1, -1, -1):
			px -= 8.0
			var r := Rect2(px, ny - 18, 5, 18)
			_overlay.draw_rect(r, Color(INK, 0.4 * a), false, 1.0)
			var fill := float(sp[i]) / cur.mag_size
			_overlay.draw_rect(Rect2(r.position.x, r.end.y - r.size.y * fill, r.size.x, r.size.y * fill), Color(INK, a))
		if sp.is_empty():
			_micro(Vector2(x - nw - 14, ny), "NO SPARE MAGAZINES", Color(RED, a), HORIZONTAL_ALIGNMENT_RIGHT)
	var line := cur.display_name + "  ·  " + cur.caliber
	if cur.modes.size() > 1:
		line += "  ·  " + w.fire_mode()
	_micro(Vector2(x, y - 22), line, Color(DIM, a), HORIZONTAL_ALIGNMENT_RIGHT)


# --- prompts and hints

## Context: only what you can do right now.
func _prompts() -> Array:
	var p := game.player
	var w := p.weapons
	var out := []
	if not p.alive:
		return out
	if w.aiming_throw:
		out.append([["gadget"], "Release to throw %s  ·  aim the arc" % Gadget.INFO[w.gadget_info().type].name.to_lower()])
		out.append([["aim"], "Cancel"])
		return out
	if p.drag_body:
		out.append([["interact"], "Release to drop"])
		return out
	if p.bleed > 0.0 and p.bandage_t < 0.0 and p.bandages > 0:
		out.append([["bandage"], "Bandage  ·  %d left" % p.bandages])
	if game.tablet_access:
		return out
	if p.ladder:
		out.append([["move_forward", "move_back"], "Climb"])
		out.append([["interact"], "Let go"])
		return out
	if game.using and game.use_target:
		out.append([["interact"], "Keep holding  ·  " + game.use_target.use_label(game)])
		return out
	if game.use_target and not game.takedown_target():
		var u := game.use_target
		var instant := u.use_time(game) <= 1.0
		if u.can_use(game):
			out.append([["interact"], u.use_label(game) + ("" if instant else "  ·  hold")])
		else:
			out.append([[], u.use_label(game)])
	var t := game.takedown_target()
	var tool := game.tool_action()
	if t:
		out.append([["interact"], "Takedown"])
	elif not tool.is_empty():
		out.append([["interact"], tool.label + "  ·  hold"])
	else:
		var it := game.interact_target()
		if it:
			out.append([["interact"], it.label()])
		elif game.corpse_near():
			out.append([["interact"], "Hold to drag body"])
	if game.ladder_near() and not game.use_target and not game.takedown_target():
		out.append([["interact"], "Climb ladder"])
	if game.facility.in_duct(p.global_position + p.forward() * 0.9) and not p.crouched and not game.facility.in_duct(p.global_position):
		out.append([["crouch"], "Crouch to crawl in"])
	var dr := game.refused_door()
	if dr and game.tool_action().get("kind") != "splice":
		if not dr.reader_live():
			out.append([[], "%s  ·  reader dead, door stays locked" % dr.label])
		else:
			out.append([[], "%s  ·  needs %s access" % [dr.label, dr.access_name()]])
	var junk := game.useless_rounds_near()
	if junk:
		out.append([[], "%s rounds  ·  none of your weapons take them" % junk.caliber])
	if p.vault_ok:
		out.append([["jump"], "Vault"])
	if p.crouched and p.low_cover_ahead and p.ads < 0.3:
		out.append([["aim"], "Aim over cover"])
	if p.is_scoped():
		out.append([["sprint"], "Hold breath"])
	var cur := w.current()
	var sp: Array = w.spares()
	if w.reload_t <= 0.0 and w.mag[w.cur] <= cur.mag_size * 0.25 and not sp.is_empty() and (cur.tube_fed or int(sp.max()) > w.in_magazine()):
		out.append([["reload"], "Reload"])
	if w.cur == 0 and w.mag[0] == 0 and sp.is_empty():
		out.append([["sidearm"], "Sidearm"])
	return out.slice(0, 3)


func _draw_prompts(size: Vector2) -> void:
	var rows := _prompts()
	var y := size.y * 0.64
	for r: Array in rows:
		var wdt := _prompt_row(Vector2.ZERO, r[0], r[1], 1.0, true)
		_prompt_row(Vector2(size.x * 0.5 - wdt * 0.5, y), r[0], r[1], 1.0)
		y += 31.0


func _draw_hint(size: Vector2) -> void:
	var h := hints.current
	if h.is_empty():
		return
	var a := hints.alpha
	var x := M
	var y := size.y * 0.46
	var keys: Array = h.keys
	var wdt := _prompt_row(Vector2.ZERO, keys, h.text, a, true) if not keys.is_empty() else _f_body.get_string_size(h.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var r := Rect2(x - 14, y - 28, wdt + 28, 40)
	_overlay.draw_rect(r, Color(0.02, 0.03, 0.05, 0.5 * a))
	_overlay.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), Color(AMBER, a))
	if keys.is_empty():
		_text(Vector2(x, y), h.text, 17, Color(INK, a), HORIZONTAL_ALIGNMENT_LEFT, _f_body)
	else:
		_prompt_row(Vector2(x, y), keys, h.text, a)


## Who said what, newest at the bottom. Radio traffic carries the three-arc mark.
func _draw_subtitles(size: Vector2) -> void:
	var c := size * 0.5
	for i in _subs.size():
		var s: Dictionary = _subs[i]
		var a := clampf(float(s.t) / 0.4, 0.0, 1.0)
		var y := size.y - 128.0 - (_subs.size() - 1 - i) * 27.0
		var who: String = s.who
		var line: String = s.text
		var radio: bool = s.radio
		var ww := _width(who, 12, _f_micro) + (16.0 if radio else 0.0)
		var lw := _f_body.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var x := c.x - (ww + 12 + lw) * 0.5
		if radio:
			_radio_glyph(Vector2(x + 4, y - 1), Color(AMBER, a))
			x += 16.0
		_micro(Vector2(x, y), who, Color(AMBER, a))
		_text(Vector2(x + ww - (16.0 if radio else 0.0) + 12, y), line, 19, Color(INK, a), HORIZONTAL_ALIGNMENT_LEFT, _f_body)


# ------------------------------------------------------------------ the terminal

## The network terminal: a typed console on the left, the watched camera feed top-right, trace
## below it, and a live palette of what you can type. Self-documenting; nothing to memorise.
func _draw_tablet(size: Vector2) -> void:
	var con := game.console
	var cams := game.cameras()
	var w := minf(1060.0, size.x - 70.0)
	var h := w * 0.52
	var r := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 - 40.0, w, h)
	var feed_w := 376.0
	var con_w := w - feed_w - 28.0
	var fx := r.position.x + con_w + 20.0
	var feed := Rect2(fx, r.position.y, feed_w, feed_w * 0.56)
	# the camera feed is a real TextureRect drawn underneath this overlay, so paint the panel
	# background around it (not over it) or the live image would be hidden
	var panel := r.grow(16)
	_overlay.draw_rect(Rect2(panel.position, Vector2(feed.position.x - panel.position.x, panel.size.y)), Style.BG)
	_overlay.draw_rect(Rect2(Vector2(feed.position.x, panel.position.y), Vector2(panel.end.x - feed.position.x, feed.position.y - panel.position.y)), Style.BG)
	_overlay.draw_rect(Rect2(Vector2(feed.position.x, feed.end.y), Vector2(panel.end.x - feed.position.x, panel.end.y - feed.end.y)), Style.BG)
	_overlay.draw_rect(panel, Color(0.3, 0.9, 0.6, 0.16), false, 1.0)
	var logging_in := con.phase == NetConsole.Phase.LOGIN
	var state: String = {"badge": "BADGE LOGIN", "creds": "COVER LOGIN", "brute": "BRUTE FORCE"}.get(con.mode, "") if logging_in else ("ADMIN" if game.tablet_admin else "USER")
	var header := "OPERATOR NETTOP  //  %s  //  %s  //  %s" % [NetConsole._slug(game.tablet_access.label), NetConsole.SUBNET, state]
	_micro(r.position + Vector2(0, -24), header, AMBER if logging_in else GREEN)
	var mono := _f_label
	var line_h := 17.0
	var pal_h := 86.0
	var log_bottom := r.position.y + h - pal_h - 34.0
	var shown: Array = con.log.slice(maxi(0, con.log.size() - int((log_bottom - r.position.y - 8.0) / line_h)))
	var ly := r.position.y + 10.0
	for e: Dictionary in shown:
		_text(Vector2(r.position.x + 4, ly + 12), e.text, 13, _tag_color(e.tag), HORIZONTAL_ALIGNMENT_LEFT, mono)
		ly += line_h
	var iy := log_bottom + 6.0
	_rule(Vector2(r.position.x, iy), Vector2(r.position.x + con_w, iy), Color(1, 1, 1, 0.1))
	if logging_in:
		_draw_login(con, r, con_w, iy, feed, fx, feed_w, mono)
		return
	var prompt := NetConsole.PROMPT + ":~$ "
	_text(Vector2(r.position.x + 4, iy + 20), prompt, 13, GREEN, HORIZONTAL_ALIGNMENT_LEFT, mono)
	var pw := mono.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2(r.position.x + 4 + pw, iy + 20), con.input, 13, INK, HORIZONTAL_ALIGNMENT_LEFT, mono)
	if fmod(game.time, 1.0) < 0.5:
		var cx := r.position.x + 4 + pw + mono.get_string_size(con.input.substr(0, con.cursor), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_overlay.draw_rect(Rect2(cx, iy + 7, 7, 15), Color(GREEN, 0.8))
	var sugg := con.suggestions()
	var py := iy + 34.0
	_micro(Vector2(r.position.x + 4, py + 10), "COMMANDS", DIM)
	var sx := r.position.x + 4
	var swy := py + 28.0
	for item: Dictionary in sugg.slice(0, 10):
		var label2: String = item.text + ("  " + item.help if item.help != "" else "")
		var tw := mono.get_string_size(label2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		if sx + tw > r.position.x + con_w:
			sx = r.position.x + 4
			swy += 20.0
		_overlay.draw_rect(Rect2(sx, swy - 13, tw - 6, 18), Color(1, 1, 1, 0.05))
		_text(Vector2(sx + 5, swy), item.text, 12, AMBER if item.admin else INK, HORIZONTAL_ALIGNMENT_LEFT, mono)
		if item.help != "":
			var ox := mono.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0
			_text(Vector2(sx + 5 + ox, swy), item.help, 12, DIM, HORIZONTAL_ALIGNMENT_LEFT, mono)
		sx += tw
	_feed_rect.position = feed.position
	_feed_rect.size = feed.size
	_overlay.draw_rect(feed, Color(1, 1, 1, 0.15), false, 1.0)
	var ci: int = clampi(con.watch_cam, 0, cams.size() - 1)
	var secs := int(game.time) + 7_380
	_text(feed.position + Vector2(8, 16), "%s  02:%02d:%02d" % [cams[ci].label, (secs / 60) % 60, secs % 60], 12, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, mono)
	if fmod(game.time, 1.0) < 0.5:
		_overlay.draw_circle(feed.position + Vector2(feed.size.x - 14, 13), 4.0, RED)
	var ty := feed.end.y + 22.0
	_micro(Vector2(fx, ty - 6), "TRACE", DIM)
	var bar := Rect2(fx + 54, ty - 13, feed_w - 54, 4)
	_overlay.draw_rect(bar, Color(1, 1, 1, 0.1))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(game.trace / 100.0, 0.0, 1.0), 4)), RED if game.trace > 70.0 else AMBER)
	if _trace_t > 0.0:
		_micro(Vector2(fx, ty + 16), _trace_reason, Color(RED, minf(1.0, _trace_t)))
	_micro(Vector2(fx, feed.end.y + 48.0), "ESC DISCONNECT  ·  TAB COMPLETE  ·  ↑ HISTORY", DIM)


## The nettop working the login: a progress bar where the prompt will be, the attempt counter
## where the feed will be, and nothing to type yet.
func _draw_login(con: NetConsole, r: Rect2, con_w: float, iy: float, feed: Rect2, fx: float, feed_w: float, mono: Font) -> void:
	var k := con.login_progress()
	var what: String = {"badge": "PRESENTING BADGE", "creds": "TRYING THE COVER LOGIN", "brute": "BRUTE-FORCING  %d / %d" % [con.attempt_i, con.attempts.size()]}.get(con.mode, "")
	_micro(Vector2(r.position.x + 4, iy + 20), what, AMBER)
	var bar := Rect2(r.position.x + 4, iy + 30, con_w - 8, 4)
	_overlay.draw_rect(bar, Color(1, 1, 1, 0.1))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, 4)), AMBER)
	if con.mode == "brute":
		var left := maxf(0.0, con.login_dur - con.login_t)
		_micro(Vector2(r.position.x + 4, iy + 54), "%d s  ·  trace climbs with every miss" % ceili(left), DIM)
	_overlay.draw_rect(feed, Color(1, 1, 1, 0.15), false, 1.0)
	_text(feed.position + Vector2(8, 16), "NO SESSION", 12, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT, mono)
	var big := "%d" % roundi(k * 100.0) + "%"
	if con.mode == "brute":
		big = "%d" % con.attempt_i
	_text(feed.get_center() + Vector2(0, 14), big, 40, AMBER, HORIZONTAL_ALIGNMENT_CENTER, _f_label)
	_micro(feed.get_center() + Vector2(0, 40), "ATTEMPTS" if con.mode == "brute" else "HANDSHAKE", DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var ty := feed.end.y + 22.0
	_micro(Vector2(fx, ty - 6), "TRACE", DIM)
	var tbar := Rect2(fx + 54, ty - 13, feed_w - 54, 4)
	_overlay.draw_rect(tbar, Color(1, 1, 1, 0.1))
	_overlay.draw_rect(Rect2(tbar.position, Vector2(tbar.size.x * clampf(game.trace / 100.0, 0.0, 1.0), 4)), RED if game.trace > 70.0 else AMBER)
	if _trace_t > 0.0:
		_micro(Vector2(fx, ty + 16), _trace_reason, Color(RED, minf(1.0, _trace_t)))
	_micro(Vector2(fx, feed.end.y + 60.0), "ESC PULL THE CABLE", DIM)


func _tag_color(tag: String) -> Color:
	match tag:
		"green": return GREEN
		"amber": return AMBER
		"red": return RED
		"dim": return DIM
		"input": return Color(0.75, 0.85, 1.0)
	return INK


# ------------------------------------------------------------------ the scope

## Fill everything outside a circle with a colour (the scope housing).
func _mask_outside(size: Vector2, cc: Vector2, r: float, col: Color) -> void:
	_overlay.draw_rect(Rect2(0, 0, maxf(0.0, cc.x - r + 1), size.y), col)
	_overlay.draw_rect(Rect2(cc.x + r - 1, 0, maxf(0.0, size.x - (cc.x + r) + 1), size.y), col)
	for i in 72:
		var a0 := TAU * i / 72.0
		var a1 := TAU * (i + 1) / 72.0
		var p0 := Vector2(cc.x + cos(a0) * r, cc.y + sin(a0) * r)
		var p1 := Vector2(cc.x + cos(a1) * r, cc.y + sin(a1) * r)
		var edge := -1.0 if sin((a0 + a1) * 0.5) < 0.0 else size.y + 1.0
		_overlay.draw_colored_polygon(PackedVector2Array([p0, p1, Vector2(p1.x, edge), Vector2(p0.x, edge)]), col)


## Scope view. The reticle is where the round goes; the dark eye-box shadow drifts with head
## movement, sway and recoil, the way a real scope punishes a sloppy cheek weld.
func _draw_scope(size: Vector2, c: Vector2) -> void:
	var p := game.player
	var vm := p.viewmodel
	var r := size.y * 0.45
	var shift := Vector2(-vm.sway.x, vm.sway.y) * 2600.0
	shift += Vector2(sin(p.step_phase * PI), absf(cos(p.step_phase * PI))) * p.bob * 14.0
	shift += Vector2(0, vm.recoil * 900.0)
	shift = shift.limit_length(r * 0.35)
	var cc := c + shift
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	var inner := r * 0.32
	_overlay.draw_line(Vector2(c.x - inner, c.y), Vector2(c.x + inner, c.y), ink, 1.2)
	_overlay.draw_line(Vector2(c.x, c.y - inner), Vector2(c.x, c.y + inner), ink, 1.2)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_overlay.draw_line(c + d * inner, c + d * r * 1.4, ink, 5.0)
	for i in range(1, 4):
		var o := inner * i / 4.0
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
			var n := Vector2(-d.y, d.x)
			_overlay.draw_line(c + d * o - n * 4.0, c + d * o + n * 4.0, ink, 1.2)
	_overlay.draw_circle(c, 1.8, Color(1.0, 0.14, 0.06, 0.85))
	for i in 10:
		var k := i / 10.0
		_overlay.draw_arc(cc, r - 26.0 + k * 26.0, 0, TAU, 96, Color(0, 0, 0, 0.08 + k * 0.08), 3.2)
	_overlay.draw_arc(cc, r + 1.0, 0, TAU, 96, Color(0.55, 0.65, 0.8, 0.12), 1.5)
	_mask_outside(size, cc, r, Color.BLACK)
	var bw := 180.0
	var by := size.y * 0.93
	_overlay.draw_rect(Rect2(c.x - bw / 2, by, bw, 2), Color(1, 1, 1, 0.12))
	_overlay.draw_rect(Rect2(c.x - bw / 2, by, bw * p.breath / Player.BREATH, 2), RED if p.breath_out > 0.0 else DIM)
