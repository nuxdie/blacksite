class_name Style
## Shared look for every screen: one typeface, three weights, a restrained palette.

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
	l.add_theme_font_override("font", font if font else medium)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = font if font else medium
		fv.spacing_glyph = spacing
		l.add_theme_font_override("font", fv)
	return l


static func box(bg: Color, border: Color, width := 1, pad := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(pad)
	return sb


static func spaced(font: Font, spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = font
	fv.spacing_glyph = spacing
	return fv


static func button(text: String, primary := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", spaced(semibold, 5))
	b.add_theme_font_size_override("font_size", 18)
	var c := INK if primary else DIM
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), c, 1, 10))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.06), INK, 1, 10))
	b.add_theme_stylebox_override("pressed", box(Color(1, 0.72, 0.29, 0.08), AMBER, 1, 10))
	b.custom_minimum_size = Vector2(190, 44)
	b.mouse_entered.connect(func() -> void: Sfx.play("ui_move", -6.0, 0.0))
	b.pressed.connect(func() -> void: Sfx.play("ui_select", -4.0, 0.0))
	return b
