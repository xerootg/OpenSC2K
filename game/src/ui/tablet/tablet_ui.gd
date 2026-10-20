class_name TabletUi
extends Control
## The pen and touch interface over the city map: a slim status bar at the top,
## the tool rail on the left, the window drawer on the right, and the camera
## buttons at the bottom right. The desktop menu bar, toolbar and status bar
## stay in the scene, hidden, and remain the source of the tool and menu state.

const GameSpeed = preload("res://src/simulation/core/game_speed_controller.gd")
const DisplayNumbers = preload("res://src/ui/shared/display_number_format.gd")
const SPEED_GLYPHS: Array[String] = ["pause", "speed1", "speed2", "speed3", "speed4"]
const SPEED_NAMES: Array[String] = ["Pause", "Turtle", "Llama", "Cheetah", "African Swallow"]
const TOAST_SECONDS := 3.5
const SYNC_SECONDS := 0.2

var app: CityApplication
var tablet: ApplicationTablet
var top_bar: PanelContainer
var rail: TabletToolRail
var drawer: TabletDrawer
var hover_tip: TabletHoverTip
var camera_cluster: PanelContainer
var city_label: Label
var date_label: Label
var funds_label: Label
var population_label: Label
var ticker_label: Label
var zoom_label: Label
var rci: TabletRciBars
var speed_buttons: Array[Button] = []
var underground_button: Button
var drawer_button: Button
var toast: PanelContainer
var _toast_label: Label
var _toast_seconds := 0.0
var _last_status := ""
var _sync_seconds := 0.0


func setup(application: CityApplication, controller: ApplicationTablet) -> void:
	app = application
	tablet = controller
	name = "TabletUi"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = AppUiTheme.current()
	_build_top_bar()
	_build_rail()
	_build_camera_cluster()
	_build_toast()
	drawer = TabletDrawer.new()
	drawer.setup(app, tablet)
	drawer.tablet_settings_changed.connect(tablet.apply_preferences)
	add_child(drawer)
	hover_tip = TabletHoverTip.new()
	hover_tip.setup(app)
	add_child(hover_tip)
	resized.connect(_layout)
	_layout.call_deferred()


func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", TabletStyle.panel(TabletStyle.PANEL, 0, 4.0))
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top_bar.add_child(row)
	row.add_child(_spacer(4))
	city_label = TabletStyle.label("", TabletStyle.FONT_LARGE, TabletStyle.ACCENT)
	city_label.custom_minimum_size = Vector2(150, 0)
	city_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(city_label)
	date_label = TabletStyle.label("", TabletStyle.FONT)
	row.add_child(date_label)
	funds_label = TabletStyle.label("", TabletStyle.FONT, TabletStyle.GOOD)
	row.add_child(funds_label)
	population_label = TabletStyle.label("", TabletStyle.FONT_SMALL + 1, TabletStyle.INK_DIM)
	row.add_child(population_label)
	rci = TabletRciBars.new()
	rci.custom_minimum_size = Vector2(66, 44)
	row.add_child(rci)
	ticker_label = TabletStyle.label("", TabletStyle.FONT_SMALL + 1, TabletStyle.INK_DIM)
	ticker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ticker_label.clip_text = true
	ticker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(ticker_label)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 3)
	row.add_child(speeds)

	for index in SPEED_GLYPHS.size():
		var button := TabletStyle.glyph_button(SPEED_GLYPHS[index], Vector2(50, 46), tr(SPEED_NAMES[index]))
		button.toggle_mode = true
		button.pressed.connect(_on_speed_pressed.bind(index))
		speeds.add_child(button)
		speed_buttons.append(button)

	var undo := TabletStyle.glyph_button("undo", Vector2(50, 46), tr("Undo"))
	undo.pressed.connect(func() -> void: app.controls.run("undo"))
	row.add_child(undo)
	drawer_button = TabletStyle.glyph_button("menu", Vector2(60, 46), tr("Windows and options"))
	drawer_button.toggle_mode = true
	drawer_button.pressed.connect(func() -> void:
		app.interface.play_toolbar_click()
		rail.close_flyout()
		drawer.toggle())
	row.add_child(drawer_button)


