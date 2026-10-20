class_name TabletDrawer
extends PanelContainer
## The right drawer of the tablet interface: the city windows, views, options,
## disasters, files and tablet settings. Each entry runs the same player action
## as the desktop menu, so the existing windows open.

signal tablet_settings_changed

const WIDTH := 400.0
const SLIDE_SECONDS := 0.18
const WINDOWS := [
	["Budget", "window_budget"], ["Ordinances", "window_ordinances"], ["Population", "window_population"],
	["Industry", "window_industry"], ["Graphs", "window_graphs"], ["Neighbors", "window_neighbors"],
	["City Map", "window_map"], ["Newspaper", "window_newspaper"],
]
const LAYERS := [
	["Buildings", "buildings", "view_show_buildings"], ["Networks", "networks", "view_show_networks"],
	["Water", "water", "view_show_water"], ["Trees", "trees", "view_show_trees"],
	["Signs", "signs", "view_show_signs"], ["Vehicles", "vehicles", "view_show_vehicles"],
]
const FILES := [
	["Save", "file_save"], ["Save As", "file_save_as"], ["Open City", "file_open"], ["New City", "file_new"],
	["Rename", "file_rename"], ["Main Menu", "file_main_menu"],
]

var app: CityApplication
var tablet: ApplicationTablet
var opened := false
var _content: VBoxContainer
var _scroll: ScrollContainer
var _tween: Tween
var _disasters_open := false


