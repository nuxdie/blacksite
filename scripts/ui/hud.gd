class_name Hud
extends CanvasLayer
## Minimal in-game interface. Everything is drawn on one overlay: compass, sights, awareness and
## damage cues, vitals, ammunition, contextual key prompts, one-time tips and radio subtitles.

var game: Game
var flash := 0.0
var hints := Hints.new()

var _fx: ColorRect
var _fx_mat: ShaderMaterial
var _flash_rect: ColorRect
var _overlay: Control
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
## Vitals and ammunition stay out of the way until they matter.
var _vitals_a := 0.0
var _ammo_a := 0.0
var _ammo_seen := {}
var _area := ""
var _gadget_seen := ""
var _gadget_flash := 0.0
var _area_t := 0.0

var _f_small: FontVariation
var _f_label: FontVariation
var _f_wide: FontVariation
var _f_big: Font
var _f_num: Font


func _ready() -> void:
	layer = 1
	hints.game = game
	_f_small = Style.spaced(Style.semibold, 2)
	_f_label = Style.spaced(Style.semibold, 3)
	_f_wide = Style.spaced(Style.bold, 10)
	_f_big = Style.bold
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
	visible = false


func reset() -> void:
	flash = 0.0
	_damage = 0.0
	_dmg_dirs.clear()
	_subs.clear()
	_toast_t = 0.0
	_banner_t = 0.0
	hints.reset()


# ------------------------------------------------------------------ events

func learn(id: String) -> void:
	hints.learn(id)


func hint_event(name: String) -> void:
	hints.event(name)


func trace_event(reason: String) -> void:
	_trace_reason = "LOGGED: " + reason.to_upper()
	_trace_t = 3.0


func toast(text: String) -> void:
	_toast = text
	_toast_t = 1.6


func banner(text: String) -> void:
	_banner = text
	_banner_t = 3.0


