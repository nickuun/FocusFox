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
	{"key": "rainbow", "label": "Rainbow"},
]

# Pomodoro session types. Durations live in _session_minutes (user-configurable).
const SESSION_META := {
	"focus": {"label": "Focus", "is_break": false},
	"short": {"label": "Short break", "is_break": true},
	"long": {"label": "Long break", "is_break": true},
}
const SESSIONS_BEFORE_LONG := 4
const DEFAULT_MINUTES := {"focus": 25, "short": 5, "long": 15}
const CLOCK_DIAL_INTRO_SECONDS := 0.28
const CLOCK_DIAL_INTRO_START_SCALE := 0.08

@onready var _desktop_fox: DesktopFox = $DesktopFox
@onready var _preview_fox: RigidBody2D = $MenuLayer/MainMenu/PreviewFox

@onready var _start_button: TextureButton = $MenuLayer/MainMenu/Buttons/StartButton
@onready var _quit_button: TextureButton = $MenuLayer/MainMenu/Buttons/QuitButton
@onready var _short_button: TextureButton = $MenuLayer/MainMenu/Buttons/DeepButton
@onready var _focus_button: TextureButton = $MenuLayer/MainMenu/Buttons/FocusButton
@onready var _long_button: TextureButton = $MenuLayer/MainMenu/Buttons/BreakButton
@onready var _short_choice_label: Label = $MenuLayer/MainMenu/Buttons/DeepButton/Label
@onready var _focus_choice_label: Label = $MenuLayer/MainMenu/Buttons/FocusButton/Label
@onready var _long_choice_label: Label = $MenuLayer/MainMenu/Buttons/BreakButton/Label
@onready var _stop_button: TextureButton = $MenuLayer/MainMenu/Buttons/StopButton
@onready var _pause_button: TextureButton = $MenuLayer/MainMenu/Buttons/PauseButton
@onready var _pause_label: Label = $MenuLayer/MainMenu/Buttons/PauseButton/Label
@onready var _bring_home_button: TextureButton = $MenuLayer/MainMenu/Buttons/BringHomeButton

@onready var _timer_label: Label = $MenuLayer/MainMenu/TimerLabel
@onready var _session_label: Label = $MenuLayer/MainMenu/SessionLabel
@onready var _status_label: Label = $MenuLayer/MainMenu/StatusLabel
@onready var _task_input: LineEdit = $MenuLayer/MainMenu/TaskInput

@onready var _settings_icon_button: TextureButton = $MenuLayer/MainMenu/SettingsIconButton
@onready var _settings_panel: FoxSettingsPanel = $MenuLayer/MainMenu/SettingsPanel

@onready var _main_menu: Node2D = $MenuLayer/MainMenu
@onready var _background: Sprite2D = $MenuLayer/MainMenu/Background
@onready var _title: Sprite2D = $MenuLayer/MainMenu/Title
@onready var _stats_today_value: Label = $MenuLayer/MainMenu/MainmenuStatsPanel/TodayValue
@onready var _stats_week_value: Label = $MenuLayer/MainMenu/MainmenuStatsPanel/WeekValue
@onready var _stats_total_header: Label = $MenuLayer/MainMenu/MainmenuStatsPanel/TotalHeader
@onready var _journal_icon: TextureButton = $MenuLayer/JournalIcon
@onready var _journal_panel: JournalPanel = $MenuLayer/JournalPanel
@onready var _clock_dial: Sprite2D = $MenuLayer/ClockDial

const JOURNAL_ICON := preload("res://assets/main_menu/icons/journal-icon.png")
const HOME_ICON := preload("res://assets/main_menu/icons/home-icon.png")
const BTN_NORMAL := preload("res://assets/main_menu/default_button.png")
const BTN_HILITE := preload("res://assets/main_menu/default_button - hovered.png")

