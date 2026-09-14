extends Node2D

@export_group("Launcher")
## The design space, 1:1 with the art. Everything in world.tscn and in the panels
## built in code is laid out in these coordinates, unresampled; the window is a
## whole multiple of it and the engine's canvas_items stretch does the scaling.
## Keep in sync with display/window/size/viewport_* in project.godot.
const DESIGN_SIZE := Vector2i(960, 540)
## Screen pixels per design pixel.
##
## 2, not 1, because the launcher renders in physical pixels (allow_hidpi is on) —
## so on a desktop scaled past 100% a 1x launcher comes out smaller than every
## other window on screen rather than merely small. Trimmed at runtime on a screen
## that can't fit it; see _launcher_size_for_screen().
@export_range(1, 4) var launcher_scale := 2
@export var minimize_delay_after_start := 1.5

## HOME / CHOOSE / RUNNING are the session flow. DEN is a side room off it: the menu
## chrome clears out and what's left is the fox's room and the drawer of things to put
## in it. You come back to whichever of the other three you left.
enum Mode { HOME, CHOOSE, RUNNING, DEN }

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

## --- Which fox the room shows ------------------------------------------------
##
## Nothing special: the room's fox is the same scene as the desktop pet, and planetoid.gd
## draws it in whichever art style the player picked ("New fox art" on the settings Fox
## page). The dial fox is separate and still runs the older sitting-transition set.
@onready var _menu_layer: CanvasLayer = $MenuLayer
@onready var _desktop_fox: DesktopFox = $DesktopFox
@onready var _preview_fox: RigidBody2D = $MenuLayer/MainMenu/Room/PreviewFox

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
## A sibling of MainMenu rather than a child of it, so the scrim can be slipped
## between the two — see _setup_settings_scrim().
@onready var _settings_panel: FoxSettingsPanel = $MenuLayer/SettingsPanel

@onready var _main_menu: Node2D = $MenuLayer/MainMenu
## Everything that *is* the room, in one node so den mode can slide it sideways while
## the stats panel and the button row stay pinned where they were composed.
@onready var _room: Node2D = $MenuLayer/MainMenu/Room
@onready var _background: Sprite2D = $MenuLayer/MainMenu/Room/Background
@onready var _title: Sprite2D = $MenuLayer/MainMenu/Title
@onready var _stats_today_value: Label = $MenuLayer/MainMenu/MainmenuStatsPanel/TodayValue
@onready var _stats_week_value: Label = $MenuLayer/MainMenu/MainmenuStatsPanel/WeekValue
@onready var _stats_total_header: Label = $MenuLayer/MainMenu/MainmenuStatsPanel/TotalHeader
@onready var _journal_icon: TextureButton = $MenuLayer/JournalIcon
## The menu's authored desk plant. Not a find — it was always in the room — but it's
## furniture, so it dims with the rest of the furniture rather than staying vivid
## beside a faded lamp.
@onready var _desk_plant: Node2D = $MenuLayer/MainMenu/Room/Planet
@onready var _stats_panel: Sprite2D = $MenuLayer/MainMenu/MainmenuStatsPanel
@onready var _version_labels: Array[Label] = [
	$MenuLayer/MainMenu/VersionLabel, $MenuLayer/MainMenu/VersionLabel2,
]
@onready var _journal_panel: JournalBook = $MenuLayer/JournalBook
@onready var _clock_dial: Sprite2D = $MenuLayer/ClockDial
## Slides in over the button row, so it and the buttons are mutually exclusive.
@onready var _den_inventory: DenInventory = $MenuLayer/DenInventory

const SCRIM_SHADER := preload("res://src/world/settings_scrim.gdshader")
## Above everything else in MenuLayer (the journal icon is the highest at 100) and
## below the settings panel, which is lifted to 120 in world.tscn to make room.
const SCRIM_Z := 110
const SCRIM_FADE := 0.16

const JOURNAL_ICON := preload("res://assets/main_menu/icons/journal-icon.png")
const HOME_ICON := preload("res://assets/main_menu/icons/home-icon.png")
## What the den fades to when the launcher has something else to say. The room is the
## backdrop to the whole menu rather than a screen of its own, so it stays on show —
## but a lamp at full strength competes with the status line and the task field.
const DEN_DIM := 0.6
const DEN_DIM_FADE := 0.22

## How far one notch of the wheel walks the room.
const ROOM_WHEEL_STEP := 120.0
## The band at each edge of the window that pulls the room along while a find is being
## carried. Without it there is no way to take something from one screenful to the next.
const ROOM_EDGE_ZONE := 90.0
const ROOM_EDGE_SPEED := 620.0
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
## The mode den mode was entered from, restored on the way out — so ducking into the
## den mid-session gives you your timer back rather than dumping you at the main menu.
var _mode_before_den := Mode.HOME
var _den_dim_tween: Tween
var _intro_running := false
var _settings_scrim: ColorRect          # blurs + darkens the menu behind the settings panel
var _scrim_tween: Tween
var _launcher_parked := false           # tucked off-screen into the tray
var _launcher_home := Vector2i.ZERO     # on-screen position to restore it to
var _session_started_at := 0
var _session_minutes := {"focus": 25.0, "short": 5.0, "long": 15.0}
var _cycle_focus_count := 0  # completed focus sessions in the current Pomodoro set
var _last_completed := ""     # "focus" / "short" / "long" / "" — drives the next-move hint
var _current_task := ""
var _clock_dial_base_scale := Vector2.ONE
var _clock_dial_intro_tween: Tween
var _clock_fox: AnimatedSprite2D
## True while the sit is running in reverse, so animation_finished can tell the two
## ends apart — it fires at both when a playback is reversed.
var _clock_fox_reversing := false
## The launch curtain: opaque from the first frame, and the only thing that animates
## across a handoff. See the boot splash notes above.
var _curtain: ColorRect
var _curtain_tween: Tween
var _boot_splash_active := false
var _boot_skip := false
## The review fox is off by default now that the room's own fox can be drawn in either
## style from settings — F9 still swaps it in to flick through the clips the game
## never plays (sit, stalk) and to check one against the other.
var _room_pan := 0.0
var _room_dragging := false
var _room_drag_from := 0.0
var _room_drag_pan := 0.0