func subtitle(who: String, text: String) -> void:
	_subs.append({"who": who, "text": text, "t": 2.8})
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
	var open := game.tablet_access != null
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
	_flash_rect.color.a = minf(1.0, flash)
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
	var shadow := Color(0, 0, 0, color.a * 0.6)
	_overlay.draw_string(f, Vector2(x + 1, pos.y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	_overlay.draw_string(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


func _keycap_width(glyph: String) -> float:
	return maxf(24.0, _f_small.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0)


func _keycap(pos: Vector2, glyph: String, alpha := 1.0) -> float:
	var w := _keycap_width(glyph)
	var r := Rect2(pos.x, pos.y - 17, w, 23)
	_overlay.draw_rect(r, Color(0, 0, 0, 0.35 * alpha))
	_overlay.draw_rect(r, Color(Style.INK, 0.85 * alpha), false, 1.5)
	_text(Vector2(pos.x + w * 0.5, pos.y), glyph, 14, Color(Style.INK, alpha), HORIZONTAL_ALIGNMENT_CENTER, _f_small)
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
	x += 6
	var lw := _f_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	if not dry:
		_text(Vector2(x, pos.y), label, 16, Color(Style.INK, alpha))
	return x + lw - pos.x


func _screen_angle(world: Vector3) -> float:
	var cam := game.player.camera
	var local := cam.global_transform.affine_inverse() * world
	return atan2(local.x, -local.z) - PI / 2.0


# ------------------------------------------------------------------ the overlay

func _draw_overlay() -> void:
	var p := game.player
	var size := _overlay.size
	var c := size * 0.5
	if p.is_scoped():
		_draw_scope(size, c)
	if game.tablet_access:
		_draw_tablet(size)
	_draw_compass(size)
	_draw_area()
	_draw_status(size)
	_draw_markers()
	if not game.tablet_access:
		_draw_guard_states()
	if p.alive and not game.tablet_access:
		_draw_sights(c)
		_draw_hack(c)
	if not game.tablet_access:
		_draw_arcs(c)
	_draw_vitals(size)
	_draw_ammo(size)
	_draw_gadgets(size)
	_draw_prompts(size)
	if not game.tablet_access:
		_draw_hint(size)
	for i in _subs.size():
		var s: Dictionary = _subs[i]
		var a := clampf(float(s.t) / 0.4, 0.0, 1.0)
		var y := size.y - 120.0 - (_subs.size() - 1 - i) * 26.0
		var who: String = s.who
		var line: String = s.text
		var ww := _f_small.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var lw := Style.semibold.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var x := c.x - (ww + 10 + lw) * 0.5
		_text(Vector2(x, y), who, 14, Color(Style.AMBER, a), HORIZONTAL_ALIGNMENT_LEFT, _f_small)
		_text(Vector2(x + ww + 10, y), line, 19, Color(Style.INK, a), HORIZONTAL_ALIGNMENT_LEFT, Style.semibold)
	if _toast_t > 0.0:
		_text(Vector2(c.x, size.y * 0.36), _toast, 15, Color(Style.DIM, minf(1.0, _toast_t * 3.0)), HORIZONTAL_ALIGNMENT_CENTER)
	if _banner_t > 0.0:
		_text(Vector2(c.x, size.y * 0.3), _banner, 30, Color(Style.INK, minf(1.0, _banner_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, _f_wide)


func _draw_compass(size: Vector2) -> void:
	var p := game.player
	var heading := atan2(-sin(p.yaw), -cos(p.yaw))
	var cw := 420.0
	var cx := size.x * 0.5
	var y := 30.0
	var span := PI * 0.75
	for deg in range(0, 360, 15):
		var rel := angle_difference(heading, deg_to_rad(deg))
		if absf(rel) > span / 2.0:
			continue
		var x := cx + rel / (span / 2.0) * cw / 2.0
		var a := 1.0 - absf(rel) / (span / 2.0) * 0.85
		var card := deg % 90 == 0
		_overlay.draw_line(Vector2(x, y - (7.0 if card else 4.0)), Vector2(x, y + 2), Color(Style.INK, a * 0.8), 1.0)
		if card:
			_text(Vector2(x, y + 19), "NESW"[deg / 90], 14, Color(Style.INK, a), HORIZONTAL_ALIGNMENT_CENTER)
		elif deg % 45 == 0:
			_text(Vector2(x, y + 17), str(deg), 11, Color(Style.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, _f_small)
	_overlay.draw_line(Vector2(cx, y - 18), Vector2(cx, y - 10), Style.INK, 2.0)
	var tgt := game.objective_target()
	var orel := angle_difference(heading, atan2(tgt.x - p.global_position.x, tgt.z - p.global_position.z))
	var ox := cx + clampf(orel / (span / 2.0), -1.0, 1.0) * cw / 2.0
	_overlay.draw_colored_polygon(PackedVector2Array([Vector2(ox, y - 13), Vector2(ox + 6, y - 7), Vector2(ox, y - 1), Vector2(ox - 6, y - 7)]), Style.AMBER)
	var dist := Vector2(tgt.x - p.global_position.x, tgt.z - p.global_position.z).length()
	var label := game.objective_text()
	var lw := _f_label.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var dtxt := "  %dm" % roundi(dist)
	var dw := _f_label.get_string_size(dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(Vector2(cx - (lw + dw) * 0.5, y + 44), label, 14, Style.INK)
	_text(Vector2(cx - (lw + dw) * 0.5 + lw, y + 44), dtxt, 14, Style.AMBER)


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
			_overlay.draw_colored_polygon(tri, Style.RED)
		else:
			var k := clampf(s.aware, 0.0, 1.0)
			var outline := tri.duplicate()
			outline.append(tri[0])
			_overlay.draw_polyline(outline, Style.AMBER, 1.5)
			var top := lerpf(7.0, -6.0, k)
			var w := 7.0 * (1.0 - (top + 6.0) / 13.0)
			if k > 0.02:
				_overlay.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, 7), sp + Vector2(-w, top), sp + Vector2(w, top)]), Color(Style.AMBER, 0.9))
		if calling:
			var left := clampf(s.radio_t / 4.0, 0.0, 1.0)
			_overlay.draw_arc(sp, 13.0, -PI / 2.0, -PI / 2.0 + TAU * left, 32, Style.RED, 2.0)
			_text(sp + Vector2(0, -18), "CALLING IT IN", 12, Style.RED, HORIZONTAL_ALIGNMENT_CENTER, _f_small)


## Tracked guards out of sight: a hollow marker where you last saw them, fading over 20 s.
## Guards in plain view need no marker.
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
		var col := Style.RED if s.state == Soldier.State.COMBAT else (Style.AMBER if s.state == Soldier.State.SUSPICIOUS else Style.INK)
		var pts := PackedVector2Array([sp + Vector2(0, -6), sp + Vector2(5, 0), sp + Vector2(0, 6), sp + Vector2(-5, 0), sp + Vector2(0, -6)])
		_overlay.draw_polyline(pts, Color(col, a), 1.5)
		_text(sp + Vector2(0, -10), "%dm" % roundi(s.tag_seen.distance_to(game.player.global_position)), 11, Color(col, 0.7 * a), HORIZONTAL_ALIGNMENT_CENTER, _f_small)


## No crosshair: at the hip there is only a faint dot where the eye rests; aiming uses the
## weapon's own sights.
func _draw_sights(c: Vector2) -> void:
	var p := game.player
	var w := p.weapons
	if p.ads > 0.2 or p.sprinting or w.aiming_throw or w.reload_t > 0.0 or p.drag_body != null or p.vault_t >= 0.0 or p.bandage_t >= 0.0:
		return
	_overlay.draw_circle(c, 1.5, Color(1, 1, 1, 0.35 * (1.0 - p.ads * 5.0)))


func _draw_hack(c: Vector2) -> void:
	var prog := 0.0
	if game.use_target:
		prog = game.use_progress.get(game.use_target, 0.0)
	elif not game.tool_target.is_empty():
		prog = game.tool_progress
	if prog > 0.0:
		_overlay.draw_arc(c, 26.0, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 3.0)
		_overlay.draw_arc(c, 26.0, -PI / 2.0, -PI / 2.0 + TAU * prog, 48, Style.AMBER, 3.0)
		_text(c + Vector2(0, 5), "%d" % roundi(prog * 100.0), 14, Style.AMBER, HORIZONTAL_ALIGNMENT_CENTER, _f_small)


## Where you are: named when you arrive, then it settles to a quiet label.
func _draw_area() -> void:
	var a := game.facility.area_name(game.player.global_position)
	if a != _area:
		_area = a
		_area_t = 0.0
	_area_t += get_process_delta_time()
	var alpha := 1.0 if _area_t < 3.0 else maxf(0.45, 1.0 - (_area_t - 3.0))
	_text(Vector2(34, 36), _area, 14, Color(Style.INK, alpha), HORIZONTAL_ALIGNMENT_LEFT, _f_label)


## The state of the night in one line under the objective: are you seen, how alert is the site,
## and anything running in the background. Nothing shows while all is quiet.
func status_items() -> Array:
	var out := []
	var spotted := false
	var hunted := false
	var top: Soldier = null
	var camera_on := false
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
	var drone_tracking := false
	for dr in game.facility.drones:
		if dr.scanning() and dr.sees_player and dr.aware > 0.1:
			if dr.mode == Drone.Mode.TRACK:
				drone_tracking = true
			else:
				camera_on = true
	if spotted:
		out.append(["SPOTTED", Style.RED])
	elif hunted:
		out.append(["THEY'RE SEARCHING", Style.AMBER])
	elif top:
		var why: String = {"lit": "YOU'RE LIT", "close": "TOO CLOSE", "seen": "IN THEIR VIEW", "heard": "TOO LOUD"}.get(top.notice, "")
		out.append(["BEING NOTICED  ·  " + why, Style.AMBER])
	if drone_tracking:
		out.append(["DRONE TRACKING YOU", Style.RED])
	elif camera_on and not spotted:
		out.append(["EYES ON YOU", Style.AMBER])
	match game.hq.level:
		Command.Level.CAUTION:
			out.append(["SITE ON CAUTION", Style.AMBER])
		Command.Level.ALARM:
			out.append(["ALARM", Style.RED])
	if game.reinforce_t > 0.0:
		var t := ceili(game.reinforce_t)
		out.append(["REACTION FORCE  %d:%02d" % [t / 60, t % 60], Style.RED])
	if game.comms_down:
		out.append(["THEIR RADIO IS DOWN", Style.GREEN])
	var lap := _laptop()
	if lap and lap.copy_state == "copying":
		out.append(["COPYING  %d%%" % roundi(lap.copy_progress * 100.0), Style.INK])
	elif lap and lap.copy_state == "done" and game.mission == "infil":
		out.append(["COPY COMPLETE", Style.GREEN])
	if game.trace > 0.5 and not game.tablet_access:
		out.append(["TRACE  %d%%" % roundi(game.trace), Style.RED if game.trace > 70.0 else Style.DIM])
	return out


func _draw_status(size: Vector2) -> void:
	var items := status_items()
	if items.is_empty():
		return
	var gap := 22.0
	var widths: Array[float] = []
	var total := 0.0
	for it: Array in items:
		var w := 12.0 + _f_small.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		widths.append(w)
		total += w
	total += gap * (items.size() - 1)
	var x := size.x * 0.5 - total * 0.5
	var y := 98.0
	for i in items.size():
		var col: Color = items[i][1]
		var pulse := 0.55 + 0.45 * absf(sin(game.time * 4.0)) if col == Style.RED else 1.0
		_overlay.draw_circle(Vector2(x + 3, y - 4.5), 3.0, Color(col, pulse))
		_text(Vector2(x + 12, y), items[i][0], 14, col, HORIZONTAL_ALIGNMENT_LEFT, _f_small)
		x += widths[i] + gap


func _laptop() -> Device:
	for dv in game.facility.devices:
		if dv.kind == Device.Kind.LAPTOP:
			return dv
	return null


## The security tablet: camera list, the live feed, and what each action will cost you.
## The network terminal: a typed console on the left, the watched camera feed top-right, trace
## below it, and a live palette of what you can type. Self-documenting; nothing to memorise.
func _draw_tablet(size: Vector2) -> void:
	var con := game.console
	var cams := game.cameras()
	var w := minf(1060.0, size.x - 70.0)
	var h := w * 0.52
	var r := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 - 40.0, w, h)
	_overlay.draw_rect(r.grow(14), Style.BG)
	_overlay.draw_rect(r.grow(14), Color(0.3, 0.9, 0.6, 0.18), false, 1.0)
	var feed_w := 376.0
	var con_w := w - feed_w - 28.0
	var header := "SECURITY NETWORK  //  %s  //  %s" % [NetConsole._slug(game.tablet_access.label), "ADMIN" if game.tablet_admin else "GUEST"]
	_text(r.position + Vector2(0, -20), header, 14, Style.GREEN, HORIZONTAL_ALIGNMENT_LEFT, _f_small)
	# console log
	var mono := _f_small
	var line_h := 17.0
	var pal_h := 86.0
	var log_bottom := r.position.y + h - pal_h - 34.0
	var shown: Array = con.log.slice(maxi(0, con.log.size() - int((log_bottom - r.position.y - 8.0) / line_h)))
	var ly := r.position.y + 10.0
	for e: Dictionary in shown:
		_text(Vector2(r.position.x + 4, ly + 12), e.text, 13, _tag_color(e.tag), HORIZONTAL_ALIGNMENT_LEFT, mono)
		ly += line_h
	# input line with cursor
	var iy := log_bottom + 6.0
	_overlay.draw_line(Vector2(r.position.x, iy), Vector2(r.position.x + con_w, iy), Color(1, 1, 1, 0.1), 1.0)
	var prompt := NetConsole.PROMPT + ":~$ "
	_text(Vector2(r.position.x + 4, iy + 20), prompt, 13, Style.GREEN, HORIZONTAL_ALIGNMENT_LEFT, mono)
	var pw := mono.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2(r.position.x + 4 + pw, iy + 20), con.input, 13, Style.INK, HORIZONTAL_ALIGNMENT_LEFT, mono)
	if fmod(game.time, 1.0) < 0.5:
		var cx := r.position.x + 4 + pw + mono.get_string_size(con.input.substr(0, con.cursor), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_overlay.draw_rect(Rect2(cx, iy + 7, 7, 15), Color(Style.GREEN, 0.8))
	# palette of valid next tokens
	var sugg := con.suggestions()
	var py := iy + 34.0
	_text(Vector2(r.position.x + 4, py + 10), "AVAILABLE", 11, Style.DIM, HORIZONTAL_ALIGNMENT_LEFT, mono)
	var sx := r.position.x + 4
	var swy := py + 28.0
	for item: Dictionary in sugg.slice(0, 10):
		var label2: String = item.text + ("  " + item.help if item.help != "" else "")
		var tw := mono.get_string_size(label2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		if sx + tw > r.position.x + con_w:
			sx = r.position.x + 4
			swy += 20.0
		var box := Rect2(sx, swy - 13, tw - 6, 18)
		_overlay.draw_rect(box, Color(1, 1, 1, 0.05))
		_text(Vector2(sx + 5, swy), item.text, 12, Style.AMBER if item.admin else Style.INK, HORIZONTAL_ALIGNMENT_LEFT, mono)
		if item.help != "":
			var ox := mono.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0
			_text(Vector2(sx + 5 + ox, swy), item.help, 12, Style.DIM, HORIZONTAL_ALIGNMENT_LEFT, mono)
		sx += tw
	# feed panel on the right
	var fx := r.position.x + con_w + 20.0
	var feed := Rect2(fx, r.position.y, feed_w, feed_w * 0.56)
	_feed_rect.position = feed.position
	_feed_rect.size = feed.size
	_overlay.draw_rect(feed, Color(1, 1, 1, 0.15), false, 1.0)
	var ci: int = clampi(con.watch_cam, 0, cams.size() - 1)
	var secs := int(game.time) + 7_380
	_text(feed.position + Vector2(8, 16), "%s  02:%02d:%02d" % [cams[ci].label, (secs / 60) % 60, secs % 60], 12, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, mono)
	if fmod(game.time, 1.0) < 0.5:
		_overlay.draw_circle(feed.position + Vector2(feed.size.x - 14, 13), 4.0, Style.RED)
	# trace bar under the feed
	var ty := feed.end.y + 22.0
	_text(Vector2(fx, ty - 6), "TRACE", 12, Style.DIM, HORIZONTAL_ALIGNMENT_LEFT, mono)
	var bar := Rect2(fx + 54, ty - 14, feed_w - 54, 6)
	_overlay.draw_rect(bar, Color(1, 1, 1, 0.1))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(game.trace / 100.0, 0.0, 1.0), 6)), Style.RED if game.trace > 70.0 else Style.AMBER)
	if _trace_t > 0.0:
		_text(Vector2(fx, ty + 16), _trace_reason, 12, Color(Style.RED, minf(1.0, _trace_t)), HORIZONTAL_ALIGNMENT_LEFT, mono)
	_text(Vector2(fx, feed.end.y + 48.0), "ESC disconnect  ·  Tab complete  ·  ↑ history", 12, Style.DIM, HORIZONTAL_ALIGNMENT_LEFT, mono)


