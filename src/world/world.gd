extends Node2D

@export_group("Launcher")
@export var launcher_window_size := Vector2i(960, 540)
@export var minimize_delay_after_start := 1.5

enum Mode { HOME, CHOOSE, RUNNING }

const COLOUR_OPTIONS := [
	{"key": "default", "label": "Classic"},
	{"key": "red", "label": "Red"},
	{"key": "gray", "label": "Grey"},
	{"key": "lightbrown", "label": "Light brown"},
	{"key": "darkbrown", "label": "Dark brown"},
	{"key": "black", "label": "Black"},
]

const SESSIONS := {
	"deep": {"label": "Deep focus", "minutes": 45},
	"focus": {"label": "Focus", "minutes": 25},
	"break": {"label": "Break", "minutes": 15},
}

@onready var _desktop_fox: DesktopFox = $DesktopFox
@onready var _preview_fox: RigidBody2D = $MenuLayer/MainMenu/PreviewFox

@onready var _start_button: TextureButton = $MenuLayer/MainMenu/Buttons/StartButton
@onready var _quit_button: TextureButton = $MenuLayer/MainMenu/Buttons/QuitButton
@onready var _deep_button: TextureButton = $MenuLayer/MainMenu/Buttons/DeepButton
@onready var _focus_button: TextureButton = $MenuLayer/MainMenu/Buttons/FocusButton
@onready var _break_button: TextureButton = $MenuLayer/MainMenu/Buttons/BreakButton
@onready var _stop_button: TextureButton = $MenuLayer/MainMenu/Buttons/StopButton
@onready var _pause_button: TextureButton = $MenuLayer/MainMenu/Buttons/PauseButton
@onready var _pause_label: Label = $MenuLayer/MainMenu/Buttons/PauseButton/Label
@onready var _bring_home_button: TextureButton = $MenuLayer/MainMenu/Buttons/BringHomeButton

@onready var _timer_label: Label = $MenuLayer/MainMenu/TimerLabel
@onready var _session_label: Label = $MenuLayer/MainMenu/SessionLabel
@onready var _status_label: Label = $MenuLayer/MainMenu/StatusLabel

@onready var _settings_icon_button: TextureButton = $MenuLayer/MainMenu/SettingsIconButton
@onready var _settings_panel: FoxSettingsPanel = $MenuLayer/MainMenu/SettingsPanel
@onready var _settings_close_button: Button = $MenuLayer/MainMenu/SettingsPanel/CloseButton

var _mode := Mode.HOME
var _is_starting := false
var _syncing_ui := false
var _minimize_token := 0
var _clock: PomodoroTimer
var _tray: SystemTray
var _save_debounce: Timer


const SETTINGS_PATH := "user://focus_fox.cfg"


func _ready() -> void:
	randomize()
	# Closing the launcher tucks it into the tray instead of quitting the app.
	get_tree().set_auto_accept_quit(false)
	_setup_launcher_window()
	_setup_save()
	_setup_clock()
	_setup_tray()
	_setup_menu_nodes()
	_configure_desktop_fox()
	_load_settings()
	_desktop_fox.initialize()
	_preview_fox.freeze = true
	_preview_fox.call("set_highlight", false, _desktop_fox.hover_modulate)
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_preview_fox.modulate.a = _desktop_fox.fox_opacity
	_set_mode(Mode.HOME)
	_refresh_ui()


func _exit_tree() -> void:
	_save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _tray != null and _tray.is_supported():
			_hide_to_tray()
		else:
			get_tree().quit()


func _physics_process(delta: float) -> void:
	_desktop_fox.physics_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _mode != Mode.HOME or not is_instance_valid(_preview_fox) or not _preview_fox.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _preview_fox.global_position.distance_to(get_global_mouse_position()) <= _desktop_fox.get_fox_radius(_preview_fox):
			_preview_fox.call("pulse_click")


func _setup_clock() -> void:
	_clock = PomodoroTimer.new()
	_clock.name = "SessionClock"
	add_child(_clock)
	_clock.tick.connect(_on_clock_tick)
	_clock.finished.connect(_on_clock_finished)
	_clock.paused_changed.connect(_on_clock_paused_changed)


func _setup_tray() -> void:
	_tray = SystemTray.new()
	_tray.name = "SystemTray"
	add_child(_tray)
	_tray.open_requested.connect(_on_tray_open)
	_tray.pause_toggle_requested.connect(_on_tray_pause)
	_tray.fox_toggle_requested.connect(_on_tray_fox_toggle)
	_tray.quit_requested.connect(_on_tray_quit)


