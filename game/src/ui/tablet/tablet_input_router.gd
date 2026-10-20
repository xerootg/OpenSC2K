class_name TabletInputRouter
extends RefCounted
## Sorts map input into pen and finger input for the tablet interface.
##
## Godot on Android sends a stylus (and a mouse) as InputEventMouseButton and
## InputEventMouseMotion with a real device id, and fingers as
## InputEventScreenTouch and InputEventScreenDrag. With
## input_devices/pointing/emulate_mouse_from_touch, the first finger also makes
## mouse events with the device InputEvent.DEVICE_ID_EMULATION. Interface
## buttons use those, but the map ignores them and reads the touch events.
##
## A pen near the screen sends mouse motion with no buttons (hover). A pen tap
## with the side button held arrives as a press with MOUSE_BUTTON_NONE, because
## Godot does not map MotionEvent.BUTTON_STYLUS_PRIMARY to a mouse button.
##
## The pen is the precise tool: tap and drag use the tool, hover shows the
## footprint. Fingers move the camera. With no pen, one finger uses an armed
## tool and two fingers move and zoom.

signal hover_changed(position: Vector2, active: bool)
signal finger_used
signal side_action_used(action: String, tile: Vector2i)

# fingers that touch while the pen is near the screen, or this long after, are a palm
const PALM_GRACE_MSEC := 450
# a finger that moves less than this is a tap
const TAP_SLOP := 14.0
# a finger with an armed tool waits this long for a second finger before it uses the tool
const TOOL_START_MSEC := 140
const TWO_FINGER_TAP_MSEC := 320
# a finger that rests this long in the hand tool opens the map menu (the right click)
const LONG_PRESS_MSEC := 550
# the finger distance ratio for one zoom step
const PINCH_STEP := 1.32
const INERTIA_DECAY := 6.0
const INERTIA_MIN_SPEED := 40.0
# device id of the mouse events that the router makes for the map
const SYNTHETIC_DEVICE := 0x7ab1

enum Gesture { NONE, TOOL_PENDING, TOOL, PAN, PINCH, IGNORE }

var map: CityMapControl
# true when no tool is armed. a pen drag and a finger drag move the map
var hand_mode := Callable()
# the action of the pen side button: TabletPreferences.SIDE_QUERY or SIDE_BULLDOZE
var side_button := TabletPreferences.SIDE_QUERY
# a desktop test aid: the left mouse button acts as a finger
var simulate_fingers := false
var last_pen_msec := -100000
var pen_pressed := false
var pen_position := Vector2.ZERO
var pen_seen := false
var gesture := Gesture.NONE
var fingers: Dictionary[int, Vector2] = {}
var _finger_start: Dictionary[int, Vector2] = {}
var _gesture_start_msec := 0
var _tool_finger := -1
var _pinch_distance := 0.0
var _pinch_center := Vector2.ZERO
var _two_finger_moved := false
var _two_finger_start_msec := 0
var _max_fingers := 0
var _velocity := Vector2.ZERO
var _last_drag_msec := 0
var _side_action := ""
var _side_tile := Vector2i(-1, -1)
var _pen_pan := false
var _sim_secondary := false
# InputEventMouseButton has no pen_inverted; the last motion tells it
var _pen_inverted := false
var _long_press_done := false


func _init(map_control: CityMapControl) -> void:
	map = map_control


static func is_emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


static func is_pen(event: InputEvent) -> bool:
	return event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION and event.device != SYNTHETIC_DEVICE


func pen_near() -> bool:
	return pen_pressed or Time.get_ticks_msec() - last_pen_msec < PALM_GRACE_MSEC


# Called from the application input before the interface sees the event.
# Returns true when the event is consumed.
func global_input(event: InputEvent) -> bool:
	if is_pen(event) and not (simulate_fingers and _is_simulated_finger(event)):
		last_pen_msec = Time.get_ticks_msec()
		pen_position = event.position
		pen_seen = true

		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_NONE]:
			pen_pressed = event.pressed

		return false

	var finger := event is InputEventScreenTouch or event is InputEventScreenDrag or (event is InputEventMouse and is_emulated(event))

	if not finger:
		return false

	finger_used.emit()

	# palm rejection: a hand that rests on the screen while the pen writes
	if pen_seen and pen_near():
		if event is InputEventScreenTouch and not event.pressed:
			fingers.erase(event.index)
			_finger_start.erase(event.index)

		return true

	return false


func _is_simulated_finger(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT

	return event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0


# The map pointer filter. Returns true when the map must not handle the event.
func map_input(event: InputEvent) -> bool:
	if event.device == SYNTHETIC_DEVICE:
		return false

	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed, event.canceled)

		return true

	if event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)

		return true

	if not event is InputEventMouse:
		return false

	if is_emulated(event):
		return true

	if simulate_fingers and _simulate_finger(event):
		return true

	return _pen(event)