var _mode := Mode.HOME
var _is_starting := false
var _syncing_ui := false
var _minimize_token := 0
var _clock: PomodoroTimer
var _tray: SystemTray
var _save_debounce: Timer
var _stats: StatsStore
var _den: Den
var _reset_dialog: ConfirmationDialog
var _journal_open := false
var _intro_running := false
var _launcher_parked := false           # tucked off-screen into the tray
var _launcher_home := Vector2i.ZERO     # on-screen position to restore it to
var _session_started_at := 0
var _session_minutes := {"focus": 25.0, "short": 5.0, "long": 15.0}
var _cycle_focus_count := 0  # completed focus sessions in the current Pomodoro set
var _last_completed := ""     # "focus" / "short" / "long" / "" — drives the next-move hint
var _current_task := ""
var _clock_dial_base_scale := Vector2.ONE
var _clock_dial_intro_tween: Tween


const SETTINGS_PATH := "user://focus_fox.cfg"


func _ready() -> void:
	randomize()
	# Closing the launcher tucks it into the tray instead of quitting the app.
	get_tree().set_auto_accept_quit(false)
	_stats = StatsStore.new()
	_stats.load()
	Achievements.on_first_launch()
	_setup_launcher_window()
	_setup_overlay_owner()
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
	_clock_dial_base_scale = _clock_dial.scale
	_set_mode(Mode.HOME)
	_refresh_ui()
	_refresh_stats_bar()
	_refresh_session_buttons()
	_setup_dialogs()
	_setup_den()
	_play_intro()


func _exit_tree() -> void:
	_save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Achievements.on_app_closing(_mode == Mode.RUNNING)
		if _tray != null and _tray.is_supported():
			_hide_to_tray()
		else:
			get_tree().quit()


func _physics_process(delta: float) -> void:
	_keep_launcher_unminimized()
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


func _setup_overlay_owner() -> void:
	# The launcher owns every desktop overlay, which keeps the fox and the ball out
	# of the taskbar and alt-tab and keeps the whole app down to a single entry —
	# any other owner would need an entry of its own. The price is that the launcher
	# can never truly minimize; see _hide_to_tray.
	_launcher_home = get_window().position
	_desktop_fox.overlay_owner = get_window()
	# That single entry stays in the taskbar and alt-tab while the launcher is parked
	# off-screen, so activating it has to bring the launcher back — otherwise clicking
	# our own taskbar button would appear to do nothing.
	get_window().focus_entered.connect(_on_launcher_focus_entered)


func _setup_menu_nodes() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_short_button.pressed.connect(_on_session_chosen.bind("short"))
	_focus_button.pressed.connect(_on_session_chosen.bind("focus"))
	_long_button.pressed.connect(_on_session_chosen.bind("long"))
	_stop_button.pressed.connect(_on_stop_pressed)
	_pause_button.pressed.connect(_on_pause_pressed)
	_bring_home_button.pressed.connect(_on_bring_home_pressed)
	_settings_icon_button.pressed.connect(_on_settings_pressed)
	_settings_panel.close_button.pressed.connect(_hide_settings_panel)
	_journal_icon.pressed.connect(_on_journal_pressed)
	_settings_panel.scale_slider.value_changed.connect(_on_scale_changed)
	_settings_panel.opacity_slider.value_changed.connect(_on_opacity_changed)
	_settings_panel.liveliness_slider.value_changed.connect(_on_liveliness_changed)
	_settings_panel.sit_height_slider.value_changed.connect(_on_sit_height_changed)
	_settings_panel.focus_length_slider.value_changed.connect(_on_length_changed.bind("focus"))
	_settings_panel.short_length_slider.value_changed.connect(_on_length_changed.bind("short"))
	_settings_panel.long_length_slider.value_changed.connect(_on_length_changed.bind("long"))
	_settings_panel.mute_toggle.toggled.connect(_on_mute_toggled)
	_settings_panel.volume_slider.value_changed.connect(_on_volume_changed)
	_settings_panel.reset_data_button.pressed.connect(_on_reset_data_pressed)
	for option in COLOUR_OPTIONS:
		_settings_panel.colour_option.add_item(option["label"])
	_settings_panel.colour_option.item_selected.connect(_on_colour_selected)
	_settings_panel.reset_fox_button.pressed.connect(_on_reset_fox_pressed)
	_settings_panel.spawn_fox_button.pressed.connect(_on_spawn_fox_pressed)
	_settings_panel.hide_fox_button.pressed.connect(_on_hide_fox_pressed)
	_settings_panel.reset_all_button.pressed.connect(_on_reset_all_pressed)
	_desktop_fox.fox_spawned_changed.connect(_on_fox_spawned_changed)