func _setup_launcher_window() -> void:
	RenderingServer.set_default_clear_color(Color.TRANSPARENT)
	get_viewport().transparent_bg = false

	var window := get_window()
	window.title = "Focus Fox"
	window.borderless = false
	window.always_on_top = false
	window.transparent = false
	window.transparent_bg = false
	window.unresizable = false
	window.gui_embed_subwindows = false
	window.size = launcher_window_size

	var usable_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	window.position = usable_rect.position + (usable_rect.size - launcher_window_size) / 2

	# Use the fox headshot as the window (title bar + taskbar) icon too.
	if DisplayServer.get_name() != "headless":
		var icon_image := SystemTray.ICON.get_image()
		if icon_image != null:
			DisplayServer.set_icon(icon_image)


func _setup_menu_nodes() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_deep_button.pressed.connect(_on_session_chosen.bind("deep"))
	_focus_button.pressed.connect(_on_session_chosen.bind("focus"))
	_break_button.pressed.connect(_on_session_chosen.bind("break"))
	_stop_button.pressed.connect(_on_stop_pressed)
	_pause_button.pressed.connect(_on_pause_pressed)
	_bring_home_button.pressed.connect(_on_bring_home_pressed)
	_settings_icon_button.pressed.connect(_on_settings_pressed)
	_settings_close_button.pressed.connect(_hide_settings_panel)
	_settings_panel.click_through_toggle.toggled.connect(_on_click_through_toggled)
	_settings_panel.hover_fade_toggle.toggled.connect(_on_hover_fade_toggled)
	_settings_panel.taskbar_snap_toggle.toggled.connect(_on_taskbar_snap_toggled)
	_settings_panel.scale_slider.value_changed.connect(_on_scale_changed)
	_settings_panel.opacity_slider.value_changed.connect(_on_opacity_changed)
	_settings_panel.liveliness_slider.value_changed.connect(_on_liveliness_changed)
	_settings_panel.taskbar_height_slider.value_changed.connect(_on_taskbar_height_changed)
	for option in COLOUR_OPTIONS:
		_settings_panel.colour_option.add_item(option["label"])
	_settings_panel.colour_option.item_selected.connect(_on_colour_selected)
	_settings_panel.reset_fox_button.pressed.connect(_on_reset_fox_pressed)
	_settings_panel.spawn_fox_button.pressed.connect(_on_spawn_fox_pressed)
	_settings_panel.hide_fox_button.pressed.connect(_on_hide_fox_pressed)
	_settings_panel.reset_all_button.pressed.connect(_on_reset_all_pressed)
	_desktop_fox.fox_spawned_changed.connect(_on_fox_spawned_changed)


func _configure_desktop_fox() -> void:
	_desktop_fox.fox_scale = 2.0
	_desktop_fox.fox_opacity = 1.0
	_desktop_fox.click_through_enabled = false
	_desktop_fox.hover_fade_enabled = false
	_desktop_fox.taskbar_snap_enabled = true
	_desktop_fox.taskbar_height = 24.0
	_desktop_fox.body_speed_multiplier = 1.0
	_desktop_fox.fox_palette = "default"


# --- Menu mode -------------------------------------------------------------

func _set_mode(mode: Mode) -> void:
	_mode = mode
	var home := mode == Mode.HOME
	var choose := mode == Mode.CHOOSE
	var running := mode == Mode.RUNNING

	_preview_fox.visible = home and not _desktop_fox.is_spawned()
	_start_button.visible = home
	_quit_button.visible = home

	_deep_button.visible = choose
	_focus_button.visible = choose
	_break_button.visible = choose
	_status_label.visible = choose

	_stop_button.visible = running
	_pause_button.visible = running
	_session_label.visible = running
	_timer_label.visible = running

	_bring_home_button.visible = choose or running
	_update_tray()
	_update_fox_activity()


func _on_start_pressed() -> void:
	if _is_starting or _desktop_fox.is_spawned():
		return
	_is_starting = true
	_preview_fox.call("pulse_click")
	await get_tree().create_timer(0.14).timeout
	# Drop the fox onto the desktop but keep the launcher open so the user can
	# choose what kind of session they're starting.
	_desktop_fox.spawn_fox(_desktop_fox.get_preview_screen_position(_preview_fox))
	_is_starting = false