func _tag_color(tag: String) -> Color:
	match tag:
		"green": return Style.GREEN
		"amber": return Style.AMBER
		"red": return Style.RED
		"dim": return Style.DIM
		"input": return Color(0.75, 0.85, 1.0)
	return Style.INK


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
			col = Style.RED
		elif s.aware > 0.03:
			amt = minf(1.0, s.aware)
			col = Style.AMBER if s.state == Soldier.State.SUSPICIOUS else Style.INK
		else:
			continue
		var a := _screen_angle(s.global_position + Vector3.UP * 1.5)
		_overlay.draw_arc(c, 100.0, a - 0.16, a + 0.16, 12, Color(col, 0.18), 4.0)
		_overlay.draw_arc(c, 100.0, a - 0.16 * amt, a + 0.16 * amt, 12, Color(col, 0.95), 4.0)
	for dr in game.facility.drones:
		if not dr.scanning() or dr.aware <= 0.03:
			continue
		var dcol := Style.RED if dr.mode == Drone.Mode.TRACK else Style.AMBER
		var damt := minf(1.0, dr.aware)
		var da := _screen_angle(dr.global_position)
		_overlay.draw_arc(c, 114.0, da - 0.1, da + 0.1, 10, Color(dcol, 0.18), 3.0)
		_overlay.draw_arc(c, 114.0, da - 0.1 * damt, da + 0.1 * damt, 10, Color(dcol, 0.95), 3.0)
	for dv in game.facility.devices:
		if not dv.camera_live():
			continue
		var col2: Color
		var amt2 := minf(1.0, dv.aware)
		if dv.alarm and dv.sees_player:
			col2 = Style.RED
			amt2 = 1.0
		elif dv.aware > 0.03:
			col2 = Style.AMBER
		else:
			continue
		var a2 := _screen_angle(dv.global_position)
		_overlay.draw_arc(c, 108.0, a2 - 0.12, a2 + 0.12, 10, Color(col2, 0.18), 3.0)
		_overlay.draw_arc(c, 108.0, a2 - 0.12 * amt2, a2 + 0.12 * amt2, 10, Color(col2, 0.95), 3.0)
	for g in game.gadgets:
		if g.type != "frag" or g.global_position.distance_to(game.player.global_position) > 11.0:
			continue
		var a := _screen_angle(g.global_position)
		var pos := c + Vector2(cos(a), sin(a)) * 165.0
		var blink := 1.0 if fmod(game.time * 10.0, 2.0) < 1.0 else 0.4
		_overlay.draw_circle(pos, 9.0, Color(Style.RED if not g.owner_is_player else Style.AMBER, blink))
		_text(pos + Vector2(0, 5), "!", 14, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, Style.bold)


