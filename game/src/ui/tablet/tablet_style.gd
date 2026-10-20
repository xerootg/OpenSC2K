class_name TabletStyle
extends RefCounted
## Sizes and colors of the tablet interface. Sizes are interface pixels. A Tab
## S11 at 2560 x 1600 and 340 dpi shows the 1280 x 800 layout at two screen
## pixels for each interface pixel, so one interface pixel is about 0.94 dp.

const TOUCH_MIN := 52.0
const TOUCH := 60.0
const BAR_HEIGHT := 56.0
const RAIL_BUTTON := 58.0
const GAP := 6.0
const RADIUS := 12
const FONT_SMALL := 15
const FONT := 18
const FONT_LARGE := 22
const PANEL := Color(0.075, 0.098, 0.122, 0.9)
const PANEL_SOLID := Color(0.075, 0.098, 0.122, 0.97)
const PANEL_EDGE := Color(1, 1, 1, 0.08)
const BUTTON := Color(0.16, 0.2, 0.245)
const BUTTON_HOVER := Color(0.22, 0.27, 0.33)
const BUTTON_PRESSED := Color(0.28, 0.24, 0.12)
const BUTTON_DISABLED := Color(0.12, 0.14, 0.16, 0.6)
# the yellow of the original toolbar selection
const ACCENT := Color("f2c230")
const INK := Color("eef2f5")
const INK_DIM := Color("9aa7b2")
const GOOD := Color("6bdc8f")
const BAD := Color("ff7a6e")
const ACCENT_INK := Color("1a1406")
const ZONE_COLORS: Array[Color] = [Color("3ccf6b"), Color("4a90e8"), Color("f0c419")]


static func panel(color := PANEL, radius := RADIUS, padding := 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = PANEL_EDGE
	box.set_border_width_all(1)
	box.set_content_margin_all(padding)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	box.anti_aliasing = true

	return box


static func _button_box(color: Color, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(RADIUS - 2)
	box.set_content_margin_all(6)
	box.border_color = border
	box.set_border_width_all(border_width)
	box.anti_aliasing = true

	return box


# gives a button the tablet look. toggled buttons show the accent outline
static func style_button(button: BaseButton, font_size := FONT) -> void:
	button.add_theme_stylebox_override("normal", _button_box(BUTTON))
	button.add_theme_stylebox_override("hover", _button_box(BUTTON_HOVER))
	button.add_theme_stylebox_override("pressed", _button_box(BUTTON_PRESSED, ACCENT, 3))
	button.add_theme_stylebox_override("hover_pressed", _button_box(BUTTON_PRESSED, ACCENT, 3))
	button.add_theme_stylebox_override("disabled", _button_box(BUTTON_DISABLED))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_hover_pressed_color", ACCENT)
	button.add_theme_color_override("font_disabled_color", INK_DIM)
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE
	# a drag that starts on a button scrolls the drawer or flyout on a touch
	# screen; the scroll start cancels the button press
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func button(text: String, minimum := Vector2(TOUCH, TOUCH), font_size := FONT) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = minimum
	style_button(result, font_size)

	return result


# a toggle that shows its pressed state as a filled accent button, for a
# choice of one, such as the simulation speed
static func fill_when_pressed(button: BaseButton) -> void:
	button.add_theme_stylebox_override("pressed", _button_box(ACCENT, ACCENT.lightened(0.4), 2))
	button.add_theme_stylebox_override("hover_pressed", _button_box(ACCENT.lightened(0.1), ACCENT.lightened(0.4), 2))
	button.add_theme_color_override("font_pressed_color", ACCENT_INK)
	button.add_theme_color_override("font_hover_pressed_color", ACCENT_INK)
	button.set_meta("filled_when_pressed", true)


# a button that shows a drawn glyph (TabletGlyph)
static func glyph_button(glyph: String, minimum := Vector2(TOUCH, TOUCH), tooltip := "") -> Button:
	var result := button("", minimum)
	result.tooltip_text = tooltip
	var icon := TabletGlyph.new()
	icon.glyph = glyph
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	result.add_child(icon)

	return result


static func label(text: String, font_size := FONT, color := INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	return result
