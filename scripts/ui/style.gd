class_name Style
## Shared look for every screen: one typeface, three weights, a restrained palette.
## Rules: tracked small capitals for labels, the medium weight for sentences, bold for numbers;
## hairlines instead of boxes; amber means "you", red means "danger", green means "advantage".

const INK := Color("e8edf1")
const DIM := Color(0.91, 0.93, 0.95, 0.5)
const FAINT := Color(0.91, 0.93, 0.95, 0.14)
const AMBER := Color("ffb84a")
const RED := Color("ff4a3a")
const GREEN := Color("7dffb0")
const BG := Color(0.016, 0.024, 0.04, 0.92)

static var medium: Font = preload("res://assets/fonts/Rajdhani-Medium.ttf")
static var semibold: Font = preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
static var bold: Font = preload("res://assets/fonts/Rajdhani-Bold.ttf")


static func label(text: String, size: int, color := INK, font: Font = null, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", spaced(font if font else medium, spacing) if spacing != 0 else (font if font else medium))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Tracked small capitals.
static func micro(text: String, color := DIM, size := 12) -> Label:
	return label(text.to_upper(), size, color, semibold, 3)


static func box(bg: Color, border: Color, width := 1, pad := 12, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(pad)
	sb.set_corner_radius_all(radius)
	return sb


static func spaced(font: Font, spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = font
	fv.spacing_glyph = spacing
	return fv


## A hairline rule.
static func rule(width := 0.0, color := FAINT) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(width, 1)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_SHRINK_BEGIN
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Text buttons: the primary action is ink on a hairline; the rest are dim until hovered.
static func button(text: String, primary := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", spaced(semibold, 4))
	b.add_theme_font_size_override("font_size", 16)
	var c := INK if primary else DIM
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), c if primary else FAINT, 1, 10, 3))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.05), INK, 1, 10, 3))
	b.add_theme_stylebox_override("pressed", box(Color(1, 0.72, 0.29, 0.08), AMBER, 1, 10, 3))
	b.custom_minimum_size = Vector2(170, 42)
	b.mouse_entered.connect(func() -> void: Sfx.ui("ui_move", -8.0))
	b.pressed.connect(func() -> void: Sfx.ui("ui_select", -6.0))
	return b


## A labelled slider row.
static func slider(text: String, lo: float, hi: float, step: float, value: float, on_change: Callable, width := 260.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var l := label(text, 16, DIM)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(width, 24)
	s.focus_mode = Control.FOCUS_NONE
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0, 0, 0, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = FAINT
	track.set_content_margin_all(0)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	var fill := StyleBoxFlat.new()
	fill.bg_color = INK
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row


## A labelled on/off toggle.
static func toggle(text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var l := label(text, 16, DIM)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = value
	b.focus_mode = Control.FOCUS_NONE
	b.text = "ON" if value else "OFF"
	b.add_theme_font_override("font", spaced(semibold, 3))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", AMBER)
	b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), FAINT, 1, 6, 3))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.05), DIM, 1, 6, 3))
	b.add_theme_stylebox_override("pressed", box(Color(1, 0.72, 0.29, 0.08), AMBER, 1, 6, 3))
	b.custom_minimum_size = Vector2(64, 28)
	b.toggled.connect(func(v: bool) -> void:
		b.text = "ON" if v else "OFF"
		Sfx.ui("ui_select", -8.0)
		on_change.call(v))
	row.add_child(b)
	return row