func _draw_vitals(size: Vector2) -> void:
	var p := game.player
	var x := 34.0
	var y := size.y - 34.0
	# always: how visible you are and how you're standing
	var lit := game.player_light
	var light_txt := "IN SHADOW" if lit < 0.45 else ("LOW LIGHT" if lit < 0.7 else "LIT")
	var light_col := Style.DIM if lit < 0.45 else (Style.INK if lit < 0.7 else Style.AMBER)
	for i in 5:
		var on := lit >= 0.22 + i * 0.18
		_overlay.draw_rect(Rect2(x + i * 7.0, y - 4.0, 5, 8), Color(light_col, 0.9) if on else Style.FAINT)
	var bx := x + 44.0
	bx += _text(Vector2(bx, y + 4), light_txt, 14, light_col, HORIZONTAL_ALIGNMENT_LEFT, _f_small) + 14.0
	var stance := "DRAGGING" if p.drag_body else ("CROUCHED" if p.crouched else ("SPRINTING" if p.sprinting else "STANDING"))
	if absf(p.lean_k) > 0.5:
		stance += "  ·  LEAN " + ("L" if p.lean_k < 0.0 else "R")
	_text(Vector2(bx, y + 4), stance, 14, Style.DIM, HORIZONTAL_ALIGNMENT_LEFT, _f_small)
	# health and wounds, while they matter
	var a := clampf(_vitals_a, 0.0, 1.0)
	if a <= 0.01:
		return
	var low := p.hp < 30.0
	var col := Color(Style.RED if low else Style.INK, a)
	_text(Vector2(x, y - 40), str(ceili(p.hp)), 34, col, HORIZONTAL_ALIGNMENT_LEFT, _f_num)
	var bar := Rect2(x, y - 28, 220, 4)
	_overlay.draw_rect(bar, Color(Style.FAINT, Style.FAINT.a * a))
	_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * p.hp / Player.MAX_HP, bar.size.y)), col)
	if p.bleed > 0.0:
		var lost := minf(p.hp, p.bleed * 10.0) / Player.MAX_HP * bar.size.x
		var pulse := 0.45 + 0.4 * sin(game.time * 6.0)
		_overlay.draw_rect(Rect2(bar.position.x + bar.size.x * p.hp / Player.MAX_HP - lost, bar.position.y, lost, bar.size.y), Color(Style.RED, pulse * a))
	var wx := x + 70.0
	if p.bandage_t >= 0.0:
		wx += _text(Vector2(wx, y - 40), "BANDAGING  %d%%" % roundi(p.bandage_t / Player.BANDAGE_TIME * 100.0), 14, Color(Style.AMBER, a), HORIZONTAL_ALIGNMENT_LEFT, _f_small) + 14.0
	elif p.bleed > 0.0:
		wx += _text(Vector2(wx, y - 40), "BLEEDING", 14, Color(Style.RED, a), HORIZONTAL_ALIGNMENT_LEFT, _f_small) + 14.0
	if p.leg_wound:
		_text(Vector2(wx, y - 40), "LEG WOUND", 14, Color(Style.AMBER, a), HORIZONTAL_ALIGNMENT_LEFT, _f_small)