func _setup_dialogs() -> void:
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset game data?"
	_reset_dialog.dialog_text = "This erases your journal stats, streaks and den.\nThis can't be undone."
	_reset_dialog.ok_button_text = "Reset"
	_reset_dialog.confirmed.connect(_do_reset_data)
	add_child(_reset_dialog)


func _setup_den() -> void:
	_den = Den.new()
	_den.name = "Den"
	_main_menu.add_child(_den)
	_den.refresh(_stats.total_focus(), false)


func _configure_desktop_fox() -> void:
	_desktop_fox.fox_scale = 2.0
	_desktop_fox.fox_opacity = 1.0
	_desktop_fox.click_through_enabled = false
	_desktop_fox.hover_fade_enabled = false
	_desktop_fox.sit_height = 48.0  # feet rest above the screen bottom; clears a taskbar
	_desktop_fox.body_speed_multiplier = 1.0
	_desktop_fox.fox_palette = "default"


# --- Menu mode -------------------------------------------------------------

func _set_mode(mode: Mode) -> void:
	var entering_running := mode == Mode.RUNNING and _mode != Mode.RUNNING
	_mode = mode
	var home := mode == Mode.HOME
	var choose := mode == Mode.CHOOSE
	var running := mode == Mode.RUNNING

	_preview_fox.visible = home and not _desktop_fox.is_spawned()
	_start_button.visible = home
	_quit_button.visible = home

	_short_button.visible = choose
	_focus_button.visible = choose
	_long_button.visible = choose
	_status_label.visible = choose
	_task_input.visible = choose

	_stop_button.visible = running
	_pause_button.visible = running
	_session_label.visible = running
	_timer_label.visible = running
	_clock_dial.visible = running
	if entering_running:
		_play_clock_dial_intro()
	elif not running:
		_reset_clock_dial_intro()

	_bring_home_button.visible = choose or running
	if choose:
		_apply_recommendation()
	_update_tray()
	_update_fox_activity()
	_update_ambient()


func _update_ambient() -> void:
	if _clock != null and _clock.is_running() and not _clock.is_paused() and not _is_break(_clock.session_id):
		Audio.play_ambient("focus")
	else:
		Audio.stop_ambient()


func _on_start_pressed() -> void:
	if _intro_running or _is_starting or _desktop_fox.is_spawned():
		return
	Audio.play("click")
	_is_starting = true
	_preview_fox.call("pulse_click")
	await get_tree().create_timer(0.14).timeout
	# Drop the fox onto the desktop but keep the launcher open so the user can
	# choose what kind of session they're starting.
	_desktop_fox.spawn_fox(_desktop_fox.get_preview_screen_position(_preview_fox))
	_is_starting = false


func _on_session_chosen(id: String) -> void:
	if not SESSION_META.has(id):
		return
	var label: String = SESSION_META[id]["label"]
	var minutes: float = _session_minutes.get(id, DEFAULT_MINUTES.get(id, 25))
	_current_task = _task_input.text.strip_edges() if id == "focus" else ""
	Audio.play("start")
	Achievements.on_session_started(id)
	_session_started_at = int(Time.get_unix_time_from_system())
	_clock.start(minutes * 60.0, id, label)
	_session_label.text = _running_session_label(id, label)
	_pause_label.text = "Pause"
	_timer_label.modulate = Color.WHITE
	_timer_label.text = _format_time(_clock.remaining())
	_update_clock_dial()
	_set_mode(Mode.RUNNING)
	if is_instance_valid(_desktop_fox) and _desktop_fox.is_spawned():
		_desktop_fox.celebrate()
	_queue_minimize()