func setup(application: CityApplication, controller: ApplicationTablet) -> void:
	app = application
	tablet = controller
	add_theme_stylebox_override("panel", TabletStyle.panel(TabletStyle.PANEL_SOLID, TabletStyle.RADIUS, 12.0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", int(TabletStyle.GAP))
	_scroll.add_child(_content)
	visible = false


func toggle() -> void:
	if opened:
		close()
	else:
		open()


func open() -> void:
	opened = true
	rebuild()
	visible = true
	_slide(get_parent_area_size().x - size.x - 8.0)


func close() -> void:
	if not opened:
		return

	opened = false
	_slide(get_parent_area_size().x + 8.0, true)


func _slide(x: float, hide_after := false) -> void:
	if _tween != null:
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "position:x", x, SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if hide_after:
		_tween.tween_callback(func() -> void: visible = opened)


func rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var city := app.document_state.city
	_section("City")
	var windows := _grid()

	for entry in WINDOWS:
		_action_button(windows, entry[0], entry[1], true)

	if app.simulation_state.simulation_engine != null and app.simulation_state.simulation_engine.scenario != null:
		_action_button(windows, "Scenario Goals", "window_scenario_goals", true)

	_section("View")
	var views := _grid()
	var mode := app.view_state.overlay_mode
	_toggle_button(views, "City", mode == CityViewMode.Mode.CITY and not app.menus.zones_view_active(),
		func() -> void: app.controls.run("view_city"))
	_toggle_button(views, "Underground", mode == CityViewMode.Mode.UNDERGROUND,
		func() -> void: app.controls.run("view_toggle_underground"))
	_toggle_button(views, "Zones", app.menus.zones_view_active(), func() -> void: app.menus.select_zones_view())

	for index in CityViewMode.DATA_MODES.size():
		var data_mode: CityViewMode.Mode = CityViewMode.DATA_MODES[index]
		_toggle_button(views, str(CityDataView.TITLES[index]), mode == data_mode,
			func() -> void: app.menus.select_view(data_mode))

	_section("Layers")
	var layers := _grid()

	for entry in LAYERS:
		var check := app.city_toolbar.view_visibility_checks.get(entry[1]) as BaseButton if app.city_toolbar != null else null
		_toggle_button(layers, entry[0], check != null and check.button_pressed, func() -> void: app.controls.run(entry[2]), false)

	if city != null:
		_section("Options")
		var options := _grid()
		_toggle_button(options, "Auto-Budget", city.auto_budget_enabled(), func() -> void: app.controls.run("option_auto_budget"), false)
		_toggle_button(options, "Auto-Goto", city.auto_goto_enabled(), func() -> void: app.controls.run("option_auto_goto"), false)
		_toggle_button(options, "Sound Effects", city.sound_enabled(), func() -> void: app.controls.run("option_sound_effects"), false)
		_toggle_button(options, "Music", city.music_enabled(), func() -> void: app.controls.run("option_music"), false)
		_disaster_section(city)

	_section("File")
	var files := _grid()

	for entry in FILES:
		_action_button(files, entry[0], entry[1], true)

	_tablet_section()
	_section("Application")
	var application := _grid()
	_action_button(application, "Settings", "settings", true)
	_plain_button(application, "About", func() -> void: app.interface.open_about_dialog(), true)


func _disaster_section(city: CityState) -> void:
	var header := TabletStyle.button(("▾ " if _disasters_open else "▸ ") + tr("Disasters"), Vector2(0, TabletStyle.TOUCH_MIN))
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.pressed.connect(func() -> void:
		_disasters_open = not _disasters_open
		rebuild())
	_content.add_child(header)

	if not _disasters_open:
		return

	var grid := _grid()
	_toggle_button(grid, "No Disasters", city.no_disasters_enabled(),
		func() -> void: app.reports.on_disaster_menu(CityMenuBar.MENU_NO_DISASTERS), false)

	for entry in CityMenuBar.DISASTERS_MENU_ITEMS:
		var id: int = entry[1]
		_plain_button(grid, entry[0], func() -> void: app.reports.on_disaster_menu(id), true)


func _tablet_section() -> void:
	var preferences := tablet.preferences
	_section("Pen and touch")
	_choice_row("Interface", [["Auto", TabletPreferences.MODE_AUTO], ["Tablet", TabletPreferences.MODE_ON],
		["Desktop", TabletPreferences.MODE_OFF]], preferences.mode, func(value: String) -> void:
			preferences.mode = value)
	_choice_row("Pen side button", [["Query", TabletPreferences.SIDE_QUERY], ["Bulldoze", TabletPreferences.SIDE_BULLDOZE]],
		preferences.side_button, func(value: String) -> void:
			preferences.side_button = value)
	_choice_row("Pen hand", [["Right", TabletPreferences.HAND_RIGHT], ["Left", TabletPreferences.HAND_LEFT]],
		preferences.hand, func(value: String) -> void:
			preferences.hand = value)

	if not TabletPreferences.touch_device():
		var grid := _grid()
		_toggle_button(grid, "Mouse as finger", tablet.router.simulate_fingers, func() -> void:
			tablet.router.simulate_fingers = not tablet.router.simulate_fingers
			rebuild(), false)

	var hint := TabletStyle.label(tr("Fingers move the map: drag to pan, pinch to zoom, two-finger tap to step the zoom. "
		+ "The pen uses the tool; hover to preview. Without a pen, one finger uses the tool and two fingers move the map."),
		TabletStyle.FONT_SMALL, TabletStyle.INK_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	_content.add_child(hint)


func _choice_row(title: String, choices: Array, current: String, apply: Callable) -> void:
	_content.add_child(TabletStyle.label(tr(title), TabletStyle.FONT_SMALL, TabletStyle.INK_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(TabletStyle.GAP))
	_content.add_child(row)

	for choice in choices:
		var value: String = choice[1]
		var button := TabletStyle.button(tr(choice[0]), Vector2(0, TabletStyle.TOUCH_MIN), TabletStyle.FONT_SMALL + 1)
		button.toggle_mode = true
		button.button_pressed = value == current
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			apply.call(value)
			tablet_settings_changed.emit()
			rebuild())
		row.add_child(button)


func _section(title: String) -> void:
	var heading := TabletStyle.label(tr(title), TabletStyle.FONT_LARGE, TabletStyle.ACCENT)
	heading.custom_minimum_size = Vector2(0, 36)
	_content.add_child(heading)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(TabletStyle.GAP))
	grid.add_theme_constant_override("v_separation", int(TabletStyle.GAP))
	_content.add_child(grid)

	return grid


func _cell(button: Button, parent: Control) -> void:
	button.custom_minimum_size = Vector2((WIDTH - 24.0 - TabletStyle.GAP) * 0.5, TabletStyle.TOUCH_MIN)
	button.clip_text = true
	parent.add_child(button)


func _action_button(parent: Control, text: String, action: String, closes: bool) -> void:
	_plain_button(parent, text, func() -> void: app.controls.run(action), closes)


func _plain_button(parent: Control, text: String, run: Callable, closes: bool) -> void:
	var button := TabletStyle.button(tr(text), Vector2.ZERO, TabletStyle.FONT_SMALL + 2)
	button.pressed.connect(func() -> void:
		app.interface.play_toolbar_click()

		if closes:
			close()

		run.call())
	_cell(button, parent)


func _toggle_button(parent: Control, text: String, pressed: bool, run: Callable, closes := true) -> void:
	var button := TabletStyle.button(tr(text), Vector2.ZERO, TabletStyle.FONT_SMALL + 2)
	button.toggle_mode = true
	button.button_pressed = pressed
	button.pressed.connect(func() -> void:
		app.interface.play_toolbar_click()
		run.call()

		if closes:
			close()
		else:
			rebuild.call_deferred())
	_cell(button, parent)