func _pen(event: InputEventMouse) -> bool:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion

	if motion != null:
		_pen_inverted = motion.pen_inverted
		hover_changed.emit(motion.position, motion.button_mask == 0 and not pen_pressed)

	# the side button, or the eraser end of a pen that reports it
	if button != null and (button.button_index == MOUSE_BUTTON_NONE or (button.button_index == MOUSE_BUTTON_LEFT and _pen_inverted)):
		if button.pressed:
			_begin_side_action(TabletPreferences.SIDE_BULLDOZE if _pen_inverted else side_button, button.position)
		else:
			_side_action = ""

		map.accept_event()

		return true

	if not _side_action.is_empty():
		if motion != null and _side_action == TabletPreferences.SIDE_BULLDOZE:
			_side_sweep(motion.position)

		if button != null and not button.pressed:
			_side_action = ""

		return true

	if button != null and button.button_index == MOUSE_BUTTON_LEFT and _is_hand():
		_pen_pan = button.pressed

		if button.pressed or Time.get_ticks_msec() - _last_drag_msec > 80:
			_velocity = Vector2.ZERO

		map.accept_event()

		return true

	if _pen_pan and motion != null:
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_pen_pan = false

			return false

		_pan(motion.relative)

		return true

	return false


func _begin_side_action(action: String, position: Vector2) -> void:
	_side_action = action
	_side_tile = Vector2i(-1, -1)
	map.cancel_active_selection()
	var tile := map.camera._tile_at(position)

	if tile.x < 0:
		return

	if action == TabletPreferences.SIDE_QUERY:
		map.hover_tile = tile
		map.query_requested.emit(tile)
		side_action_used.emit(action, tile)
		_side_action = "done"
	else:
		_side_sweep(position)


func _side_sweep(position: Vector2) -> void:
	var tile := map.camera._tile_at(position)

	if tile.x < 0 or tile == _side_tile:
		return

	_side_tile = tile
	map.hover_tile = tile
	map.bulldoze_requested.emit(tile)
	side_action_used.emit(TabletPreferences.SIDE_BULLDOZE, tile)


func _is_hand() -> bool:
	return hand_mode.is_valid() and bool(hand_mode.call())


# desktop finger simulation: left drag is one finger, Ctrl+left drag pinches
# around the map center, Shift+Ctrl+left drag moves two fingers together
func _simulate_finger(event: InputEventMouse) -> bool:
	var button := event as InputEventMouseButton

	if button != null:
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false

		_sim_secondary = button.ctrl_pressed
		_touch(0, button.position, button.pressed, false)

		if _sim_secondary:
			_touch(1, _sim_second_point(button), button.pressed, false)

		return true

	var motion := event as InputEventMouseMotion

	if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return false

	_drag(0, motion.position, motion.relative)

	if _sim_secondary:
		var second := _sim_second_point(motion)
		_drag(1, second, second - fingers.get(1, second))

	return true


func _sim_second_point(event: InputEventMouse) -> Vector2:
	if event.shift_pressed:
		return event.position + Vector2(160, 0)

	return map.size - event.position


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool) -> void:
	if pressed:
		fingers[index] = position
		_finger_start[index] = position
		_max_fingers = maxi(_max_fingers, fingers.size())
		_finger_down(index)

		return

	if not fingers.has(index):
		return

	fingers[index] = position
	_finger_up(index, canceled)
	fingers.erase(index)
	_finger_start.erase(index)

	if fingers.is_empty():
		_max_fingers = 0
		gesture = Gesture.NONE


func _finger_down(index: int) -> void:
	var now := Time.get_ticks_msec()
	_velocity = Vector2.ZERO
	map.hover_tile = Vector2i(-1, -1)

	if fingers.size() == 1:
		_gesture_start_msec = now
		_long_press_done = false

		if _is_hand():
			gesture = Gesture.PAN
		else:
			gesture = Gesture.TOOL_PENDING
			_tool_finger = index

		return

	if fingers.size() == 2:
		if gesture == Gesture.TOOL:
			# the second finger turns a tool drag into a camera gesture
			_send_button(fingers[_tool_finger], false, true)

		gesture = Gesture.PINCH
		_two_finger_moved = false
		_two_finger_start_msec = now
		_start_pinch()

		return

	gesture = Gesture.IGNORE