func _draw_ammo(size: Vector2) -> void:
	var w := game.player.weapons
	var cur := w.current()
	var a := clampf(_ammo_a, 0.0, 1.0)
	if a <= 0.01:
		return
	var x := size.x - 34.0
	var y := size.y - 34.0
	var m: int = w.mag[w.cur]
	var col := Color(Style.RED if m == 0 else (Style.AMBER if m <= cur.mag_size * 0.25 else Style.INK), a)
	var busy := w.reload_t > 0.0 and not w.tube_loading
	_text(Vector2(x, y - 26), "—" if busy else str(m), 42, col, HORIZONTAL_ALIGNMENT_RIGHT, _f_num)
	var sp: Array = w.spares()
	if cur.tube_fed:
		var n := w.loose_shells()
		_text(Vector2(x, y - 6), "+%d SHELLS" % n if n > 0 else "NO SHELLS", 12, Color(Style.DIM if n > 0 else Style.RED, a), HORIZONTAL_ALIGNMENT_RIGHT, _f_small)
	else:
		var px := x
		for i in range(sp.size() - 1, -1, -1):
			px -= 9.0
			var r := Rect2(px, y - 18, 6, 14)
			_overlay.draw_rect(r, Color(Style.INK, 0.5 * a), false, 1.0)
			var fill := float(sp[i]) / cur.mag_size
			_overlay.draw_rect(Rect2(r.position.x, r.end.y - r.size.y * fill, r.size.x, r.size.y * fill), Color(Style.INK, a))
		if sp.is_empty():
			_text(Vector2(x, y - 6), "NO SPARE MAGAZINES", 12, Color(Style.RED, a), HORIZONTAL_ALIGNMENT_RIGHT, _f_small)
	var line := cur.display_name + "  ·  " + cur.caliber
	if cur.modes.size() > 1:
		line += "  ·  " + w.fire_mode()
	_text(Vector2(x, y + 6), line, 14, Color(Style.DIM, a), HORIZONTAL_ALIGNMENT_RIGHT, _f_small)