func _running_session_label(id: String, label: String) -> String:
	if id == "focus" and _current_task != "":
		return "%s · %s" % [label, _current_task]
	return label


func _queue_minimize() -> void:
	_minimize_token += 1
	var token := _minimize_token
	await get_tree().create_timer(minimize_delay_after_start).timeout
	# Only tuck the launcher away if the session is still the one we queued for.
	if token == _minimize_token and _mode == Mode.RUNNING and _clock.is_running() and not _clock.is_paused():
		_hide_to_tray()


func _on_stop_pressed() -> void:
	Audio.play("back")
	Achievements.on_session_ended_early()
	_clock.stop()
	_set_mode(Mode.CHOOSE)
	_status_label.text = Encouragements.pick("early_exit")


func _on_pause_pressed() -> void:
	Audio.play("click")
	_clock.toggle_pause()


func _on_clock_paused_changed(paused: bool) -> void:
	_pause_label.text = "Resume" if paused else "Pause"
	_session_label.text = "%s · paused" % _clock.session_label if paused else _clock.session_label
	_timer_label.modulate = Color(1, 1, 1, 0.5) if paused else Color.WHITE
	_update_tray()
	_update_fox_activity()
	_update_ambient()


func _on_bring_home_pressed() -> void:
	Audio.play("click")
	Achievements.on_bring_fox_home()
	_clock.stop()
	_desktop_fox.despawn_fox()


func _on_clock_tick(remaining: float) -> void:
	_timer_label.text = _format_time(remaining)
	_update_clock_dial()
	_update_tray()


func _update_clock_dial() -> void:
	# The dial fills as the session elapses (0 = just started, 1 = complete).
	var mat := _clock_dial.material as ShaderMaterial
	if mat == null:
		return
	var elapsed := 0.0
	if _clock.total_seconds > 0.0:
		elapsed = clampf(1.0 - _clock.remaining() / _clock.total_seconds, 0.0, 1.0)
	mat.set_shader_parameter("fill", elapsed)