func _start_pinch() -> void:
	var points := fingers.values()
	_pinch_distance = maxf(1.0, (points[0] as Vector2).distance_to(points[1]))
	_pinch_center = ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	if not fingers.has(index):
		return

	fingers[index] = position

	match gesture:
		Gesture.TOOL_PENDING:
			if index == _tool_finger and position.distance_to(_finger_start[index]) > TAP_SLOP:
				_start_tool()
				_send_motion(position)
		Gesture.TOOL:
			if index == _tool_finger:
				_send_motion(position)
		Gesture.PAN:
			_pan(relative)
		Gesture.PINCH:
			if fingers.size() < 2:
				return

			var points := fingers.values()
			var center := ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5
			var distance := maxf(1.0, (points[0] as Vector2).distance_to(points[1]))

			if position.distance_to(_finger_start[index]) > TAP_SLOP:
				_two_finger_moved = true

			_pan(center - _pinch_center)
			_pinch_center = center

			if distance / _pinch_distance >= PINCH_STEP:
				map.zoom_in(center)
				_pinch_distance = distance
			elif _pinch_distance / distance >= PINCH_STEP:
				map.zoom_out(center)
				_pinch_distance = distance


func _finger_up(index: int, canceled: bool) -> void:
	match gesture:
		Gesture.TOOL_PENDING:
			if index == _tool_finger and not canceled:
				# a tap uses the tool once
				_start_tool()
				_send_button(fingers[index], false)
		Gesture.TOOL:
			if index == _tool_finger:
				_send_button(fingers[index], false, canceled)
				gesture = Gesture.IGNORE
		Gesture.PAN:
			# a finger that stops before it lifts does not fling the map
			if fingers.size() > 1 or Time.get_ticks_msec() - _last_drag_msec > 80:
				_velocity = Vector2.ZERO
		Gesture.PINCH:
			if fingers.size() == 2:
				var short := Time.get_ticks_msec() - _two_finger_start_msec <= TWO_FINGER_TAP_MSEC
				# the finger that stays moves the map
				gesture = Gesture.PAN
				_velocity = Vector2.ZERO

				if short and not _two_finger_moved and _max_fingers == 2:
					_cycle_zoom(_pinch_center)


func _start_tool() -> void:
	if gesture != Gesture.TOOL_PENDING:
		return

	gesture = Gesture.TOOL
	_send_button(_finger_start[_tool_finger], true)


func _send_button(position: Vector2, pressed: bool, cancel := false) -> void:
	if cancel:
		map.cancel_active_selection()
		map.hover_tile = Vector2i(-1, -1)

		return

	var event := InputEventMouseButton.new()
	event.device = SYNTHETIC_DEVICE
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = map.get_global_transform() * position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	map.interaction.handle_pointer(event)

	if not pressed:
		map.hover_tile = Vector2i(-1, -1)
		map.queue_redraw()


func _send_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = SYNTHETIC_DEVICE
	event.position = position
	event.global_position = map.get_global_transform() * position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	map.interaction.handle_pointer(event)


func _pan(relative: Vector2) -> void:
	if relative.is_zero_approx():
		return

	map.pan_screen(-relative)
	var now := Time.get_ticks_msec()
	var elapsed := maxf(1.0, float(now - _last_drag_msec)) / 1000.0

	if elapsed < 0.1:
		_velocity = _velocity.lerp(relative / elapsed, 0.5)
	else:
		_velocity = Vector2.ZERO

	_last_drag_msec = now


func _open_context_menu(position: Vector2) -> void:
	var tile := map.camera._tile_at(position)

	if tile.x < 0 or map.context_menu == null:
		return

	gesture = Gesture.IGNORE
	_velocity = Vector2.ZERO
	Input.vibrate_handheld(30)
	map.hover_tile = tile
	map.context_menu.open_at(tile, position)


func _cycle_zoom(center: Vector2) -> void:
	if not map.zoom_in(center):
		while map.zoom_out(center):
			pass


# Starts the tool of a finger that stays still, and moves the map after a fling.
func process(delta: float) -> void:
	if gesture == Gesture.TOOL_PENDING and Time.get_ticks_msec() - _gesture_start_msec >= TOOL_START_MSEC:
		_start_tool()

	if gesture == Gesture.PAN and fingers.size() == 1 and not _long_press_done and _max_fingers == 1:
		var index: int = fingers.keys()[0]

		if fingers[index].distance_to(_finger_start[index]) <= TAP_SLOP:
			if Time.get_ticks_msec() - _gesture_start_msec >= LONG_PRESS_MSEC:
				_long_press_done = true
				_open_context_menu(fingers[index])
		else:
			_long_press_done = true

	if gesture != Gesture.NONE or _pen_pan:
		return

	if _velocity.length() < INERTIA_MIN_SPEED:
		_velocity = Vector2.ZERO

		return

	map.pan_screen(-_velocity * delta)
	_velocity *= exp(-INERTIA_DECAY * delta)


# True while the camera gesture of a finger or the pen hand tool runs.
func is_navigating() -> bool:
	return gesture in [Gesture.PAN, Gesture.PINCH] or _pen_pan or _velocity.length() >= INERTIA_MIN_SPEED
