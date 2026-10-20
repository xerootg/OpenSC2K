class_name TabletHoverTip
extends PanelContainer
## The small card beside a hovering pen. It names the tool, gives its cost,
## and shows why a placement at the hovered tile would fail, before the pen
## touches the screen. The card stays on the side away from the pen hand.

const Tools = preload("res://src/tools/shared/tool_catalog.gd")
const Zones = preload("res://src/tools/city/zone_command.gd")
const DisplayNumbers = preload("res://src/ui/shared/display_number_format.gd")
const OFFSET := Vector2(28, 36)
const IDLE_HIDE_MSEC := 1500

var app: CityApplication
var left_handed := false
var _title: Label
var _detail: Label
var _last_event_msec := 0
var _tile := Vector2i(-1, -1)
var _tool := Vector2i(-1, -1)


static func per_tile(group_index: int, subtool_index: int) -> bool:
	return (Zones.supports_tool(group_index, subtool_index) or NetworkPlacementPreview.supports_tool(group_index, subtool_index)
		or group_index == CityToolIds.Group.BULLDOZER or group_index == CityToolIds.Group.LANDSCAPE)


func setup(application: CityApplication) -> void:
	app = application
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", TabletStyle.panel(Color(0.05, 0.07, 0.09, 0.88), 10, 8.0))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_title = TabletStyle.label("", TabletStyle.FONT, TabletStyle.INK)
	column.add_child(_title)
	_detail = TabletStyle.label("", TabletStyle.FONT_SMALL, TabletStyle.INK_DIM)
	column.add_child(_detail)
	visible = false
	top_level = true
	z_index = 100


func pen_moved(map_position: Vector2, hovering: bool, map: CityMapControl, armed: bool) -> void:
	_last_event_msec = Time.get_ticks_msec()

	if not hovering or not armed or app.document_state.city == null or map.hover_tile.x < 0:
		visible = false
		_tile = Vector2i(-1, -1)

		return

	var tool := Vector2i(app.tool_state.selected_group, app.tool_state.selected_subtool)

	if map.hover_tile != _tile or tool != _tool:
		_tile = map.hover_tile
		_tool = tool
		_describe(map)

	visible = true
	reset_size()
	var screen_position := map.get_global_transform() * map_position
	var offset := Vector2(OFFSET.x if left_handed else -OFFSET.x - size.x, -OFFSET.y - size.y)
	var viewport_size := get_viewport_rect().size
	global_position = (screen_position + offset).clamp(Vector2(4, TabletStyle.BAR_HEIGHT + 4), viewport_size - size - Vector2(4, 4))


func _describe(map: CityMapControl) -> void:
	var group_index := app.tool_state.selected_group
	var subtool_index := app.tool_state.selected_subtool
	var tool := Tools.tool(group_index, subtool_index)

	if tool == null:
		visible = false

		return

	_title.text = tr(str(tool.name))
	var lines := PackedStringArray()
	var cost := int(tool.cost)
	var funds := app.document_state.city.funds()
	var free := app.scurk_workspace.scurk_edit_tool_active()

	if group_index == CityToolIds.Group.QUERY:
		lines.append(tr("Tap to inspect tile %d, %d") % [_tile.x, _tile.y])
	elif cost > 0 and not free:
		var price := "$%s" % DisplayNumbers.format(cost)
		lines.append(price + (tr(" / tile") if per_tile(group_index, subtool_index) else ""))

	var error := ""

	if map.placement_error_provider.is_valid():
		error = str(map.placement_error_provider.call(_tile))

	if error.is_empty() and cost > funds and not free:
		error = tr("Funds are not sufficient.")

	_title.add_theme_color_override("font_color", TabletStyle.BAD if not error.is_empty() else TabletStyle.INK)

	if not error.is_empty():
		error = tr(error)
		lines.append(error.left(1).to_upper() + error.substr(1))

	_detail.text = "\n".join(lines)
	_detail.visible = not lines.is_empty()
	_detail.add_theme_color_override("font_color", TabletStyle.BAD if not error.is_empty() else TabletStyle.INK_DIM)


func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec() - _last_event_msec > IDLE_HIDE_MSEC:
		visible = false
		_tile = Vector2i(-1, -1)


func refresh() -> void:
	_tile = Vector2i(-1, -1)
