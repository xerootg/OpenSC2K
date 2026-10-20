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


# On a touch screen a text field that takes focus by itself must not open the
# on-screen keyboard over the dialog. A tap on the field still opens it.
static func keep_keyboard_for_taps(tree: SceneTree) -> void:
	if not TabletPreferences.touch_device():
		return

	var quiet := func(node: Node) -> void:
		if node is LineEdit:
			(node as LineEdit).virtual_keyboard_show_on_focus = false

	tree.node_added.connect(quiet)

	for node in tree.root.find_children("*", "LineEdit", true, false):
		quiet.call(node)


# Call after the city workspace exists.
func attach() -> void:
	preferences = TabletPreferences.for_settings(app.preferences.settings_path)
	router = TabletInputRouter.new(app.map_view)
	ui = TabletUi.new()
	ui.setup(app, self)
	# the map moves its hover tile after the filter. the signal goes to the
	# node, so the router holds no reference back to this object
	router.hover_changed.connect(ui.on_pen_moved)
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
	# the map menu that a long press opens needs finger-sized rows
	var menu := app.map_view.context_menu

	if menu != null:
		for item in [["font_size", TabletStyle.FONT], ["v_separation", 18]]:
			if active:
				if item[0] == "font_size":
					menu.add_theme_font_size_override(item[0], item[1])
				else:
					menu.add_theme_constant_override(item[0], item[1])
			elif item[0] == "font_size":
				menu.remove_theme_font_size_override(item[0])
			else:
				menu.remove_theme_constant_override(item[0])


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
	router.hand = hand_mode()

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