func _spacer(width: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(width, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return spacer


func _build_rail() -> void:
	rail = TabletToolRail.new()
	rail.setup(app)
	add_child(rail)
	add_child(rail.flyout)


func _build_camera_cluster() -> void:
	camera_cluster = PanelContainer.new()
	camera_cluster.add_theme_stylebox_override("panel", TabletStyle.panel(TabletStyle.PANEL, TabletStyle.RADIUS + 4, 6.0))
	camera_cluster.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(camera_cluster)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(TabletStyle.GAP))
	camera_cluster.add_child(row)
	underground_button = TabletStyle.glyph_button("layers", Vector2(TabletStyle.TOUCH, TabletStyle.TOUCH), tr("Underground view"))
	underground_button.toggle_mode = true
	underground_button.pressed.connect(func() -> void: _run("view_toggle_underground"))
	row.add_child(underground_button)

	for entry in [["rotate_ccw", "rotate_counter_clockwise", "Rotate counterclockwise"],
			["rotate_cw", "rotate_clockwise", "Rotate clockwise"], ["zoom_out", "zoom_out", "Zoom out"]]:
		var button := TabletStyle.glyph_button(entry[0], Vector2(TabletStyle.TOUCH, TabletStyle.TOUCH), tr(entry[2]))
		button.pressed.connect(_run.bind(entry[1]))
		row.add_child(button)

	zoom_label = TabletStyle.label("", TabletStyle.FONT_SMALL, TabletStyle.INK_DIM)
	zoom_label.custom_minimum_size = Vector2(52, 0)
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(zoom_label)
	var zoom_in := TabletStyle.glyph_button("zoom_in", Vector2(TabletStyle.TOUCH, TabletStyle.TOUCH), tr("Zoom in"))
	zoom_in.pressed.connect(_run.bind("zoom_in"))
	row.add_child(zoom_in)


func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.add_theme_stylebox_override("panel", TabletStyle.panel(Color(0.05, 0.07, 0.09, 0.9), 10, 10.0))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	toast.z_index = 20
	add_child(toast)
	_toast_label = TabletStyle.label("", TabletStyle.FONT)
	_toast_label.clip_text = true
	_toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(_toast_label)


func _run(action: String) -> void:
	app.interface.play_toolbar_click()
	app.controls.run(action)
	sync()


func _on_speed_pressed(index: int) -> void:
	app.interface.play_toolbar_click()
	app.controls.run(ControlActions.SPEED_IDS[index])
	sync()


func _layout() -> void:
	var area := size
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(area.x, TabletStyle.BAR_HEIGHT)
	rail.reset_size()
	rail.position = Vector2(8, TabletStyle.BAR_HEIGHT + 8.0)
	camera_cluster.reset_size()
	camera_cluster.position = area - camera_cluster.size - Vector2(10, 10)
	var drawer_height := area.y - TabletStyle.BAR_HEIGHT - 16.0
	drawer.size = Vector2(TabletDrawer.WIDTH, drawer_height)
	drawer.position = Vector2(area.x - TabletDrawer.WIDTH - 8.0 if drawer.opened else area.x + 8.0, TabletStyle.BAR_HEIGHT + 8.0)
	_layout_toast()

	if app.map_view != null:
		# the camera centers and clamps the city in the area that the controls leave
		var left := rail.position.x + rail.size.x
		app.map_view.camera_view_rect = Rect2(Vector2(left, TabletStyle.BAR_HEIGHT), area - Vector2(left, TabletStyle.BAR_HEIGHT))


func _layout_toast() -> void:
	var font := _toast_label.get_theme_font("font")
	var width := font.get_string_size(_toast_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TabletStyle.FONT).x + 8.0
	_toast_label.custom_minimum_size = Vector2(minf(width, size.x * 0.7), 0)
	toast.size = Vector2.ZERO
	toast.reset_size()
	toast.position = Vector2((size.x - toast.size.x) * 0.5, size.y - toast.size.y - TabletStyle.TOUCH - 30.0)


func _process(delta: float) -> void:
	if not visible:
		return

	tablet.router.process(delta)
	_sync_seconds -= delta

	if _sync_seconds <= 0.0:
		_sync_seconds = SYNC_SECONDS
		sync()

	_watch_status()

	if _toast_seconds > 0.0:
		_toast_seconds -= delta
		toast.modulate.a = clampf(_toast_seconds / 0.4, 0.0, 1.0)

		if _toast_seconds <= 0.0:
			toast.visible = false


# show each new status message briefly, as the desktop status bar does
func _watch_status() -> void:
	if app.status_label == null:
		return

	var text := app.status_label.text

	if text == _last_status:
		return

	_last_status = text

	if text.is_empty() or text in ["City ready.", "Main menu."]:
		return

	show_toast(text, app.status_label.theme_type_variation == "ErrorLabel")


func show_toast(text: String, error := false) -> void:
	_toast_label.text = tr(text)
	_toast_label.add_theme_color_override("font_color", TabletStyle.BAD if error else TabletStyle.INK)
	toast.visible = true
	toast.modulate.a = 1.0
	_toast_seconds = TOAST_SECONDS
	_layout_toast()


func sync() -> void:
	var city := app.document_state.city

	if app.city_menu_bar != null:
		city_label.text = app.city_menu_bar.city_label.text
		date_label.text = app.city_menu_bar.date_label.text.trim_prefix(tr("Date: "))
		funds_label.text = app.city_menu_bar.money_label.text.trim_prefix(tr("Funds: "))
		population_label.text = app.city_menu_bar.population_label.text

	if city != null:
		funds_label.add_theme_color_override("font_color", TabletStyle.GOOD if city.funds() >= 0 else TabletStyle.BAD)
		rci.set_demand(city.rci_demand())
	else:
		rci.set_demand(Vector3i.ZERO)

	if app.city_status_bar != null:
		ticker_label.text = app.city_status_bar.reports_label.text
		ticker_label.add_theme_color_override("font_color",
			TabletStyle.BAD if app.city_status_bar.reports_label.theme_type_variation == "ErrorLabel" else TabletStyle.INK_DIM)

	var speed := app.simulation_state.speed_controller.speed if app.simulation_state.speed_controller != null else -1

	for index in speed_buttons.size():
		speed_buttons[index].set_pressed_no_signal(index == speed)
		speed_buttons[index].queue_redraw()

	underground_button.set_pressed_no_signal(app.view_state.overlay_mode == CityViewMode.Mode.UNDERGROUND)
	underground_button.queue_redraw()
	drawer_button.set_pressed_no_signal(drawer.opened)
	drawer_button.queue_redraw()

	if app.map_view != null:
		var percent := app.map_view.zoom_factor * 100.0
		zoom_label.text = ("%d%%" % roundi(percent)) if percent >= 10.0 else ("%s%%" % String.num(percent, 1))

	rail.sync()


# a press outside the flyout and the drawer closes them
func _input(event: InputEvent) -> void:
	if not visible:
		return

	var position := Vector2.INF

	if event is InputEventMouseButton and event.pressed:
		position = event.position
	elif event is InputEventScreenTouch and event.pressed:
		position = event.position

	if position == Vector2.INF:
		return

	if rail.flyout.visible and not rail.flyout.get_global_rect().has_point(position) and not rail.get_global_rect().has_point(position):
		rail.close_flyout()

	if (drawer.opened and not drawer.get_global_rect().has_point(position)
			and not drawer_button.get_global_rect().has_point(position) and _point_on_map(position)):
		drawer.close()


func _point_on_map(position: Vector2) -> bool:
	for control: Control in [top_bar, rail, camera_cluster]:
		if control.get_global_rect().has_point(position):
			return false

	return true


func pen_moved(position: Vector2, hovering: bool) -> void:
	hover_tip.left_handed = tablet.preferences.hand == TabletPreferences.HAND_LEFT
	hover_tip.pen_moved(position, hovering and not drawer.get_global_rect().has_point(position), app.map_view, tablet.tool_armed())