## --- The revamped fox, previewed inside the session dial ---------------------
##
## The dial art is an ornate window with a ledge and a crescent moon, and its base
## texture is named Clock_No Fox_Empty.png — the hole in it was always meant to hold a
## fox. This is a look at the new art in that hole while it's being drawn.
##
## Deliberately only that. The desktop fox still runs off the old 14x7 sprite sheet in
## planetoid.gd and nothing here touches it.
const CLOCK_FOX_DIR := "res://assets/fox/animations/sitting-transition/"
const CLOCK_FOX_PREFIX := "Fox Sitting"
const CLOCK_FOX_FRAMES := 27
const CLOCK_FOX_FPS := 14.0
## Half scale, which costs nothing: the launcher renders the design space at 2x, so a
## 0.5 sprite puts one source texel on one physical pixel. The frames are drawn at twice
## design size for exactly that reason, and at 1:1 the fox would overflow the window.
const CLOCK_FOX_SCALE := 0.5
## Where the fox goes, in the dial texture's own pixels: the interior's centre line and
## the top of the painted ledge, both measured off Clock_No Fox_Empty.png.
const CLOCK_FOX_WINDOW_X := 477.5
const CLOCK_FOX_LEDGE_Y := 293.0
## The drawn fox within its 390x195 frame, taken as the union across all 27 frames so
## the anchor can't jitter as the tail swings: the centre of the content, and its footing.
const CLOCK_FOX_CONTENT_CENTRE_X := 220.0
const CLOCK_FOX_CONTENT_BOTTOM_Y := 187.0


## --- Boot splash --------------------------------------------------------------
##
## Borrowed wholesale from 100-million-zombies: there is one full-screen curtain, and
## **only the curtain ever animates**. Every handoff — engine splash to scene, splash to
## room — happens while the curtain is fully opaque, so there is no frame in which
## something can be seen changing. Nothing pops because nothing visible moves.
##
## The engine's own boot splash (project.godot) is deliberately set to draw the flat
## background colour and *not* the image. It cannot animate — it is painted before any
## scene exists — so leaving the logo in it gave a static plate for a beat and then a
## jump as the scene took over at a different size and opacity. Now the engine paints
## the same brown the curtain starts on, which makes that handoff invisible, and the
## logo is only ever seen moving.
const BOOT_SPLASH_TEXTURE := "res://assets/static/boot_splash.png"
## Curtain timings: reveal the splash, hold it, cover it again, then reveal the room.
const BOOT_SPLASH_REVEAL := 0.55
const BOOT_SPLASH_HOLD := 1.0
const BOOT_SPLASH_COVER := 0.55
const BOOT_ROOM_REVEAL := 0.45
## How fast the curtain closes when the splash is skipped rather than run out.
const BOOT_SPLASH_SKIP_COVER := 0.18
## The gentle push in. It starts at 1.0 — exactly filling the window, matching what the
## engine painted — and only ever grows, so no edge can uncover.
const BOOT_SPLASH_GROW_FROM := 1.0
const BOOT_SPLASH_GROW_TO := 1.06
## The splash art's own edge colour, sampled from its corners. The curtain, the splash's
## backing and the engine's bg_color are all this, which is what lets the handoffs hide.
const BOOT_SPLASH_BACKING := Color(0.125, 0.106, 0.11, 1.0)


const SETTINGS_PATH := "user://focus_fox.cfg"


func _ready() -> void:
	randomize()
	# Before anything else: the screen starts covered, so frame one is never the raw room.
	_setup_curtain()
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
	_setup_settings_scrim()
	_setup_menu_nodes()
	_configure_desktop_fox()
	_load_settings()
	_desktop_fox.initialize()
	_apply_cosmetics_to_previews()
	_clock_dial_base_scale = _clock_dial.scale
	_setup_clock_fox()
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


## Escape leaves the den. The journal runs its own Escape handler and is deeper in the
## tree, so it gets first refusal — but it only acts while it's visible, and the two
## are mutually exclusive, so they can't both answer.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Any key cuts the launch splash short (a click does the same, via the splash's own
	# blocker). Two seconds of logo gets old fast when you're relaunching all day.
	if _boot_splash_active:
		_boot_skip = true
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and _mode == Mode.DEN:
		_den_inventory.set_open(false)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_room_pan_input(event):
		get_viewport().set_input_as_handled()
		return
	if _mode != Mode.HOME or not is_instance_valid(_preview_fox) or not _room_fox_present():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# get_fox_radius() accounts for both the body scale cosmetics apply and the fact
		# that the two art styles are different sizes.
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


