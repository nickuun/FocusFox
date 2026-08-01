extends Node
class_name SystemTray

## Windows system-tray icon for Focus Fox. Left-click toggles the launcher,
## right-click opens a small context menu. The launcher hides here instead of
## cluttering the taskbar while a session runs.

signal open_requested()
signal pause_toggle_requested()
signal fox_toggle_requested()
signal quit_requested()

const ICON: Texture2D = preload("res://assets/static/tray icon/headshot.png")

const TAG_HEADER := 100
const TAG_OPEN := 101
const TAG_PAUSE := 102
const TAG_FOX := 103
const TAG_QUIT := 199

var _indicator := -1
var _menu := RID()
var _idx_header := -1
var _idx_open := -1
var _idx_pause := -1
var _idx_fox := -1


func _ready() -> void:
	# Headless / server builds have no display server (and no tray).
	if DisplayServer.get_name() == "headless":
		return
	if not DisplayServer.has_method("create_status_indicator") or not ClassDB.class_exists("NativeMenu"):
		push_warning("System tray not supported on this platform; skipping.")
		return
	_build()


func is_supported() -> bool:
	return _indicator >= 0


func _build() -> void:
	_menu = NativeMenu.create_menu()
	_idx_header = NativeMenu.add_item(_menu, "Focus Fox", Callable(), Callable(), TAG_HEADER)
	NativeMenu.set_item_disabled(_menu, _idx_header, true)
	NativeMenu.add_separator(_menu)
	_idx_open = NativeMenu.add_item(_menu, "Open", _on_item, Callable(), TAG_OPEN)
	_idx_pause = NativeMenu.add_item(_menu, "Pause", _on_item, Callable(), TAG_PAUSE)
	_idx_fox = NativeMenu.add_item(_menu, "Send fox out", _on_item, Callable(), TAG_FOX)
	NativeMenu.add_separator(_menu)
	NativeMenu.add_item(_menu, "Quit", _on_item, Callable(), TAG_QUIT)

	_indicator = DisplayServer.create_status_indicator(ICON, "Focus Fox", _on_click)
	if _indicator >= 0:
		DisplayServer.status_indicator_set_menu(_indicator, _menu)


func update_state(status_text: String, session_running: bool, paused: bool, fox_out: bool, launcher_open: bool) -> void:
	if not is_supported():
		return
	NativeMenu.set_item_text(_menu, _idx_header, status_text)
	NativeMenu.set_item_text(_menu, _idx_open, "Hide window" if launcher_open else "Open window")
	NativeMenu.set_item_disabled(_menu, _idx_pause, not session_running)
	NativeMenu.set_item_text(_menu, _idx_pause, "Resume" if paused else "Pause")
	NativeMenu.set_item_text(_menu, _idx_fox, "Bring fox home" if fox_out else "Send fox out")
	if DisplayServer.has_method("status_indicator_set_tooltip"):
		DisplayServer.status_indicator_set_tooltip(_indicator, "Focus Fox — " + status_text)


func _on_click(_button: int, _position: Vector2i) -> void:
	# Left-click (and any non-menu click) toggles the launcher. The right-click
	# menu is handled natively by the OS via status_indicator_set_menu.
	open_requested.emit()


func _on_item(tag: int) -> void:
	match tag:
		TAG_OPEN:
			open_requested.emit()
		TAG_PAUSE:
			pause_toggle_requested.emit()
		TAG_FOX:
			fox_toggle_requested.emit()
		TAG_QUIT:
			quit_requested.emit()


func _exit_tree() -> void:
	if _indicator >= 0:
		DisplayServer.delete_status_indicator(_indicator)
		_indicator = -1
	if _menu.is_valid():
		NativeMenu.free_menu(_menu)
		_menu = RID()