func _on_session_chosen(id: String) -> void:
	if not SESSIONS.has(id):
		return
	var session: Dictionary = SESSIONS[id]
	var minutes: float = session["minutes"]
	_clock.start(minutes * 60.0, id, session["label"])
	_session_label.text = session["label"]
	_pause_label.text = "Pause"
	_timer_label.modulate = Color.WHITE
	_timer_label.text = _format_time(_clock.remaining())
	_set_mode(Mode.RUNNING)
	if is_instance_valid(_desktop_fox) and _desktop_fox.is_spawned():
		_desktop_fox.celebrate()
	_queue_minimize()


func _queue_minimize() -> void:
	_minimize_token += 1
	var token := _minimize_token
	await get_tree().create_timer(minimize_delay_after_start).timeout
	# Only tuck the launcher away if the session is still the one we queued for.
	if token == _minimize_token and _mode == Mode.RUNNING and _clock.is_running() and not _clock.is_paused():
		_hide_to_tray()


func _on_stop_pressed() -> void:
	_clock.stop()
	_set_mode(Mode.CHOOSE)
	_status_label.text = "Stopped — pick another, or bring the fox home."


func _on_pause_pressed() -> void:
	_clock.toggle_pause()


func _on_clock_paused_changed(paused: bool) -> void:
	_pause_label.text = "Resume" if paused else "Pause"
	_session_label.text = "%s · paused" % _clock.session_label if paused else _clock.session_label
	_timer_label.modulate = Color(1, 1, 1, 0.5) if paused else Color.WHITE
	_update_tray()
	_update_fox_activity()


func _on_bring_home_pressed() -> void:
	_clock.stop()
	_desktop_fox.despawn_fox()


func _on_clock_tick(remaining: float) -> void:
	_timer_label.text = _format_time(remaining)
	_update_tray()


func _on_clock_finished() -> void:
	_minimize_token += 1
	_show_launcher()
	if _desktop_fox.is_spawned():
		_desktop_fox.celebrate()
	_set_mode(Mode.CHOOSE)
	_status_label.text = "%s done — nice work. Ready for what's next?" % _clock.session_label


func _hide_to_tray() -> void:
	# The root window's visibility can't be toggled (it has no parent), so we
	# minimize it. The tray icon is the way back.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _show_launcher() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().move_to_foreground()
	DisplayServer.window_request_attention()


# --- System tray -----------------------------------------------------------

func _update_tray() -> void:
	if _tray == null:
		return
	var fox_out := _desktop_fox.is_spawned()
	var running := _clock.is_running()
	var paused := _clock.is_paused()
	var status := "Resting"
	if running:
		status = "%s · %s" % [_clock.session_label, _format_time(_clock.remaining())]
		if paused:
			status += " (paused)"
	elif fox_out:
		status = "Fox is out"
	_tray.update_state(status, running, paused, fox_out)


func _on_tray_open() -> void:
	_show_launcher()


func _on_tray_pause() -> void:
	if _clock.is_running():
		_clock.toggle_pause()


func _on_tray_fox_toggle() -> void:
	if _desktop_fox.is_spawned():
		_on_bring_home_pressed()
	else:
		_desktop_fox.spawn_at_screen_center()


func _on_tray_quit() -> void:
	get_tree().quit()


# --- Persistence -----------------------------------------------------------

func _setup_save() -> void:
	_save_debounce = Timer.new()
	_save_debounce.name = "SaveDebounce"
	_save_debounce.one_shot = true
	_save_debounce.timeout.connect(_save_settings)
	add_child(_save_debounce)


func _request_save() -> void:
	# Coalesce rapid changes (slider drags) into a single write shortly after.
	if _save_debounce != null:
		_save_debounce.start(0.4)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("fox", "scale", _desktop_fox.fox_scale)
	cfg.set_value("fox", "opacity", _desktop_fox.fox_opacity)
	cfg.set_value("fox", "liveliness", _desktop_fox.body_speed_multiplier)
	cfg.set_value("fox", "palette", _desktop_fox.fox_palette)
	cfg.set_value("behaviour", "click_through", _desktop_fox.click_through_enabled)
	cfg.set_value("behaviour", "hover_fade", _desktop_fox.hover_fade_enabled)
	cfg.set_value("behaviour", "taskbar_snap", _desktop_fox.taskbar_snap_enabled)
	cfg.set_value("behaviour", "taskbar_height", _desktop_fox.taskbar_height)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_desktop_fox.fox_scale = float(cfg.get_value("fox", "scale", _desktop_fox.fox_scale))
	_desktop_fox.fox_opacity = float(cfg.get_value("fox", "opacity", _desktop_fox.fox_opacity))
	_desktop_fox.body_speed_multiplier = float(cfg.get_value("fox", "liveliness", _desktop_fox.body_speed_multiplier))
	_desktop_fox.fox_palette = str(cfg.get_value("fox", "palette", _desktop_fox.fox_palette))
	_desktop_fox.click_through_enabled = bool(cfg.get_value("behaviour", "click_through", _desktop_fox.click_through_enabled))
	_desktop_fox.hover_fade_enabled = bool(cfg.get_value("behaviour", "hover_fade", _desktop_fox.hover_fade_enabled))
	_desktop_fox.taskbar_snap_enabled = bool(cfg.get_value("behaviour", "taskbar_snap", _desktop_fox.taskbar_snap_enabled))
	_desktop_fox.taskbar_height = float(cfg.get_value("behaviour", "taskbar_height", _desktop_fox.taskbar_height))