func _setup_settings_scrim() -> void:
	# Sits in MenuLayer rather than inside MainMenu so it can cover the nodes that
	# live outside the menu too — the clock dial and the journal icon.
	_settings_scrim = ColorRect.new()
	_settings_scrim.name = "SettingsScrim"
	var mat := ShaderMaterial.new()
	mat.shader = SCRIM_SHADER
	_settings_scrim.material = mat
	_settings_scrim.z_index = SCRIM_Z
	_settings_scrim.visible = false
	_settings_scrim.modulate.a = 0.0
	# Swallows clicks, so the menu behind can't be poked at while settings are open.
	_settings_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_layer.add_child(_settings_scrim)
	_settings_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Input picking walks the tree back-to-front and ignores z_index entirely, so a
	# full-screen blocker eats the clicks of anything that isn't after it. The panel
	# has to be the last child of MenuLayer for its own controls to stay usable.
	_menu_layer.move_child(_settings_panel, -1)


func _set_scrim_visible(shown: bool) -> void:
	if _scrim_tween != null and _scrim_tween.is_valid():
		_scrim_tween.kill()
	if shown:
		_settings_scrim.visible = true
	_scrim_tween = create_tween()
	_scrim_tween.tween_property(_settings_scrim, "modulate:a", 1.0 if shown else 0.0, SCRIM_FADE)
	if not shown:
		# Keep it out of the way of input once it's faded out.
		_scrim_tween.tween_callback(func() -> void: _settings_scrim.visible = false)


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
	var size := _launcher_size_for_screen()
	window.size = size

	var usable_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	window.position = usable_rect.position + (usable_rect.size - size) / 2

	# Use the fox headshot as the window (title bar + taskbar) icon too.
	if DisplayServer.get_name() != "headless":
		var icon_image := SystemTray.ICON.get_image()
		if icon_image != null:
			DisplayServer.set_icon(icon_image)


## The largest whole multiple of the design size that still fits the screen, capped
## at launcher_scale. Whole multiples only: this is pixel art drawn 1:1 with the
## design space, so a fractional scale resamples every sprite and the crisp edges go
## soft. Falling back rather than clipping matters on a 1366x768 laptop or a 1080p
## monitor with a taskbar, where a 2x launcher does not fit.
##
## Only the window size is set here. The render scale follows from it on its own —
## project.godot puts the root window in canvas_items stretch with integer scaling,
## so the engine divides window size by design size and lands on the same multiple.
func _launcher_size_for_screen() -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var fits := mini(usable.x / DESIGN_SIZE.x, usable.y / DESIGN_SIZE.y)
	return DESIGN_SIZE * clampi(fits, 1, launcher_scale)


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
	_den_inventory.opened_changed.connect(_on_drawer_opened_changed)
	_journal_panel.close_requested.connect(_set_journal_open.bind(false))
	_settings_panel.scale_slider.value_changed.connect(_on_scale_changed)
	_settings_panel.opacity_slider.value_changed.connect(_on_opacity_changed)
	_settings_panel.liveliness_slider.value_changed.connect(_on_liveliness_changed)
	_settings_panel.sit_height_slider.value_changed.connect(_on_sit_height_changed)
	_settings_panel.focus_length_slider.value_changed.connect(_on_length_changed.bind("focus"))
	_settings_panel.short_length_slider.value_changed.connect(_on_length_changed.bind("short"))
	_settings_panel.long_length_slider.value_changed.connect(_on_length_changed.bind("long"))
	_settings_panel.mute_toggle.toggled.connect(_on_mute_toggled)
	_settings_panel.volume_slider.value_changed.connect(_on_volume_changed)
	_settings_panel.ambience_slider.value_changed.connect(_on_ambience_changed)
	_settings_panel.reset_data_button.pressed.connect(_on_reset_data_pressed)
	for option in COLOUR_OPTIONS:
		_settings_panel.colour_option.add_item(option["label"])
	_settings_panel.colour_option.item_selected.connect(_on_colour_selected)
	_settings_panel.fox_style_toggle.toggled.connect(_on_fox_style_toggled)
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
	_room.add_child(_den)
	# The drawer is where finds come from and where they go back to, so the two
	# only ever talk through these three wires.
	_den.room_width = _room_width()
	# The desk plant is a ThrowableProp as well, and it worked out its bounds from the
	# viewport back in its own _ready — which stopped describing the room the moment the
	# room grew wider than the window.
	var plant := _desk_plant.get_node_or_null("Plant") as ThrowableProp
	if plant != null:
		plant.set_bounds(Den.FLOOR_MARGIN_LEFT, _room_width() - Den.ROOM_MARGIN_RIGHT)
	_den.store_zone = _den_inventory.contains_point
	_den.placement_changed.connect(_on_den_placement_changed)
	_den_inventory.place_requested.connect(_on_den_place_requested)
	_den.refresh(_stats.total_focus(), false)


## Both readers of what's out in the room: the drawer's dimmed icons, and the journal's
## Den page, which can be the very thing that changed it (its Tidy Up button) and would
## otherwise sit there describing the room as it was.
func _on_den_placement_changed() -> void:
	_refresh_den_inventory()
	if _journal_open:
		_journal_panel.refresh(_stats, _den)


func _refresh_den_inventory() -> void:
	_den_inventory.refresh(_den.unlocked_entries())


