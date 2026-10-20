class_name TabletToolRail
extends PanelContainer
## The tool groups of the original toolbar as large buttons in two columns. A
## tap selects the group with its last subtool and opens a flyout with the
## subtools, their names and their costs. The hidden desktop toolbar stays the
## source of the subtool list, icons and availability.

const Tools = preload("res://src/tools/shared/tool_catalog.gd")
const DisplayNumbers = preload("res://src/ui/shared/display_number_format.gd")
# the original toolbar order. Centering is the Hand tool
const GROUP_ORDER: Array[int] = [
	CityToolIds.Group.BULLDOZER, CityToolIds.Group.LANDSCAPE,
	CityToolIds.Group.POWER, CityToolIds.Group.WATER,
	CityToolIds.Group.REWARDS, CityToolIds.Group.ROADS,
	CityToolIds.Group.RAIL, CityToolIds.Group.PORTS,
	CityToolIds.Group.RESIDENTIAL, CityToolIds.Group.COMMERCIAL,
	CityToolIds.Group.INDUSTRIAL, CityToolIds.Group.EDUCATION,
	CityToolIds.Group.SERVICES, CityToolIds.Group.RECREATION,
	CityToolIds.Group.SIGNS, CityToolIds.Group.QUERY,
	CityToolIds.Group.DISPATCH, CityToolIds.Group.CENTERING,
]
const GROUP_NAMES := {
	CityToolIds.Group.BULLDOZER: "Bulldozer", CityToolIds.Group.LANDSCAPE: "Landscape",
	CityToolIds.Group.DISPATCH: "Emergency", CityToolIds.Group.POWER: "Power",
	CityToolIds.Group.WATER: "Water", CityToolIds.Group.REWARDS: "Rewards",
	CityToolIds.Group.ROADS: "Roads", CityToolIds.Group.RAIL: "Rail",
	CityToolIds.Group.PORTS: "Ports", CityToolIds.Group.RESIDENTIAL: "Residential",
	CityToolIds.Group.COMMERCIAL: "Commercial", CityToolIds.Group.INDUSTRIAL: "Industrial",
	CityToolIds.Group.EDUCATION: "Education", CityToolIds.Group.SERVICES: "City Services",
	CityToolIds.Group.RECREATION: "Parks", CityToolIds.Group.SIGNS: "Signs",
	CityToolIds.Group.QUERY: "Query", CityToolIds.Group.CENTERING: "Hand (move map)",
}
const FLYOUT_WIDTH := 330.0

var app: CityApplication
var group_buttons: Dictionary[int, Button] = {}
var flyout: PanelContainer
var flyout_group := -1
var _flyout_title: Label
var _flyout_rows: VBoxContainer
var _flyout_scroll: ScrollContainer
var _grid: GridContainer


func setup(application: CityApplication) -> void:
	app = application
	add_theme_stylebox_override("panel", TabletStyle.panel(TabletStyle.PANEL, TabletStyle.RADIUS, 6.0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", int(TabletStyle.GAP))
	_grid.add_theme_constant_override("v_separation", int(TabletStyle.GAP))
	add_child(_grid)

	for group_index in GROUP_ORDER:
		var button := TabletStyle.button("", Vector2(TabletStyle.RAIL_BUTTON, TabletStyle.RAIL_BUTTON))
		button.toggle_mode = true
		button.tooltip_text = tr(GROUP_NAMES.get(group_index, ""))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 40)

		if group_index == CityToolIds.Group.CENTERING:
			var glyph := TabletGlyph.new()
			glyph.glyph = "hand"
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
			button.add_child(glyph)
		else:
			button.icon = app.city_toolbar.group_icon(group_index) if app.city_toolbar != null else null

			if button.icon == null:
				button.text = tr(GROUP_NAMES.get(group_index, "?")).left(2)

		button.pressed.connect(_on_group_pressed.bind(group_index))
		_grid.add_child(button)
		group_buttons[group_index] = button

	_build_flyout()


func _build_flyout() -> void:
	flyout = PanelContainer.new()
	flyout.add_theme_stylebox_override("panel", TabletStyle.panel(TabletStyle.PANEL_SOLID, TabletStyle.RADIUS, 10.0))
	flyout.visible = false
	flyout.mouse_filter = Control.MOUSE_FILTER_STOP
	flyout.custom_minimum_size = Vector2(FLYOUT_WIDTH, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(TabletStyle.GAP))
	flyout.add_child(column)
	_flyout_title = TabletStyle.label("", TabletStyle.FONT_LARGE, TabletStyle.ACCENT)
	column.add_child(_flyout_title)
	_flyout_scroll = ScrollContainer.new()
	_flyout_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_flyout_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_flyout_scroll)
	_flyout_rows = VBoxContainer.new()
	_flyout_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flyout_rows.add_theme_constant_override("separation", int(TabletStyle.GAP))
	_flyout_scroll.add_child(_flyout_rows)