## Equipment, always on screen: the one that G throws is amber, underlined and carries the key;
## switching flashes it.
func _draw_gadgets(size: Vector2) -> void:
	var w := game.player.weapons
	if w.gadgets.is_empty():
		return
	var key := "%d:%s" % [w.gsel, w.gadget_info().get("type", "")]
	if key != _gadget_seen:
		if _gadget_seen != "":
			_gadget_flash = 1.2
		_gadget_seen = key
	_gadget_flash = maxf(0.0, _gadget_flash - get_process_delta_time())
	var x := size.x - 34.0
	var y := size.y - 10.0
	for i in range(w.gadgets.size() - 1, -1, -1):
		var g: Dictionary = w.gadgets[i]
		var n := int(g.n)
		var sel := i == w.gsel
		var t := "%s  ×%d" % [Gadget.INFO[g.type].name, n]
		var col := Style.AMBER if sel else Style.DIM
		if n == 0:
			col = Color(col, 0.4)
		var tw := _f_small.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if sel:
			if _gadget_flash > 0.0:
				_overlay.draw_rect(Rect2(x - tw - 6, y - 16, tw + 12, 22), Color(Style.AMBER, 0.18 * _gadget_flash))
			_text(Vector2(x, y), t, 14, col, HORIZONTAL_ALIGNMENT_RIGHT, _f_small)
			_overlay.draw_rect(Rect2(x - tw, y + 4, tw, 2), col)
			var glyph := Settings.glyph("gadget")
			var cw := _keycap_width(glyph)
			_keycap(Vector2(x - tw - 10 - cw, y), glyph, 0.9)
			x -= tw + cw + 10 + 22
		else:
			_text(Vector2(x, y), t, 14, col, HORIZONTAL_ALIGNMENT_RIGHT, _f_small)
			x -= tw + 22


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
		y += 32.0


