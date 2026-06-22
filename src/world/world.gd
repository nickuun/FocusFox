extends Node2D

@export_group("Launcher")
@export var launcher_window_size := Vector2i(960, 540)
@export var minimize_launcher_after_spawn := true

const START_LABEL := "Start Focus Session"
const RECALL_LABEL := "Bring Fox Home"

@onready var _desktop_fox: DesktopFox = $DesktopFox
@onready var _preview_fox: RigidBody2D = $MenuLayer/MainMenu/PreviewFox
@onready var _start_button: TextureButton = $MenuLayer/MainMenu/Buttons/StartButton
@onready var _start_label: Label = $MenuLayer/MainMenu/Buttons/StartButton/Label
@onready var _quit_button: TextureButton = $MenuLayer/MainMenu/Buttons/QuitButton
@onready var _settings_icon_button: TextureButton = $MenuLayer/MainMenu/SettingsIconButton
@onready var _settings_panel: FoxSettingsPanel = $MenuLayer/MainMenu/SettingsPanel
@onready var _settings_close_button: Button = $MenuLayer/MainMenu/SettingsPanel/CloseButton

var _is_starting := false
var _syncing_ui := false


func _ready() -> void:
	randomize()
	_setup_launcher_window()
	_setup_menu_nodes()
	_configure_desktop_fox()
	_desktop_fox.initialize()
	_preview_fox.freeze = true
	_preview_fox.call("set_highlight", false, _desktop_fox.hover_modulate)
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_refresh_ui()


func _physics_process(delta: float) -> void:
	_desktop_fox.physics_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _is_starting or not is_instance_valid(_preview_fox):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _preview_fox.global_position.distance_to(get_global_mouse_position()) <= _desktop_fox.get_fox_radius(_preview_fox):
			_preview_fox.call("pulse_click")


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


func _setup_menu_nodes() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_settings_icon_button.pressed.connect(_on_settings_pressed)
	_settings_close_button.pressed.connect(_hide_settings_panel)
	_settings_panel.click_through_toggle.toggled.connect(_on_click_through_toggled)
	_settings_panel.hover_fade_toggle.toggled.connect(_on_hover_fade_toggled)
	_settings_panel.taskbar_snap_toggle.toggled.connect(_on_taskbar_snap_toggled)
	_settings_panel.scale_slider.value_changed.connect(_on_scale_changed)
	_settings_panel.opacity_slider.value_changed.connect(_on_opacity_changed)
	_settings_panel.liveliness_slider.value_changed.connect(_on_liveliness_changed)
	_settings_panel.taskbar_height_slider.value_changed.connect(_on_taskbar_height_changed)
	_settings_panel.reset_fox_button.pressed.connect(_on_reset_fox_pressed)
	_settings_panel.spawn_fox_button.pressed.connect(_on_spawn_fox_pressed)
	_settings_panel.hide_fox_button.pressed.connect(_on_hide_fox_pressed)
	_settings_panel.reset_all_button.pressed.connect(_on_reset_all_pressed)
	_desktop_fox.fox_spawned_changed.connect(_on_fox_spawned_changed)


func _configure_desktop_fox() -> void:
	_desktop_fox.fox_scale = 3.0
	_desktop_fox.fox_opacity = 1.0
	_desktop_fox.click_through_enabled = false
	_desktop_fox.hover_fade_enabled = false
	_desktop_fox.taskbar_snap_enabled = true
	_desktop_fox.taskbar_height = 24.0
	_desktop_fox.body_speed_multiplier = 1.0


func _on_start_pressed() -> void:
	if _is_starting:
		return
	# Start doubles as a toggle: once the fox is out on the desktop, the same
	# button calls it back home so the launcher stays a single clear action.
	if _desktop_fox.is_spawned():
		_desktop_fox.despawn_fox()
		return
	_is_starting = true
	_preview_fox.call("pulse_click")
	await get_tree().create_timer(0.14).timeout
	_desktop_fox.spawn_fox(_desktop_fox.get_preview_screen_position(_preview_fox))
	_preview_fox.visible = false
	_is_starting = false
	_refresh_ui()
	if minimize_launcher_after_spawn:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_settings_pressed() -> void:
	_settings_panel.visible = true


func _hide_settings_panel() -> void:
	_settings_panel.visible = false


func _on_click_through_toggled(enabled: bool) -> void:
	_desktop_fox.click_through_enabled = enabled
	_desktop_fox.apply_visual_settings()


func _on_hover_fade_toggled(enabled: bool) -> void:
	_desktop_fox.hover_fade_enabled = enabled
	_desktop_fox.apply_visual_settings()


func _on_taskbar_snap_toggled(enabled: bool) -> void:
	_desktop_fox.taskbar_snap_enabled = enabled
	_refresh_ui()
	_desktop_fox.reset_fox_position()


func _on_scale_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_scale = maxf(1.0, roundf(value))
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_refresh_ui()


func _on_opacity_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.fox_opacity = value
	_desktop_fox.apply_visual_settings()
	_preview_fox.modulate.a = value


func _on_liveliness_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.body_speed_multiplier = value
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()


func _on_taskbar_height_changed(value: float) -> void:
	if _syncing_ui:
		return
	_desktop_fox.taskbar_height = value
	_refresh_ui()
	_desktop_fox.reset_fox_position()


func _on_reset_fox_pressed() -> void:
	_desktop_fox.reset_fox_position()


func _on_spawn_fox_pressed() -> void:
	if _desktop_fox.is_spawned():
		return
	_desktop_fox.spawn_at_screen_center()
	_preview_fox.visible = false
	_refresh_ui()


func _on_hide_fox_pressed() -> void:
	_desktop_fox.despawn_fox()


func _on_reset_all_pressed() -> void:
	_configure_desktop_fox()
	_desktop_fox.apply_cosmetics_to(_preview_fox)
	_desktop_fox.apply_visual_settings()
	_preview_fox.modulate.a = _desktop_fox.fox_opacity
	_refresh_ui()


func _on_fox_spawned_changed(active: bool) -> void:
	_preview_fox.visible = not active
	_refresh_ui()


func _refresh_ui() -> void:
	_syncing_ui = true
	var spawned := _desktop_fox.is_spawned()
	_start_label.text = RECALL_LABEL if spawned else START_LABEL
	_settings_panel.fox_status_label.text = "Fox: active" if spawned else "Fox: menu preview"
	_settings_panel.scale_slider.value = _desktop_fox.fox_scale
	_settings_panel.opacity_slider.value = _desktop_fox.fox_opacity
	_settings_panel.liveliness_slider.value = _desktop_fox.body_speed_multiplier
	_settings_panel.taskbar_height_slider.value = _desktop_fox.taskbar_height
	_settings_panel.taskbar_snap_toggle.button_pressed = _desktop_fox.taskbar_snap_enabled
	_settings_panel.click_through_toggle.button_pressed = _desktop_fox.click_through_enabled
	_settings_panel.hover_fade_toggle.button_pressed = _desktop_fox.hover_fade_enabled
	_syncing_ui = false