func _update_fox_activity() -> void:
	if not _desktop_fox.is_spawned():
		return
	var activity := "idle"
	if _clock.is_running() and not _clock.is_paused():
		activity = "break" if _clock.session_id == "break" else "working"
	_desktop_fox.set_activity(activity)


func _format_time(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


# --- Settings panel --------------------------------------------------------

func _on_settings_pressed() -> void:
	_settings_panel.visible = true


func _hide_settings_panel() -> void:
	_settings_panel.visible = false


func _on_click_through_toggled(enabled: bool) -> void:
	if _syncing_ui:
		return
	_desktop_fox.click_through_enabled = enabled
	_desktop_fox.apply_visual_settings()
	_request_save()


func _on_hover_fade_toggled(enabled: bool) -> void:
	if _syncing_ui:
		return
	_desktop_fox.hover_fade_enabled = enabled
	_desktop_fox.apply_visual_settings()
	_request_save()


func _on_taskbar_snap_toggled(enabled: bool) -> void:
	if _syncing_ui:
		return
	_desktop_fox.taskbar_snap_enabled = enabled
	_refresh_ui()
	_desktop_fox.reset_fox_position()
	_request_save()


func _on_scale_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_scale = maxf(1.0, roundf(value))
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_refresh_ui()
	_request_save()


func _on_opacity_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_opacity = value
	_desktop_fox.apply_visual_settings()
	_preview_fox.modulate.a = value
	_request_save()


func _on_liveliness_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.body_speed_multiplier = value
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_request_save()


func _on_colour_selected(index: int) -> void:
	if _syncing_ui or index < 0 or index >= COLOUR_OPTIONS.size():
		return
	_desktop_fox.fox_palette = COLOUR_OPTIONS[index]["key"]
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_request_save()


func _on_taskbar_height_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.taskbar_height = value
	_refresh_ui()
	_desktop_fox.reset_fox_position()
	_request_save()


func _on_reset_fox_pressed() -> void:
	_desktop_fox.reset_fox_position()


func _on_spawn_fox_pressed() -> void:
	if _desktop_fox.is_spawned():
		return
	_desktop_fox.spawn_at_screen_center()


func _on_hide_fox_pressed() -> void:
	_on_bring_home_pressed()


func _on_reset_all_pressed() -> void:
	_configure_desktop_fox()
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_preview_fox.modulate.a = _desktop_fox.fox_opacity
	_refresh_ui()
	_request_save()


func _on_fox_spawned_changed(active: bool) -> void:
	if active:
		if _mode == Mode.HOME:
			_set_mode(Mode.CHOOSE)
			_status_label.text = "What are you settling into?"
	else:
		_clock.stop()
		_set_mode(Mode.HOME)
	_refresh_ui()


func _refresh_ui() -> void:
	_syncing_ui = true
	var spawned := _desktop_fox.is_spawned()
	_settings_panel.fox_status_label.text = "Fox: active" if spawned else "Fox: menu preview"
	_settings_panel.scale_slider.value = _desktop_fox.fox_scale
	_settings_panel.opacity_slider.value = _desktop_fox.fox_opacity
	_settings_panel.liveliness_slider.value = _desktop_fox.body_speed_multiplier
	_settings_panel.taskbar_height_slider.value = _desktop_fox.taskbar_height
	_settings_panel.taskbar_snap_toggle.button_pressed = _desktop_fox.taskbar_snap_enabled
	_settings_panel.click_through_toggle.button_pressed = _desktop_fox.click_through_enabled
	_settings_panel.hover_fade_toggle.button_pressed = _desktop_fox.hover_fade_enabled
	var palette_index := 0
	for i in COLOUR_OPTIONS.size():
		if COLOUR_OPTIONS[i]["key"] == _desktop_fox.fox_palette:
			palette_index = i
	_settings_panel.colour_option.selected = palette_index
	_syncing_ui = false