func _draw_hint(size: Vector2) -> void:
	var h := hints.current
	if h.is_empty() and hints.alpha <= 0.01:
		return
	if h.is_empty():
		return
	var a := hints.alpha
	var x := 34.0
	var y := size.y * 0.44
	var keys: Array = h.keys
	var wdt := _prompt_row(Vector2.ZERO, keys, h.text, a, true) if not keys.is_empty() else _f_label.get_string_size(h.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var r := Rect2(x - 12, y - 28, wdt + 24, 40)
	_overlay.draw_rect(r, Color(0.02, 0.03, 0.05, 0.55 * a))
	_overlay.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), Color(Style.AMBER, a))
	if keys.is_empty():
		_text(Vector2(x, y), h.text, 16, Color(Style.INK, a))
	else:
		_prompt_row(Vector2(x, y), keys, h.text, a)


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
	# fine crosshair with heavy outer posts (duplex)
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
	# eye-box shadow: soft inner falloff, then the housing
	for i in 10:
		var k := i / 10.0
		_overlay.draw_arc(cc, r - 26.0 + k * 26.0, 0, TAU, 96, Color(0, 0, 0, 0.08 + k * 0.08), 3.2)
	_overlay.draw_arc(cc, r + 1.0, 0, TAU, 96, Color(0.55, 0.65, 0.8, 0.12), 1.5)
	_mask_outside(size, cc, r, Color.BLACK)
	var bw := 180.0
	var by := size.y * 0.93
	_overlay.draw_rect(Rect2(c.x - bw / 2, by, bw, 2), Color(1, 1, 1, 0.12))
	_overlay.draw_rect(Rect2(c.x - bw / 2, by, bw * p.breath / Player.BREATH, 2), Style.RED if p.breath_out > 0.0 else Style.DIM)
