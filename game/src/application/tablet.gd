class_name ApplicationTablet
extends RefCounted
## Switches between the desktop interface and the pen and touch interface,
## and gives the map the pen and finger input of TabletInputRouter.

var app: CityApplication
var preferences: TabletPreferences
var router: TabletInputRouter
var ui: TabletUi
var active := false
# the landscape editor and SCURK Place & Print keep the desktop toolbar
var _desktop_fallback := false


func _init(application: CityApplication) -> void:
	app = application


# Call after the city workspace exists.
func attach() -> void:
	preferences = TabletPreferences.for_settings(app.preferences.settings_path)
	router = TabletInputRouter.new(app.map_view)
	router.hand_mode = hand_mode
	router.hover_changed.connect(func(position: Vector2, hovering: bool) -> void:
		if ui != null and ui.visible:
			# the map moves its hover tile after the filter
			ui.pen_moved.call_deferred(position, hovering))
	ui = TabletUi.new()
	ui.setup(app, self)
	app.city_workspace.add_child(ui)
	apply_preferences()


func apply_preferences() -> void:
	if preferences == null:
		return

	preferences.save_values()
	router.side_button = preferences.side_button
	set_active(preferences.enabled())


func set_active(value: bool) -> void:
	active = value
	# interface buttons take the first finger as a mouse
	Input.emulate_mouse_from_touch = true
	app.map_view.pointer_filter = router.map_input if active else Callable()
	_desktop_fallback = false
	_apply_chrome()


# switch from the desktop Options menu
func toggle() -> void:
	preferences.mode = TabletPreferences.MODE_OFF if active else TabletPreferences.MODE_ON
	apply_preferences()
	app.interface.show_status("Tablet interface on." if active else "Tablet interface off.")


func _apply_chrome() -> void:
	var tablet_chrome := active and not _desktop_fallback
	var workspace := app.city_workspace
	workspace.menu_bar.visible = not tablet_chrome
	workspace.menu_bar.allow_hidden_trigger = tablet_chrome
	workspace.toolbar.visible = not tablet_chrome
	workspace.status_bar.visible = not tablet_chrome
	ui.visible = tablet_chrome

	if tablet_chrome:
		ui._layout.call_deferred()
	else:
		ui.drawer.close()
		ui.rail.close_flyout()
		ui.hover_tip.visible = false
		workspace._sync_camera_rect.call_deferred()


# Called for each input event before the interface. Returns true when the
# event is consumed (palm rejection).
func input(event: InputEvent) -> bool:
	if not active or router == null:
		return false

	_check_fallback()

	if router.global_input(event):
		return true

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9 and not TabletPreferences.touch_device():
		router.simulate_fingers = not router.simulate_fingers
		app.interface.show_status("Mouse acts as a finger." if router.simulate_fingers else "Mouse acts as the pen.")

		return true

	return false


func _check_fallback() -> void:
	var fallback := app.tool_state.landscape_editor or (app.scurk_place_print != null and app.scurk_place_print.visible)

	if fallback != _desktop_fallback:
		_desktop_fallback = fallback
		_apply_chrome()


func hand_mode() -> bool:
	return app.tool_state.selected_group == CityToolIds.Group.CENTERING and app.tool_state.held_tool == ApplicationCurrentTool.NO_TOOL


func tool_armed() -> bool:
	return app.map_view != null and app.map_view.edit_enabled and not hand_mode()