func _play_clock_dial_intro() -> void:
	_reset_clock_dial_intro()
	_clock_dial.scale = _clock_dial_base_scale * CLOCK_DIAL_INTRO_START_SCALE
	_clock_dial.modulate.a = 0.0
	_clock_dial_intro_tween = create_tween().set_parallel(true)
	_clock_dial_intro_tween.tween_property(_clock_dial, "scale", _clock_dial_base_scale, CLOCK_DIAL_INTRO_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_clock_dial_intro_tween.tween_property(_clock_dial, "modulate:a", 1.0, CLOCK_DIAL_INTRO_SECONDS * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _reset_clock_dial_intro() -> void:
	if _clock_dial_intro_tween != null and _clock_dial_intro_tween.is_valid():
		_clock_dial_intro_tween.kill()
	_clock_dial_intro_tween = null
	_clock_dial.scale = _clock_dial_base_scale
	_clock_dial.modulate.a = 1.0


func _on_clock_finished() -> void:
	# Only completed sessions count towards the journal + the Pomodoro cycle.
	var id := _clock.session_id
	var encouragement := ""
	if _is_break(id):
		_stats.record_break(_session_started_at)
		_last_completed = id
		if id == "long":
			_cycle_focus_count = 0
		encouragement = Encouragements.pick("break")
	else:
		_stats.record_focus(_clock.total_seconds, _session_started_at, _current_task)
		_cycle_focus_count += 1
		_last_completed = "focus"
		_current_task = ""
		# Check whether the fox slept the whole session without being disturbed.
		if _desktop_fox.is_spawned() and not Achievements._fox_clicked_this_session:
			Achievements.on_sleepy_session_completed()
		Achievements.on_session_completed(_clock.total_seconds, id, _stats)
		encouragement = Encouragements.pick("focus")
	Audio.play("complete")
	_refresh_stats_bar()
	if _journal_open:
		_journal_panel.refresh(_stats)
	if _den != null:
		_den.refresh(_stats.total_focus(), true)
	_minimize_token += 1
	_show_launcher()
	if _desktop_fox.is_spawned():
		_desktop_fox.celebrate()
	# _set_mode(CHOOSE) applies the next-move recommendation + status text,
	# then we overwrite it with a warm encouragement for this completion moment.
	_set_mode(Mode.CHOOSE)
	_status_label.text = encouragement


func _hide_to_tray() -> void:
	# Parked off-screen rather than minimized: the launcher owns the overlay windows
	# and Windows hides a window's owned children when it is minimized, so a real
	# minimize would take the fox down with it. The tray icon is the way back.
	if _launcher_parked:
		return
	_launcher_home = get_window().position
	_launcher_parked = true
	get_window().position = OverlayWindow.offscreen_point()
	_update_tray()


func _show_launcher() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if _launcher_parked:
		_launcher_parked = false
		get_window().position = _launcher_home
	get_window().move_to_foreground()
	DisplayServer.window_request_attention()
	_update_tray()


func _on_launcher_focus_entered() -> void:
	if _launcher_parked:
		_show_launcher()


func _keep_launcher_unminimized() -> void:
	# Nothing in the app minimizes the launcher, but the OS still can — Win+D,
	# show-desktop, or clicking our taskbar button while it has focus — and that
	# would hide the fox along with it. Un-minimize immediately: while parked the
	# launcher is invisible anyway, so the restore costs nothing on screen, and a
	# minimize the user asked for is honoured by tucking it to the tray instead.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if _launcher_parked:
		# The restore puts it back on screen; park it again.
		get_window().position = OverlayWindow.offscreen_point()
	else:
		_hide_to_tray()
	_desktop_fox.reassert_overlays()


func _is_launcher_open() -> bool:
	return not _launcher_parked and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED


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
	_tray.update_state(status, running, paused, fox_out, _is_launcher_open())


func _on_tray_open() -> void:
	# Toggle, so clicking the tray icon repeatedly shows and hides the launcher
	# instead of only ever showing it.
	if _is_launcher_open():
		_hide_to_tray()
	else:
		_show_launcher()


func _on_tray_pause() -> void:
	if _clock.is_running():
		_clock.toggle_pause()


func _on_tray_fox_toggle() -> void:
	if _desktop_fox.is_spawned():
		_on_bring_home_pressed()
		# The fox's home is the den, so show it — otherwise the fox just disappears
		# off the desktop with nothing to show where it went.
		_show_launcher()
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
	cfg.set_value("behaviour", "sit_height", _desktop_fox.sit_height)
	cfg.set_value("pomodoro", "focus", _session_minutes["focus"])
	cfg.set_value("pomodoro", "short", _session_minutes["short"])
	cfg.set_value("pomodoro", "long", _session_minutes["long"])
	cfg.set_value("audio", "muted", Audio.muted)
	cfg.set_value("audio", "volume", Audio.volume)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_desktop_fox.fox_scale = float(cfg.get_value("fox", "scale", _desktop_fox.fox_scale))
	_desktop_fox.fox_opacity = float(cfg.get_value("fox", "opacity", _desktop_fox.fox_opacity))
	_desktop_fox.body_speed_multiplier = float(cfg.get_value("fox", "liveliness", _desktop_fox.body_speed_multiplier))
	_desktop_fox.fox_palette = str(cfg.get_value("fox", "palette", _desktop_fox.fox_palette))
	_desktop_fox.sit_height = float(cfg.get_value("behaviour", "sit_height", _desktop_fox.sit_height))
	for id in _session_minutes:
		_session_minutes[id] = float(cfg.get_value("pomodoro", id, _session_minutes[id]))
	Audio.set_muted(bool(cfg.get_value("audio", "muted", Audio.muted)))
	Audio.set_volume(float(cfg.get_value("audio", "volume", Audio.volume)))


func _update_fox_activity() -> void:
	if not _desktop_fox.is_spawned():
		return
	var activity := "idle"
	if _clock.is_running() and not _clock.is_paused():
		activity = "break" if _is_break(_clock.session_id) else "working"
	_desktop_fox.set_activity(activity)


func _is_break(id: String) -> bool:
	return SESSION_META.has(id) and SESSION_META[id]["is_break"]


func _format_time(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


# --- Settings panel --------------------------------------------------------

func _on_settings_pressed() -> void:
	if _intro_running:
		return
	if _journal_open:
		_set_journal_open(false)
	Audio.play("open")
	_settings_panel.visible = true


func _hide_settings_panel() -> void:
	if _settings_panel.visible:
		Audio.play("close")
	_settings_panel.visible = false


# --- Journal ---------------------------------------------------------------

func _on_journal_pressed() -> void:
	if _intro_running:
		return
	_set_journal_open(not _journal_open)


func _set_journal_open(open: bool) -> void:
	_journal_open = open
	Audio.play("open" if open else "close")
	if open:
		_hide_settings_panel()
		_journal_panel.refresh(_stats)
	_journal_panel.visible = open
	_journal_icon.texture_normal = HOME_ICON if open else JOURNAL_ICON


func _refresh_stats_bar() -> void:
	var today: Dictionary = _stats.today()
	var sessions := int(today.get("sessions", 0))
	_stats_today_value.text = "%d %s" % [sessions, "session" if sessions == 1 else "sessions"]
	_stats_week_value.text = "%d-day trail" % _stats.current_trail()
	_stats_total_header.text = _format_focus_total(_stats.total_focus())


func _format_focus_total(seconds: float) -> String:
	var mins := int(round(seconds / 60.0))
	if mins < 60:
		return "%dm" % mins
	return "%dh %dm" % [mins / 60, mins % 60]


# --- Pomodoro flow ---------------------------------------------------------

## The Pomodoro rhythm: focus -> short break, repeated, then a long break after
## a full set of focus rounds. We recommend (and highlight) the natural next step.
func _recommended_next() -> String:
	if _last_completed == "focus":
		return "long" if _cycle_focus_count >= SESSIONS_BEFORE_LONG else "short"
	return "focus"


func _apply_recommendation() -> void:
	var rec := _recommended_next()
	_highlight_choice(rec)
	_status_label.text = _recommendation_text(rec)


func _highlight_choice(rec: String) -> void:
	_short_button.texture_normal = BTN_HILITE if rec == "short" else BTN_NORMAL
	_focus_button.texture_normal = BTN_HILITE if rec == "focus" else BTN_NORMAL
	_long_button.texture_normal = BTN_HILITE if rec == "long" else BTN_NORMAL


func _recommendation_text(rec: String) -> String:
	match rec:
		"short":
			return "Lovely focus! Ready for a %d-minute breather?" % int(_session_minutes["short"])
		"long":
			return "%d rounds done — time for a longer rest." % SESSIONS_BEFORE_LONG
		_:
			if _last_completed == "":
				return "What are you settling into?"
			return "Break's over — ready to focus again?"


func _refresh_session_buttons() -> void:
	_short_choice_label.text = "Short break · %dm" % int(_session_minutes["short"])
	_focus_choice_label.text = "Focus · %dm" % int(_session_minutes["focus"])
	_long_choice_label.text = "Long break · %dm" % int(_session_minutes["long"])


func _refresh_settings_length_labels() -> void:
	_settings_panel.focus_length_label.text = "Focus  %dm" % int(_session_minutes["focus"])
	_settings_panel.short_length_label.text = "Short break  %dm" % int(_session_minutes["short"])
	_settings_panel.long_length_label.text = "Long break  %dm" % int(_session_minutes["long"])


func _on_length_changed(value: float, id: String) -> void:
	if _syncing_ui:
		return
	_session_minutes[id] = roundf(value)
	_refresh_session_buttons()
	_refresh_settings_length_labels()
	Achievements.on_setting_changed()
	_request_save()


# --- Sound + data ----------------------------------------------------------

func _on_mute_toggled(enabled: bool) -> void:
	if _syncing_ui:
		return
	Audio.set_muted(enabled)
	_update_ambient()
	Achievements.on_setting_changed()
	_request_save()


func _on_volume_changed(value: float) -> void:
	if _syncing_ui:
		return
	Audio.set_volume(value)
	if not _syncing_ui:
		Audio.play("click")
	Achievements.on_setting_changed()
	_request_save()


func _on_reset_data_pressed() -> void:
	Audio.play("back")
	_reset_dialog.popup_centered()


func _do_reset_data() -> void:
	# Wipe persisted progress, then reset in-memory state to a clean slate.
	for path in [SETTINGS_PATH, StatsStore.PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_stats = StatsStore.new()
	_cycle_focus_count = 0
	_last_completed = ""
	_current_task = ""
	_task_input.text = ""
	if _den != null:
		_den.reset_layout()
		_den.refresh(0.0, false)
	_on_reset_all_pressed()  # fox cosmetics + session lengths back to defaults (+ saves)
	_refresh_stats_bar()
	if _journal_open:
		_journal_panel.refresh(_stats)
	Audio.play("complete")


# --- Intro animation -------------------------------------------------------

func _play_intro() -> void:
	_intro_running = true
	# Everything except the background and the title hides, then fades in last.
	var fade_targets: Array = []
	for child in _main_menu.get_children():
		if child == _background or child == _title:
			continue
		fade_targets.append(child)
	fade_targets.append(_journal_icon)

	# Remember each node's resting alpha (the preview fox carries its opacity).
	var rest := {}
	for n in fade_targets:
		rest[n] = (n as CanvasItem).modulate.a
		(n as CanvasItem).modulate.a = 0.0

	var title_scale: Vector2 = _title.scale
	_title.modulate.a = 0.0
	_title.scale = title_scale * 0.82

	# Phase 1 — the title gently appears in the middle.
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(_title, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t1.tween_property(_title, "scale", title_scale, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t1.finished
	await get_tree().create_timer(0.35).timeout

	# Phase 2 — the title fades away for good.
	var t2 := create_tween()
	t2.tween_property(_title, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t2.finished
	_title.visible = false

	# Phase 3 — the rest of the menu blooms in (title stays hidden).
	var t3 := create_tween().set_parallel(true)
	for n in fade_targets:
		t3.tween_property(n, "modulate:a", rest[n], 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t3.finished

	_intro_running = false


func _on_scale_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_scale = maxf(1.0, roundf(value))
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_refresh_ui()
	Achievements.on_setting_changed()
	_request_save()


func _on_opacity_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_opacity = value
	_desktop_fox.apply_visual_settings()
	_preview_fox.modulate.a = value
	Achievements.on_setting_changed()
	_request_save()


func _on_liveliness_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.body_speed_multiplier = value
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	Achievements.on_setting_changed()
	_request_save()


func _on_colour_selected(index: int) -> void:
	if _syncing_ui or index < 0 or index >= COLOUR_OPTIONS.size():
		return
	_desktop_fox.fox_palette = COLOUR_OPTIONS[index]["key"]
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	Achievements.on_colour_changed(COLOUR_OPTIONS[index]["key"])
	_request_save()


func _on_sit_height_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.sit_height = value
	_refresh_ui()
	_desktop_fox.reset_fox_position()
	Achievements.on_setting_changed()
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
	for id in _session_minutes:
		_session_minutes[id] = float(DEFAULT_MINUTES[id])
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_preview_fox.modulate.a = _desktop_fox.fox_opacity
	_refresh_ui()
	_refresh_session_buttons()
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
	_settings_panel.sit_height_slider.value = _desktop_fox.sit_height
	_settings_panel.focus_length_slider.value = _session_minutes["focus"]
	_settings_panel.short_length_slider.value = _session_minutes["short"]
	_settings_panel.long_length_slider.value = _session_minutes["long"]
	_settings_panel.mute_toggle.button_pressed = Audio.muted
	_settings_panel.volume_slider.value = Audio.volume
	_refresh_settings_length_labels()
	var palette_index := 0
	for i in COLOUR_OPTIONS.size():
		if COLOUR_OPTIONS[i]["key"] == _desktop_fox.fox_palette:
			palette_index = i
	_settings_panel.colour_option.selected = palette_index
	_syncing_ui = false