func _on_group_pressed(group_index: int) -> void:
	app.interface.play_toolbar_click()

	if flyout.visible and flyout_group == group_index:
		close_flyout()
		sync()

		return

	app.camera_input.choose_tool_group(group_index)
	sync()

	if app.tool_state.selected_group == group_index:
		open_flyout(group_index)


func open_flyout(group_index: int) -> void:
	var palette := app.city_toolbar.child_palette if app.city_toolbar != null else null

	if palette == null or palette.shown_group != group_index or palette.buttons.size() < 2:
		close_flyout()

		return

	flyout_group = group_index
	_flyout_title.text = tr(GROUP_NAMES.get(group_index, Tools.group(group_index).name))

	for child in _flyout_rows.get_children():
		child.queue_free()

	var subtools: Array = palette.buttons.keys()
	subtools.sort()

	for subtool_index: int in subtools:
		var source := palette.buttons[subtool_index] as Button
		_flyout_rows.add_child(_subtool_row(group_index, subtool_index, source))

	flyout.visible = true
	_place_flyout(group_buttons[group_index], subtools.size())


func _subtool_row(group_index: int, subtool_index: int, source: Button) -> Button:
	var tool := Tools.tool(group_index, subtool_index)
	var row := TabletStyle.button("", Vector2(FLYOUT_WIDTH - 24.0, TabletStyle.TOUCH), TabletStyle.FONT)
	row.toggle_mode = true
	row.button_pressed = subtool_index == app.tool_state.selected_subtool
	row.disabled = source.disabled
	row.icon = source.icon
	row.expand_icon = true
	row.add_theme_constant_override("icon_max_width", 48)
	row.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.tooltip_text = source.tooltip_text
	var price := tr("Free") if int(tool.cost) == 0 else "$%s" % DisplayNumbers.format(int(tool.cost))

	if TabletHoverTip.per_tile(group_index, subtool_index) and int(tool.cost) > 0:
		price += tr(" / tile")

	row.text = "%s\n%s" % [tr(str(tool.name)), price]

	if row.disabled:
		row.text = "%s\n%s" % [tr(str(tool.name)), tr("Not available yet")]

	row.pressed.connect(func() -> void:
		app.interface.play_toolbar_click()
		app.current_tool.select_subtool(subtool_index)
		close_flyout()
		sync())

	return row


func _place_flyout(anchor: Control, rows: int) -> void:
	var viewport_size := get_viewport_rect().size
	var top_limit := TabletStyle.BAR_HEIGHT + 12.0
	var wanted := 52.0 + rows * (TabletStyle.TOUCH + TabletStyle.GAP)
	var height := minf(wanted, viewport_size.y - top_limit - 12.0)
	var anchor_rect := anchor.get_global_rect()
	var y := clampf(anchor_rect.position.y - 10.0, top_limit, viewport_size.y - 12.0 - height)
	flyout.size = Vector2(FLYOUT_WIDTH, height)
	flyout.custom_minimum_size = Vector2(FLYOUT_WIDTH, height)
	flyout.global_position = Vector2(get_global_rect().end.x + 8.0, y)


func close_flyout() -> void:
	flyout.visible = false
	flyout_group = -1


# show the selected group and hide the Emergency group outside a disaster
func sync() -> void:
	if app == null:
		return

	var city := app.document_state.city

	for group_index: int in group_buttons:
		var button := group_buttons[group_index]
		button.set_pressed_no_signal(group_index == app.tool_state.selected_group and app.tool_state.held_tool == Vector2i(-1, -1))

		# the original toolbar art can load after the rail
		var desktop_buttons := app.city_toolbar.toolbar_buttons if app.city_toolbar != null else []

		if group_index != CityToolIds.Group.CENTERING and group_index < desktop_buttons.size():
			var icon: Texture2D = desktop_buttons[group_index].icon

			if icon != null and button.icon != icon:
				button.icon = icon
				button.text = ""

		if group_index == CityToolIds.Group.DISPATCH:
			button.visible = city != null and ToolAvailability.is_dispatch_enabled(city)