## The drawer is screen furniture, so it reports where you let go in canvas space. The
## den lives inside the room, which may be panned, so the point has to be carried across
## before it means anything.
func _on_den_place_requested(id: String, at: Vector2) -> void:
	_den.place(id, _den.to_local(at))


func _configure_desktop_fox() -> void:
	_desktop_fox.fox_scale = 1.0
	_desktop_fox.fox_opacity = 1.0
	_desktop_fox.click_through_enabled = false
	_desktop_fox.hover_fade_enabled = false
	_desktop_fox.sit_height = 48.0  # feet rest above the screen bottom; clears a taskbar
	_desktop_fox.body_speed_multiplier = 1.0
	_desktop_fox.fox_palette = "default"
	_desktop_fox.fox_style = "classic"


# --- The revamped fox in the room -------------------------------------------

## Whether the room should be showing a fox at all — true in the modes that draw the
## room, and false while the fox is out on the desktop.
func _room_fox_present() -> bool:
	return (_mode == Mode.HOME or _mode == Mode.DEN) and not _desktop_fox.is_spawned()


func _set_mode(mode: Mode) -> void:
	var entering_running := mode == Mode.RUNNING and _mode != Mode.RUNNING
	_mode = mode
	var home := mode == Mode.HOME
	var choose := mode == Mode.CHOOSE
	var running := mode == Mode.RUNNING
	var den := mode == Mode.DEN

	# The room keeps its resident: a fox that's out on the desktop isn't home to be
	# seen, but otherwise it sits in the den you're arranging around it.
	_preview_fox.visible = _room_fox_present()
	_start_button.visible = home
	_quit_button.visible = home

	# Everything that isn't the room itself gets out of the way.
	_stats_panel.visible = not den
	_settings_icon_button.visible = not den
	for label in _version_labels:
		label.visible = not den
	_apply_den_dim(home or den)

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
	if den:
		# The drawer is where finds come from, so arriving with it shut would mean
		# every visit starts with the same click.
		_den_inventory.set_open(true)
	_update_tray()
	_update_fox_activity()
	_update_ambient()


