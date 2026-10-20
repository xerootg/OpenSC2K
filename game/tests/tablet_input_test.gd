extends SceneTree
## Pen and finger sorting of the tablet interface: palm rejection, the hand
## tool gestures, a second finger that turns a tool touch into a camera
## gesture, and the saved tablet preferences.

var map: CityMapControl
var router: TabletInputRouter


func _initialize() -> void:
	call_deferred("_run")


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	assert(router.map_input(event))


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	assert(router.map_input(event))


func _run() -> void:
	map = CityMapControl.new()
	map.size = Vector2(1280, 800)
	root.add_child(map)
	await process_frame
	router = TabletInputRouter.new(map)

	# a stylus is a mouse with a real device; a finger makes emulated mouse events
	var pen := InputEventMouseMotion.new()
	pen.device = 0
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	assert(TabletInputRouter.is_pen(pen) and not TabletInputRouter.is_pen(emulated))
	assert(router.map_input(emulated), "the map ignores mouse events that a finger makes")

	# palm rejection: a finger near a hovering pen is ignored, later it is not
	var palm := InputEventScreenTouch.new()
	palm.index = 2
	palm.pressed = true
	assert(not router.global_input(palm), "a finger works before any pen is seen")
	assert(not router.global_input(pen))
	assert(router.global_input(palm) and router.global_input(emulated))
	router.last_pen_msec -= TabletInputRouter.PALM_GRACE_MSEC + 1
	assert(not router.global_input(palm))

	# the hand tool: a finger drag pans, a two-finger tap steps the zoom
	router.hand = true
	var center := map.source_center
	_touch(0, Vector2(600, 400), true)
	assert(router.gesture == TabletInputRouter.Gesture.PAN)
	_drag(0, Vector2(560, 380), Vector2(-40, -20))
	_touch(0, Vector2(560, 380), false)
	assert(map.source_center != center or map.city == null)
	var zoom := map.zoom_factor
	_touch(0, Vector2(560, 400), true)
	_touch(1, Vector2(720, 400), true)
	assert(router.gesture == TabletInputRouter.Gesture.PINCH)
	_touch(1, Vector2(720, 400), false)
	_touch(0, Vector2(560, 400), false)
	assert(map.zoom_factor != zoom, "a two-finger tap changes the zoom")
	assert(router.fingers.is_empty() and router.gesture == TabletInputRouter.Gesture.NONE)

	# a pinch apart zooms in one step for each step of finger distance
	map.zoom_out()
	zoom = map.zoom_factor
	_touch(0, Vector2(600, 400), true)
	_touch(1, Vector2(680, 400), true)
	_drag(0, Vector2(540, 400), Vector2(-60, 0))
	_drag(1, Vector2(740, 400), Vector2(60, 0))
	_touch(0, Vector2(540, 400), false)
	_touch(1, Vector2(740, 400), false)
	assert(map.zoom_factor > zoom)

	# with a tool, the first finger waits; a second finger makes it a camera gesture
	router.hand = false
	_touch(0, Vector2(600, 400), true)
	assert(router.gesture == TabletInputRouter.Gesture.TOOL_PENDING)
	_touch(1, Vector2(700, 400), true)
	assert(router.gesture == TabletInputRouter.Gesture.PINCH)
	assert(map.selection_start.x < 0, "no tool use starts")
	_touch(1, Vector2(700, 400), false)
	_touch(0, Vector2(600, 400), false)

	# the first speed button is Paused, which the speed enum counts from
	assert(TabletUi.speed_button(GameSpeedController.Speed.PAUSED) == 0)
	assert(TabletUi.speed_button(GameSpeedController.Speed.TURTLE) == 1)
	assert(TabletUi.speed_button(GameSpeedController.Speed.AFRICAN_SWALLOW) == 4)

	# the preferences keep their values in their own file
	var folder := ProjectSettings.globalize_path("user://tablet-input-test-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var preferences := TabletPreferences.for_settings(folder.path_join("settings.cfg"))
	assert(preferences.mode == TabletPreferences.MODE_AUTO and preferences.side_button == TabletPreferences.SIDE_QUERY)
	preferences.mode = TabletPreferences.MODE_ON
	preferences.side_button = TabletPreferences.SIDE_BULLDOZE
	assert(preferences.save_values() == OK)
	var loaded := TabletPreferences.for_settings(folder.path_join("settings.cfg"))
	assert(loaded.enabled() and loaded.side_button == TabletPreferences.SIDE_BULLDOZE)
	DirAccess.remove_absolute(folder.path_join("tablet.cfg"))
	DirAccess.remove_absolute(folder)

	map.queue_free()
	await process_frame
	print("PASS: tablet input sorts pen, palm and finger gestures")
	quit(0)
