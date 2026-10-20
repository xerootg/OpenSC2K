class_name TabletGlyph
extends Control
## Simple vector icons for the tablet controls that have no original artwork.
## The parent button colors the glyph: the accent when pressed, dim when disabled.

var glyph := "":
	set(value):
		glyph = value
		queue_redraw()


func _ready() -> void:
	var parent_button := get_parent() as BaseButton

	if parent_button != null:
		parent_button.toggled.connect(func(_on: bool) -> void: queue_redraw())
		parent_button.draw.connect(queue_redraw)


func _color() -> Color:
	var parent_button := get_parent() as BaseButton

	if parent_button != null and parent_button.disabled:
		return TabletStyle.INK_DIM

	if parent_button != null and parent_button.button_pressed:
		return TabletStyle.ACCENT_INK if parent_button.has_meta("filled_when_pressed") else TabletStyle.ACCENT

	return TabletStyle.INK


func _draw() -> void:
	var color := _color()
	var center := size * 0.5
	var unit := minf(size.x, size.y) * 0.18
	var width := maxf(2.5, unit * 0.32)

	match glyph:
		"menu":
			for row in [-1, 0, 1]:
				draw_line(center + Vector2(-unit * 1.3, row * unit * 0.85), center + Vector2(unit * 1.3, row * unit * 0.85), color, width, true)
		"close":
			draw_line(center - Vector2(unit, unit), center + Vector2(unit, unit), color, width, true)
			draw_line(center + Vector2(-unit, unit), center + Vector2(unit, -unit), color, width, true)
		"pause":
			draw_rect(Rect2(center + Vector2(-unit * 0.9, -unit), Vector2(unit * 0.6, unit * 2)), color)
			draw_rect(Rect2(center + Vector2(unit * 0.3, -unit), Vector2(unit * 0.6, unit * 2)), color)
		"speed1", "speed2", "speed3", "speed4":
			_draw_speed(int(glyph.right(1)), center, unit, color)
		"zoom_in", "zoom_out":
			draw_line(center - Vector2(unit * 1.1, 0), center + Vector2(unit * 1.1, 0), color, width * 1.2, true)

			if glyph == "zoom_in":
				draw_line(center - Vector2(0, unit * 1.1), center + Vector2(0, unit * 1.1), color, width * 1.2, true)
		"rotate_ccw", "rotate_cw":
			_draw_rotate(glyph == "rotate_cw", center, unit, color, width)
		"layers":
			for step in [1, 0, -1]:
				var offset := Vector2(0, step * unit * 0.6)
				var points := PackedVector2Array([
					center + offset + Vector2(-unit * 1.4, 0), center + offset + Vector2(0, -unit * 0.7),
					center + offset + Vector2(unit * 1.4, 0), center + offset + Vector2(0, unit * 0.7),
					center + offset + Vector2(-unit * 1.4, 0),
				])
				draw_polyline(points, color, width * 0.8, true)
		"undo":
			draw_arc(center + Vector2(unit * 0.2, unit * 0.2), unit, PI * 1.0, PI * 2.4, 20, color, width, true)
			var tip := center + Vector2(-unit * 0.8, unit * 0.2)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-unit * 0.6, -unit * 0.1), tip + Vector2(unit * 0.6, -unit * 0.1),
				tip + Vector2(0, unit * 0.7)]), color)
		"hand":
			draw_circle(center, unit * 1.2, color, false, width, true)
			draw_line(center - Vector2(unit * 1.8, 0), center - Vector2(unit * 0.7, 0), color, width, true)
			draw_line(center + Vector2(unit * 1.8, 0), center + Vector2(unit * 0.7, 0), color, width, true)
			draw_line(center - Vector2(0, unit * 1.8), center - Vector2(0, unit * 0.7), color, width, true)
			draw_line(center + Vector2(0, unit * 1.8), center + Vector2(0, unit * 0.7), color, width, true)


func _draw_speed(count: int, center: Vector2, unit: float, color: Color) -> void:
	var step := unit * 0.9
	var start := center.x - (count - 1) * step * 0.5

	for index in count:
		var x := start + index * step
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - unit * 0.55, center.y - unit * 0.9), Vector2(x + unit * 0.55, center.y),
			Vector2(x - unit * 0.55, center.y + unit * 0.9),
		]), color)


func _draw_rotate(clockwise: bool, center: Vector2, unit: float, color: Color, width: float) -> void:
	var radius := unit * 1.15
	var start := -PI * 0.75
	var finish := PI * 0.75
	draw_arc(center, radius, start, finish, 24, color, width, true)
	var angle := finish if clockwise else start
	var tip := center + Vector2.from_angle(angle) * radius
	var tangent := Vector2.from_angle(angle + (PI * 0.5 if clockwise else -PI * 0.5))
	var normal := Vector2.from_angle(angle)
	draw_colored_polygon(PackedVector2Array([
		tip + tangent * unit * 0.75, tip + normal * unit * 0.55 - tangent * unit * 0.1, tip - normal * unit * 0.55 - tangent * unit * 0.1,
	]), color)