## Full strength when the room is the thing you're looking at, faded back when the
## launcher has a session to talk about. Null-guarded because _set_mode runs once in
## _ready before the den is built.
func _apply_den_dim(full: bool) -> void:
	if _den == null:
		return
	var target := 1.0 if full else DEN_DIM
	if is_equal_approx(_den.modulate.a, target):
		return
	if _den_dim_tween != null and _den_dim_tween.is_valid():
		_den_dim_tween.kill()
	_den_dim_tween = create_tween().set_parallel(true)
	for furniture: CanvasItem in [_den, _desk_plant]:
		_den_dim_tween.tween_property(furniture, "modulate:a", target, DEN_DIM_FADE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# --- Panning the room ------------------------------------------------------
#
# The room is wider than the window, so you walk across it: wheel or drag anywhere on the
# room, in any mode. It used to pan in den mode only, on the theory that arranging the den
# was the one reason to look past the first screenful — but the room is the backdrop the
# whole app sits on, so being unable to look around it unless the drawer was out made the
# rest of the room feel like it belonged to the drawer. Wherever you leave the view is
# where the room stays: in every mode, and across launches.
#
# It used to glide back to the first screenful on the way out, on the theory that the
# menu was composed against that one view. In practice it made everything past x=960
# read as an annexe to the menu rather than as the room the menu opens onto, which is
# the opposite of the point of a wide room.
#
# What that costs: the preview fox is room furniture (world.tscn parents it inside Room
# at x 481), so it pans away with everything else and HOME can open on a stretch of room
# with no fox in it. Deliberate — the fox has a place in its den rather than tracking the
# camera. The pinned chrome (stats panel, buttons, labels) lands where it was drawn
# regardless, so only the backdrop changes.

func _room_width() -> float:
	return _background.texture.get_width() * _background.scale.x


## How far left the room can slide before its right edge reaches the window's.
func _pan_limit() -> float:
	return maxf(0.0, _room_width() - float(DESIGN_SIZE.x))


func _set_room_pan(x: float) -> void:
	var to := clampf(x, -_pan_limit(), 0.0)
	if is_equal_approx(to, _room_pan):
		return
	_room_pan = to
	# Whole pixels only. The room is pixel art at 1:1 with the design space, and a
	# fractional offset resamples every sprite in it into a soft mess.
	_room.position.x = roundf(_room_pan)
	# The view is now part of the save. Debounced, because a drag and an edge-pan both
	# call this every frame — the timer restarts on each one and only writes once the
	# room has come to rest.
	_request_save()


## Wheel, or drag the room itself.
##
## The press is deliberately *not* consumed. Godot queues physics-picking events after
## input propagation and only while the event is still unhandled, so swallowing the
## press here would kill a find's Area2D click before it ever fired — which reads as
## "finds stopped being draggable in den mode". Instead the press only *arms* a room
## drag, and the first motion cancels it if a find or the drawer's ghost has taken the
## cursor in the meantime.
func _handle_room_pan_input(event: InputEvent) -> bool:
	if _pan_limit() <= 0.0:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# A release always counts, wherever it lands, or a drag that ends over the
		# drawer would leave the room stuck to the cursor.
		if mb.pressed and _cursor_over_drawer():
			return false
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				if mb.pressed:
					_set_room_pan(_room_pan - ROOM_WHEEL_STEP)
				return true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				if mb.pressed:
					_set_room_pan(_room_pan + ROOM_WHEEL_STEP)
				return true
			MOUSE_BUTTON_LEFT:
				_room_dragging = mb.pressed
				if mb.pressed:
					_room_drag_from = get_global_mouse_position().x
					_room_drag_pan = _room_pan
				return false
	elif event is InputEventMouseMotion and _room_dragging:
		if _something_is_being_carried():
			_room_dragging = false
			return false
		_set_room_pan(_room_drag_pan + get_global_mouse_position().x - _room_drag_from)
		return true
	return false


func _something_is_being_carried() -> bool:
	return (_den != null and _den.is_dragging()) or _den_inventory.is_dragging()


## The drawer is not part of the room, so the room doesn't move under it: no wheel, no
## drag starting there, and no edge-pan from hovering its pull handle — which sits right
## inside the window's right-hand edge band, where it would otherwise be impossible to
## reach for without the room sliding away.
func _cursor_over_drawer() -> bool:
	return _den_inventory.blocks_pan(get_global_mouse_position())


## Carrying a find to the edge of the window drags the room along with it. Not optional:
## a find picked up on one screenful could otherwise never be put down on another.
##
## Not over the drawer, though — carrying a find down there means putting it away, not
## going somewhere else. The strip above the drawer is still edge-pannable, so the right
## edge stays reachable with a find in hand.
func _update_edge_pan(delta: float) -> void:
	if _pan_limit() <= 0.0 or _room_dragging:
		return
	if not _something_is_being_carried() or _cursor_over_drawer():
		return
	var mouse_x := get_global_mouse_position().x
	var push := 0.0
	if mouse_x < ROOM_EDGE_ZONE:
		push = (mouse_x - ROOM_EDGE_ZONE) / ROOM_EDGE_ZONE          # negative, pans right
	elif mouse_x > float(DESIGN_SIZE.x) - ROOM_EDGE_ZONE:
		push = (mouse_x - (float(DESIGN_SIZE.x) - ROOM_EDGE_ZONE)) / ROOM_EDGE_ZONE
	if is_zero_approx(push):
		return
	_set_room_pan(_room_pan - clampf(push, -1.0, 1.0) * ROOM_EDGE_SPEED * delta)


func _process(delta: float) -> void:
	_update_edge_pan(delta)


# --- Den mode --------------------------------------------------------------

## The drawer's pull tab is the whole way in and out. Pulling the drawer open already
## meant "I want to arrange my den", so a separate button that did the same thing was
## one control too many — and hanging the mode off the tab makes what the tab is for
## obvious instead of something to discover.
##
## The drawer plays its own open/close sound, so there is deliberately none here.
func _on_drawer_opened_changed(open: bool) -> void:
	if open == (_mode == Mode.DEN):
		return
	if open:
		# The den, the journal and the settings panel each want the whole window.
		_hide_settings_panel()
		if _journal_open:
			_set_journal_open(false)
		_mode_before_den = _mode
		_set_mode(Mode.DEN)
	elif _mode == Mode.DEN:
		# The room keeps the view you left it at; only the drag state is dropped, or a
		# press left hanging here would resume against a stale origin the next time the
		# drawer opens and jump the room on the first mouse move.
		_room_dragging = false
		_set_mode(_mode_before_den)


## Anything that decides the mode for itself — a session ending, the fox coming home —
## outranks den mode. Called before those set their own mode, so leaving the den later
## doesn't rewind to a mode that has since moved on.
func _leave_den_for(mode: Mode) -> void:
	_mode_before_den = mode
	if _mode == Mode.DEN:
		_den_inventory.set_open(false)


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
	# Only tuck the launcher away if the session is still the one we queued for. The
	# mode test also covers ducking into the den inside the delay: den mode isn't
	# RUNNING, so the park quietly cancels itself rather than parking the window out
	# from under someone mid-rearrange.
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


func _setup_clock_fox() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("sit")
	# Not looping: animation_finished is what turns the playback around, and a looping
	# animation never emits it.
	frames.set_animation_loop("sit", false)
	frames.set_animation_speed("sit", CLOCK_FOX_FPS)
	for i in range(1, CLOCK_FOX_FRAMES + 1):
		var path := "%s%s%d.png" % [CLOCK_FOX_DIR, CLOCK_FOX_PREFIX, i]
		if not ResourceLoader.exists(path):
			push_warning("Clock fox frame missing: %s" % path)
			continue
		frames.add_frame("sit", load(path))
	if frames.has_animation("default"):
		frames.remove_animation("default")

	_clock_fox = AnimatedSprite2D.new()
	_clock_fox.name = "ClockFox"
	_clock_fox.sprite_frames = frames
	_clock_fox.centered = false
	_clock_fox.scale = Vector2.ONE * CLOCK_FOX_SCALE
	# Parented to the dial rather than sat beside it, which hands us three things for
	# free: it inherits the dial's visibility, so it comes and goes with the session
	# without being wired to the mode; it rides the dial's pop-in tween; and its z_index
	# is relative, so 5 puts it over the dial's 20 and under the labels' 30.
	_clock_fox.z_index = 5
	_clock_fox.position = _clock_fox_offset()
	_clock_fox.animation_finished.connect(_on_clock_fox_finished)
	_clock_dial.add_child(_clock_fox)


## Where to hang the fox inside the dial. The dial sprite is centred, so its children
## measure from the middle of the texture — hence subtracting the texture centre — and
## the fox is anchored by its own footing rather than by its frame's corner.
func _clock_fox_offset() -> Vector2:
	var texture_centre := _clock_dial.texture.get_size() * 0.5
	var spot := Vector2(CLOCK_FOX_WINDOW_X, CLOCK_FOX_LEDGE_Y) - texture_centre
	var footing := Vector2(CLOCK_FOX_CONTENT_CENTRE_X, CLOCK_FOX_CONTENT_BOTTOM_Y) * CLOCK_FOX_SCALE
	return (spot - footing).round()


## Sits down, gets back up, and keeps at it for as long as the session runs. Reversing
## reads as standing up rather than as a rewind because the animation is a real one-way
## transition — its first and last frames are different poses.
func _on_clock_fox_finished() -> void:
	if _clock_fox_reversing:
		_clock_fox_reversing = false
		_clock_fox.play("sit")
	else:
		_clock_fox_reversing = true
		_clock_fox.play_backwards("sit")


func _start_clock_fox() -> void:
	if _clock_fox == null:
		return
	_clock_fox_reversing = false
	_clock_fox.frame = 0
	_clock_fox.play("sit")


func _stop_clock_fox() -> void:
	if _clock_fox != null:
		_clock_fox.stop()


func _play_clock_dial_intro() -> void:
	_reset_clock_dial_intro()
	_clock_dial.scale = _clock_dial_base_scale * CLOCK_DIAL_INTRO_START_SCALE
	_clock_dial.modulate.a = 0.0
	_clock_dial_intro_tween = create_tween().set_parallel(true)
	_clock_dial_intro_tween.tween_property(_clock_dial, "scale", _clock_dial_base_scale, CLOCK_DIAL_INTRO_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_clock_dial_intro_tween.tween_property(_clock_dial, "modulate:a", 1.0, CLOCK_DIAL_INTRO_SECONDS * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_start_clock_fox()


func _reset_clock_dial_intro() -> void:
	if _clock_dial_intro_tween != null and _clock_dial_intro_tween.is_valid():
		_clock_dial_intro_tween.kill()
	_clock_dial_intro_tween = null
	_clock_dial.scale = _clock_dial_base_scale
	_clock_dial.modulate.a = 1.0
	_stop_clock_fox()


func _on_clock_finished() -> void:
	# Only completed sessions count towards the journal + the Pomodoro cycle.
	var id := _clock.session_id
	var encouragement := ""
	if _is_break(id):
		_stats.record_break(_clock.total_seconds, _session_started_at, id)
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
		_journal_panel.refresh(_stats, _den)
	if _den != null:
		_den.refresh(_stats.total_focus(), true)
	_minimize_token += 1
	_show_launcher()
	if _desktop_fox.is_spawned():
		_desktop_fox.celebrate()
	# _set_mode(CHOOSE) applies the next-move recommendation + status text,
	# then we overwrite it with a warm encouragement for this completion moment.
	# A finished session outranks decorating, so this pulls out of the den too.
	_leave_den_for(Mode.CHOOSE)
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
	cfg.set_value("fox", "style", _desktop_fox.fox_style)
	cfg.set_value("behaviour", "sit_height", _desktop_fox.sit_height)
	cfg.set_value("pomodoro", "focus", _session_minutes["focus"])
	cfg.set_value("pomodoro", "short", _session_minutes["short"])
	cfg.set_value("pomodoro", "long", _session_minutes["long"])
	cfg.set_value("audio", "muted", Audio.muted)
	cfg.set_value("audio", "volume", Audio.volume)
	cfg.set_value("audio", "ambience", Audio.ambience_volume)
	cfg.set_value("den", "room_pan", _room_pan)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_desktop_fox.fox_scale = float(cfg.get_value("fox", "scale", _desktop_fox.fox_scale))
	_desktop_fox.fox_opacity = float(cfg.get_value("fox", "opacity", _desktop_fox.fox_opacity))
	_desktop_fox.body_speed_multiplier = float(cfg.get_value("fox", "liveliness", _desktop_fox.body_speed_multiplier))
	_desktop_fox.fox_palette = str(cfg.get_value("fox", "palette", _desktop_fox.fox_palette))
	_desktop_fox.fox_style = str(cfg.get_value("fox", "style", _desktop_fox.fox_style))
	_desktop_fox.sit_height = float(cfg.get_value("behaviour", "sit_height", _desktop_fox.sit_height))
	for id in _session_minutes:
		_session_minutes[id] = float(cfg.get_value("pomodoro", id, _session_minutes[id]))
	Audio.set_muted(bool(cfg.get_value("audio", "muted", Audio.muted)))
	Audio.set_volume(float(cfg.get_value("audio", "volume", Audio.volume)))
	Audio.set_ambience_volume(float(cfg.get_value("audio", "ambience", Audio.ambience_volume)))
	# Restores the view, not just the room's contents. _set_room_pan clamps, so a pan
	# saved against wider room art survives that art getting narrower instead of parking
	# the room past its own edge.
	_set_room_pan(float(cfg.get_value("den", "room_pan", _room_pan)))


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
	_den_inventory.set_open(false)
	Audio.play("open")
	_settings_panel.reset_to_first_tab()
	_settings_panel.visible = true
	_set_scrim_visible(true)


func _hide_settings_panel() -> void:
	if _settings_panel.visible:
		Audio.play("close")
	_settings_panel.visible = false
	_set_scrim_visible(false)


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
		# Closing the drawer is what drops out of den mode, if we were in it.
		_den_inventory.set_open(false)
		_journal_panel.refresh(_stats, _den)
	# The journal covers the whole window and sits above the drawer, so the drawer
	# has to go away entirely — left visible its pull tab would still take clicks
	# from behind the journal.
	_den_inventory.visible = not open
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


func _on_length_changed(value: float, id: String) -> void:
	if _syncing_ui:
		return
	_session_minutes[id] = roundf(value)
	_refresh_session_buttons()
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


func _on_ambience_changed(value: float) -> void:
	if _syncing_ui:
		return
	Audio.set_ambience_volume(value)
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
	_den_inventory.set_open(false)
	if _den != null:
		_den.reset_layout()
		_den.refresh(0.0, false)
	_on_reset_all_pressed()  # fox cosmetics + session lengths back to defaults (+ saves)
	_refresh_stats_bar()
	if _journal_open:
		_journal_panel.refresh(_stats, _den)
	Audio.play("complete")


# --- Intro animation -------------------------------------------------------

func _play_intro() -> void:
	_intro_running = true
	# Everything except the background and the title hides, then fades in last.
	var fade_targets: Array = []
	for child in _main_menu.get_children():
		if child == _title or child == _room:
			continue
		fade_targets.append(child)
	# The room is skipped as a whole and unpacked instead, because the background is
	# inside it now and is the one thing that must not fade — fading the room would take
	# the backdrop with it and the intro would open on nothing.
	for child in _room.get_children():
		if child != _background:
			fade_targets.append(child)
	fade_targets.append(_journal_icon)
	fade_targets.append(_den_inventory)

	# Remember each node's resting alpha (the preview fox carries its opacity).
	var rest := {}
	for n in fade_targets:
		rest[n] = (n as CanvasItem).modulate.a
		(n as CanvasItem).modulate.a = 0.0
	# A transparent Control still answers the mouse, so the drawer's pull tab has
	# to be gone rather than merely invisible until the menu has arrived.
	_den_inventory.visible = false

	var title_scale: Vector2 = _title.scale
	_title.modulate.a = 0.0
	_title.scale = title_scale * 0.82

	# The splash plays behind the curtain and leaves it opaque; lifting the curtain is what
	# reveals the bare room, and the title bloom below carries on from there.
	await _play_boot_splash()
	await _curtain_fade(0.0, BOOT_ROOM_REVEAL)

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
	_den_inventory.visible = true
	var t3 := create_tween().set_parallel(true)
	for n in fade_targets:
		t3.tween_property(n, "modulate:a", rest[n], 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t3.finished

	_intro_running = false


## The curtain, on its own layer above everything including the splash. Opaque to begin
## with; every reveal in the launch sequence is this fading away.
func _setup_curtain() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Curtain"
	layer.layer = 210
	add_child(layer)
	_curtain = ColorRect.new()
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.color = BOOT_SPLASH_BACKING
	# It sits over the whole app for the life of the process, so it must never be the
	# thing that eats a click. The splash puts up its own blocker while it needs one.
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_curtain)


## Fade the curtain to `target` and return when it's there. Kills any fade already
## running, so a skip mid-reveal turns around cleanly instead of fighting it.
func _curtain_fade(target: float, seconds: float) -> void:
	if _curtain == null:
		return
	if _curtain_tween != null and _curtain_tween.is_valid():
		_curtain_tween.kill()
	_curtain_tween = create_tween()
	_curtain_tween.tween_property(_curtain, "color:a", target, seconds) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _curtain_tween.finished


## Hold, but give up the moment the splash is skipped.
func _boot_hold(seconds: float) -> void:
	var timer := get_tree().create_timer(seconds)
	while timer.time_left > 0.0 and not _boot_skip:
		await get_tree().process_frame


## Reveals the splash from behind the curtain, swells it gently, then covers it again and
## takes it away — leaving the curtain opaque for the caller to lift onto the room.
## Returns when the splash is gone. A click or any key cuts it short.
func _play_boot_splash() -> void:
	var texture: Texture2D = load(BOOT_SPLASH_TEXTURE)
	if texture == null:
		push_warning("Boot splash texture missing: %s" % BOOT_SPLASH_TEXTURE)
		return

	var layer := CanvasLayer.new()
	layer.name = "BootSplash"
	# Under the curtain (210), over the menu.
	layer.layer = 200
	add_child(layer)

	# Backs the art so the swell can never uncover an edge, and stops clicks reaching the
	# menu's live buttons underneath. Its gui_input is also how a click skips.
	var blocker := ColorRect.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.color = BOOT_SPLASH_BACKING
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(_on_boot_splash_gui_input)
	layer.add_child(blocker)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = Vector2(DESIGN_SIZE) * 0.5
	# The art is 1920x1080 — the design space at the launcher's 2x — so half scale puts one
	# source texel on one physical pixel and the splash exactly fills the window.
	var base := Vector2.ONE * 0.5
	sprite.scale = base * BOOT_SPLASH_GROW_FROM
	# The project filters globally with nearest, which is right for the pixel art and wrong
	# for this: the splash is smooth vector-style artwork and it is scaled every frame it
	# is on screen, so it filters linearly like the badge art does.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.add_child(sprite)

	# The art is up and opaque from the first frame — it is simply hidden by the curtain.
	# That is the whole trick: it never fades its own alpha, so it cannot mismatch what
	# the engine painted a moment earlier.
	_boot_splash_active = true
	_boot_skip = false

	# One continuous swell across the entire splash, fades included, so it reads as a
	# slow breath rather than stalling while the curtain moves.
	var total := BOOT_SPLASH_REVEAL + BOOT_SPLASH_HOLD + BOOT_SPLASH_COVER
	var swell := create_tween()
	swell.tween_property(sprite, "scale", base * BOOT_SPLASH_GROW_TO, total) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await _curtain_fade(0.0, BOOT_SPLASH_REVEAL)
	await _boot_hold(BOOT_SPLASH_HOLD)
	await _curtain_fade(1.0, BOOT_SPLASH_SKIP_COVER if _boot_skip else BOOT_SPLASH_COVER)

	_boot_splash_active = false
	if swell.is_valid():
		swell.kill()
	layer.queue_free()


func _on_boot_splash_gui_input(event: InputEvent) -> void:
	if _boot_splash_active and event is InputEventMouseButton and event.pressed:
		_boot_skip = true


## Both preview foxes — the one posing on the menu and the one in the settings panel's
## preview box — wear whatever the desktop fox is wearing.
func _apply_cosmetics_to_previews() -> void:
	for fox in [_preview_fox, _settings_panel.preview_fox]:
		if not is_instance_valid(fox):
			continue
		fox.freeze = true
		fox.call("set_highlight", false, _desktop_fox.hover_modulate)
		# true: both of these are drawn inside the launcher, not in an overlay window.
		_desktop_fox.apply_cosmetics_to(fox, true)
		fox.modulate.a = _desktop_fox.fox_opacity
	# apply_cosmetics_to() changes the body scale, which the preview box divides out.
	_settings_panel.fit_preview()


func _on_scale_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_scale = maxf(1.0, roundf(value))
	_apply_cosmetics_to_previews()
	_desktop_fox.apply_visual_settings()
	_refresh_ui()
	Achievements.on_setting_changed()
	_request_save()


func _on_opacity_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_opacity = value
	_desktop_fox.apply_visual_settings()
	_apply_cosmetics_to_previews()
	Achievements.on_setting_changed()
	_request_save()


func _on_liveliness_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.body_speed_multiplier = value
	_apply_cosmetics_to_previews()
	_desktop_fox.apply_visual_settings()
	Achievements.on_setting_changed()
	_request_save()


## Swaps the art the fox is drawn in. Goes through the same path as the palette, so the
## desktop pet, the menu room fox and the settings preview all change together.
func _on_fox_style_toggled(pressed: bool) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_style = "drawn" if pressed else "classic"
	_apply_cosmetics_to_previews()
	_desktop_fox.apply_visual_settings()
	Achievements.on_setting_changed()
	_request_save()


func _on_colour_selected(index: int) -> void:
	if _syncing_ui or index < 0 or index >= COLOUR_OPTIONS.size():
		return
	_desktop_fox.fox_palette = COLOUR_OPTIONS[index]["key"]
	_apply_cosmetics_to_previews()
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
	_apply_cosmetics_to_previews()
	_desktop_fox.apply_visual_settings()
	_refresh_ui()
	_refresh_session_buttons()
	_request_save()


## The fox coming or going doesn't interrupt decorating — it only changes the mode you
## come back out to. Being thrown out of the den because the fox went home would be a
## strange thing to have happen while you're mid-rearrange.
func _on_fox_spawned_changed(active: bool) -> void:
	if active:
		if _mode == Mode.DEN:
			_mode_before_den = Mode.CHOOSE
		elif _mode == Mode.HOME:
			_set_mode(Mode.CHOOSE)
			_status_label.text = "What are you settling into?"
	else:
		_clock.stop()
		if _mode == Mode.DEN:
			_mode_before_den = Mode.HOME
		else:
			_set_mode(Mode.HOME)
	_refresh_ui()


func _refresh_ui() -> void:
	_syncing_ui = true
	var spawned := _desktop_fox.is_spawned()
	_settings_panel.fox_status_label.text = "Fox: active" if spawned else "Fox: menu preview"
	_settings_panel.scale_slider.value = _desktop_fox.fox_scale
	_settings_panel.opacity_slider.value = _desktop_fox.fox_opacity
	_settings_panel.liveliness_slider.value = _desktop_fox.body_speed_multiplier
	_settings_panel.fox_style_toggle.button_pressed = _desktop_fox.fox_style == "drawn"
	_settings_panel.sit_height_slider.value = _desktop_fox.sit_height
	_settings_panel.focus_length_slider.value = _session_minutes["focus"]
	_settings_panel.short_length_slider.value = _session_minutes["short"]
	_settings_panel.long_length_slider.value = _session_minutes["long"]
	_settings_panel.mute_toggle.button_pressed = Audio.muted
	_settings_panel.volume_slider.value = Audio.volume
	_settings_panel.ambience_slider.value = Audio.ambience_volume
	var palette_index := 0
	for i in COLOUR_OPTIONS.size():
		if COLOUR_OPTIONS[i]["key"] == _desktop_fox.fox_palette:
			palette_index = i
	_settings_panel.colour_option.selected = palette_index
	_syncing_ui = false
