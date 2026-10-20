class_name TabletPreferences
extends RefCounted
## The touch and pen interface preferences. They are kept in their own file
## beside the main settings file, so the desktop settings format stays the same.

const MODE_AUTO := "auto"
const MODE_ON := "on"
const MODE_OFF := "off"
const MODES: Array[String] = [MODE_AUTO, MODE_ON, MODE_OFF]
const SIDE_QUERY := "query"
const SIDE_BULLDOZE := "bulldoze"
const SIDE_ACTIONS: Array[String] = [SIDE_QUERY, SIDE_BULLDOZE]
const HAND_RIGHT := "right"
const HAND_LEFT := "left"
const SECTION := "tablet"

# auto turns the tablet interface on for phones and tablets
var mode := MODE_AUTO
# the action of a pen tap with the side button held
var side_button := SIDE_QUERY
# the pen hand. the pen tooltip shows on the side away from the hand
var hand := HAND_RIGHT
var path := ""


static func for_settings(settings_path: String) -> TabletPreferences:
	var preferences := TabletPreferences.new()
	preferences.path = settings_path.get_base_dir().path_join("tablet.cfg") if not settings_path.is_empty() else ""
	preferences.load_values()

	return preferences


static func touch_device() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func enabled() -> bool:
	if mode == MODE_ON:
		return true

	if mode == MODE_OFF:
		return false

	return touch_device()


func load_values() -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return

	var file := ConfigFile.new()

	if file.load(path) != OK:
		return

	var saved_mode := str(file.get_value(SECTION, "mode", MODE_AUTO))
	mode = saved_mode if saved_mode in MODES else MODE_AUTO
	var saved_side := str(file.get_value(SECTION, "side_button", SIDE_QUERY))
	side_button = saved_side if saved_side in SIDE_ACTIONS else SIDE_QUERY
	hand = HAND_LEFT if str(file.get_value(SECTION, "hand", HAND_RIGHT)) == HAND_LEFT else HAND_RIGHT


func save_values() -> Error:
	if path.is_empty():
		return ERR_FILE_BAD_PATH

	var file := ConfigFile.new()
	file.set_value(SECTION, "mode", mode)
	file.set_value(SECTION, "side_button", side_button)
	file.set_value(SECTION, "hand", hand)

	return file.save(path)
