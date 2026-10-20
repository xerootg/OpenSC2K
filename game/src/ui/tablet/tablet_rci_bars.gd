class_name TabletRciBars
extends Control
## The residential, commercial and industrial demand as three small bars, as
## the Demand Indicator of the original shows it. Bars grow up for demand and
## down for surplus.

const MAX_DEMAND := 2000.0
const LETTERS: Array[String] = ["R", "C", "I"]

var demand := Vector3i.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "Demand: residential, commercial, industrial"


func set_demand(value: Vector3i) -> void:
	if value == demand:
		return

	demand = value
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var bar_width := size.x / 3.0
	var label_height := 14.0
	var middle := (size.y - label_height) * 0.5
	var half := middle - 2.0
	draw_line(Vector2(0, middle), Vector2(size.x, middle), TabletStyle.INK_DIM, 1.0)

	for index in 3:
		var value := clampf(float(demand[index]) / MAX_DEMAND, -1.0, 1.0)
		var x := index * bar_width + bar_width * 0.2
		var height := absf(value) * half
		var top := middle - height if value > 0.0 else middle
		draw_rect(Rect2(x, top, bar_width * 0.6, maxf(1.0, height)), TabletStyle.ZONE_COLORS[index])
		draw_string(font, Vector2(index * bar_width, size.y - 2.0), LETTERS[index], HORIZONTAL_ALIGNMENT_CENTER, bar_width, 12,
			TabletStyle.INK_DIM)
