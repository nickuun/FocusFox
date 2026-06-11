extends Node2D

const FOX_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")

@export_group("Launcher")
@export var launcher_window_size := Vector2i(960, 540)
@export var minimize_launcher_after_spawn := true

@export_group("Fox Window")
@export var fox_window_size := Vector2i(240, 240)
@export var use_usable_screen_area := true
@export var fox_edge_padding := 12.0
@export var taskbar_height := 48.0

@export_group("Fox Feel")
@export var fox_gravity := 2450.0
@export var fox_bounce := 0.18
@export var throw_boost := 0.72
@export var max_throw_speed := 1850.0
@export var floor_friction := 6.5
@export var hover_modulate := Color(1.12, 1.08, 1.16, 1.0)

@onready var _preview_fox: RigidBody2D = $MenuLayer/MainMenu/PreviewFox
@onready var _start_button: TextureButton = $MenuLayer/MainMenu/Buttons/StartButton
@onready var _customize_button: TextureButton = $MenuLayer/MainMenu/Buttons/CustomizeButton
@onready var _settings_button: TextureButton = $MenuLayer/MainMenu/Buttons/SettingsButton
@onready var _about_button: TextureButton = $MenuLayer/MainMenu/Buttons/AboutButton
@onready var _quit_button: TextureButton = $MenuLayer/MainMenu/Buttons/QuitButton
@onready var _status_label: Label = $MenuLayer/MainMenu/StatusLabel
@onready var _settings_panel: Panel = $MenuLayer/MainMenu/SettingsPanel
@onready var _settings_close_button: Button = $MenuLayer/MainMenu/SettingsPanel/CloseButton
@onready var _click_through_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/ClickThroughToggle
@onready var _hover_fade_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/HoverFadeToggle
@onready var _taskbar_snap_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/TaskbarSnapToggle
@onready var _scale_slider: HSlider = $MenuLayer/MainMenu/SettingsPanel/ScaleSlider
@onready var _opacity_slider: HSlider = $MenuLayer/MainMenu/SettingsPanel/OpacitySlider
@onready var _taskbar_height_slider: HSlider = $MenuLayer/MainMenu/SettingsPanel/TaskbarHeightSlider
@onready var _reset_fox_button: Button = $MenuLayer/MainMenu/SettingsPanel/ResetFoxButton
@onready var _spawn_fox_button: Button = $MenuLayer/MainMenu/SettingsPanel/SpawnFoxButton
@onready var _hide_fox_button: Button = $MenuLayer/MainMenu/SettingsPanel/HideFoxButton
@onready var _reset_all_button: Button = $MenuLayer/MainMenu/SettingsPanel/ResetAllButton
@onready var _fox_status_label: Label = $MenuLayer/MainMenu/SettingsPanel/FoxStatusLabel
@onready var _settings_hint_label: Label = $MenuLayer/MainMenu/SettingsPanel/HintLabel
@onready var _customize_panel: Panel = $MenuLayer/MainMenu/CustomizePanel
@onready var _customize_close_button: Button = $MenuLayer/MainMenu/CustomizePanel/CloseButton
@onready var _body_speed_slider: HSlider = $MenuLayer/MainMenu/CustomizePanel/BodySpeedSlider

var _overlay_window: Window
var _overlay_root: Node2D
var _fox: RigidBody2D
var _fox_screen_position := Vector2.ZERO
var _fox_velocity := Vector2.ZERO
var _last_mouse_screen_position := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO
var _dragging := false
var _drag_screen_offset := Vector2.ZERO
var _hovering := false
var _is_starting := false
var _fox_scale := 3.0
var _fox_opacity := 1.0
var _click_through_enabled := false
var _hover_fade_enabled := false
var _taskbar_snap_enabled := true
var _body_speed_multiplier := 1.0
var _syncing_ui := false
var _fox_spawned := false


func _ready() -> void:
	randomize()
	_setup_launcher_window()
	_setup_menu_nodes()
	_last_mouse_screen_position = Vector2(DisplayServer.mouse_get_position())


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_fox):
		return

	var mouse_screen_position := Vector2(DisplayServer.mouse_get_position())
	_mouse_velocity = (mouse_screen_position - _last_mouse_screen_position) / maxf(delta, 0.001)
	_last_mouse_screen_position = mouse_screen_position

	if _dragging:
		_fox_screen_position = (mouse_screen_position + _drag_screen_offset).round()
		_fox_velocity = _mouse_velocity
	else:
		_apply_gravity(delta)
		_update_hover(mouse_screen_position)

	_apply_screen_bounds()
	_sync_overlay_window()


func _unhandled_input(event: InputEvent) -> void:
	if _is_starting or not is_instance_valid(_preview_fox):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _preview_fox.global_position.distance_to(get_global_mouse_position()) <= _get_preview_fox_radius():
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
	_customize_button.pressed.connect(_on_customize_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_about_button.pressed.connect(_on_about_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_settings_close_button.pressed.connect(_hide_settings_panel)
	_customize_close_button.pressed.connect(_hide_customize_panel)
	_body_speed_slider.value_changed.connect(_on_body_speed_changed)
	_click_through_toggle.toggled.connect(_on_click_through_toggled)
	_hover_fade_toggle.toggled.connect(_on_hover_fade_toggled)
	_taskbar_snap_toggle.toggled.connect(_on_taskbar_snap_toggled)
	_scale_slider.value_changed.connect(_on_scale_changed)
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	_taskbar_height_slider.value_changed.connect(_on_taskbar_height_changed)
	_reset_fox_button.pressed.connect(_reset_fox_position)
	_spawn_fox_button.pressed.connect(_spawn_fox_from_settings)
	_hide_fox_button.pressed.connect(_despawn_fox)
	_reset_all_button.pressed.connect(_reset_fox_settings)

	_preview_fox.freeze = true
	_preview_fox.call("set_highlight", false, hover_modulate)
	_apply_fox_settings(_preview_fox)
	_apply_fox_cosmetics(_preview_fox)
	_refresh_ui()


func _on_start_pressed() -> void:
	if _is_starting:
		return
	_is_starting = true
	_start_button.disabled = true
	_status_label.text = "Fox launching..."
	_preview_fox.call("pulse_click")
	await get_tree().create_timer(0.14).timeout
	_spawn_fox(_get_preview_fox_screen_position())
	_preview_fox.visible = false
	if is_instance_valid(_fox):
		_fox.call("pulse_click")
	if minimize_launcher_after_spawn:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_settings_pressed() -> void:
	_customize_panel.visible = false
	_settings_panel.visible = true
	_status_label.text = "Tune your fox."


func _on_customize_pressed() -> void:
	_settings_panel.visible = false
	_customize_panel.visible = true
	_status_label.text = "Focus Fox style."


func _on_about_pressed() -> void:
	_status_label.text = "A tiny fox that lands by your taskbar."


func _hide_settings_panel() -> void:
	_settings_panel.visible = false
	_status_label.text = "Drag the fox around your desktop."


func _hide_customize_panel() -> void:
	_customize_panel.visible = false
	_status_label.text = "Drag the fox around your desktop."


func _on_click_through_toggled(enabled: bool) -> void:
	_click_through_enabled = enabled
	if enabled and _dragging:
		_release_drag()
	_apply_click_through_mode()
	_status_label.text = "Click-through on" if enabled else "Click-through off"


func _on_hover_fade_toggled(enabled: bool) -> void:
	_hover_fade_enabled = enabled
	_apply_fox_visual_state()
	_status_label.text = "Opacity applies on hover" if enabled else "Opacity always applies"


func _on_taskbar_snap_toggled(enabled: bool) -> void:
	_taskbar_snap_enabled = enabled
	_refresh_ui()
	if is_instance_valid(_fox):
		_apply_screen_bounds()
		_sync_overlay_window()
	_status_label.text = "Taskbar snap on" if enabled else "Taskbar snap off"


func _on_scale_changed(value: float) -> void:
	if _syncing_ui:
		return
	_fox_scale = value
	_apply_fox_settings(_preview_fox)
	_apply_fox_settings(_fox)
	_status_label.text = "Fox scale %.2fx" % value


func _on_opacity_changed(value: float) -> void:
	if _syncing_ui:
		return
	_fox_opacity = value
	_apply_fox_visual_state()
	_status_label.text = "Opacity %d%%" % roundi(value * 100.0)


func _on_taskbar_height_changed(value: float) -> void:
	if _syncing_ui:
		return
	taskbar_height = value
	_refresh_ui()
	if is_instance_valid(_fox):
		_apply_screen_bounds()
		_sync_overlay_window()
	_status_label.text = "Taskbar height %d px" % roundi(taskbar_height)


func _reset_fox_position() -> void:
	if not is_instance_valid(_fox):
		return
	var screen_rect := _get_target_screen_rect()
	var radius := _get_fox_radius() + fox_edge_padding
	_fox_screen_position = Vector2(screen_rect.position.x + screen_rect.size.x * 0.5, screen_rect.end.y - _get_floor_offset() - radius)
	_fox_velocity = Vector2.ZERO
	_dragging = false
	_sync_overlay_window()
	_status_label.text = "Fox position reset"


func _apply_fox_settings(fox_node: RigidBody2D) -> void:
	if not is_instance_valid(fox_node):
		return
	fox_node.scale = Vector2.ONE * _fox_scale
	_apply_fox_visual_state()


func _apply_fox_cosmetics(fox_node: RigidBody2D) -> void:
	if not is_instance_valid(fox_node):
		return
	fox_node.call("set_body_theme", "fox")
	fox_node.call("set_body_rotation_speed", _body_speed_multiplier)


func _apply_fox_visual_state() -> void:
	var target_alpha := _fox_opacity
	if _hover_fade_enabled:
		target_alpha = _fox_opacity if (_hovering or _dragging) else 1.0
	if is_instance_valid(_fox):
		_fox.modulate.a = target_alpha
	if is_instance_valid(_preview_fox):
		_preview_fox.modulate.a = _fox_opacity


func _apply_click_through_mode() -> void:
	if not is_instance_valid(_overlay_window):
		return
	_overlay_window.mouse_passthrough = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false, _overlay_window.get_window_id())
	var active_polygon := _get_full_window_polygon() if _click_through_enabled else _get_fox_click_polygon()
	_overlay_window.mouse_passthrough_polygon = active_polygon
	DisplayServer.window_set_mouse_passthrough(active_polygon, _overlay_window.get_window_id())


func _get_full_window_polygon() -> PackedVector2Array:
	var size := Vector2(fox_window_size)
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])


func _get_fox_click_polygon() -> PackedVector2Array:
	var radius := _get_fox_radius()
	var center := Vector2(fox_window_size) * 0.5
	var points := PackedVector2Array()
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _create_overlay_window() -> void:
	if is_instance_valid(_overlay_window):
		return
	var window := Window.new()
	window.name = "FocusFoxOverlay"
	window.size = fox_window_size
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	window.unresizable = true
	window.gui_embed_subwindows = false
	window.position = _get_offscreen_overlay_position()
	window.visible = false
	window.close_requested.connect(_despawn_fox)
	window.window_input.connect(_on_overlay_window_input)
	add_child(window)

	var root := Node2D.new()
	root.name = "OverlayWorld"
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window.add_child(root)
	_overlay_window = window
	_overlay_root = root


func _get_offscreen_overlay_position() -> Vector2i:
	var screen_rect := _get_target_screen_rect()
	return screen_rect.end + fox_window_size + Vector2i(96, 96)


func _spawn_fox(spawn_position: Vector2) -> void:
	_create_overlay_window()
	if not is_instance_valid(_fox):
		_fox = FOX_SCENE.instantiate() as RigidBody2D
		_overlay_root.add_child(_fox)
		_fox.position = Vector2(fox_window_size) * 0.5
		_fox.mass = 1.0
		_fox.freeze = true
		_fox.linear_velocity = Vector2.ZERO
		_fox.angular_velocity = 0.0
		_fox.call("set_highlight", false, hover_modulate)
		_apply_fox_settings(_fox)
		_apply_fox_cosmetics(_fox)
	_fox_screen_position = spawn_position
	_fox_velocity = Vector2.ZERO
	_dragging = false
	_hovering = false
	_fox_spawned = true
	_overlay_window.show()
	_apply_click_through_mode()
	_sync_overlay_window()
	_refresh_ui()


func _spawn_fox_from_settings() -> void:
	if _fox_spawned:
		_status_label.text = "Fox already active"
		return
	var screen_rect := _get_target_screen_rect()
	_spawn_fox(Vector2(screen_rect.get_center()))
	_preview_fox.visible = false
	_start_button.disabled = true
	_status_label.text = "Fox spawned"


func _despawn_fox() -> void:
	if is_instance_valid(_overlay_window):
		_overlay_window.hide()
	if is_instance_valid(_fox):
		_fox.queue_free()
		_fox = null
	_fox_spawned = false
	_dragging = false
	_hovering = false
	_preview_fox.visible = true
	_start_button.disabled = false
	_refresh_ui()
	_status_label.text = "Fox hidden"


func _reset_fox_settings() -> void:
	_fox_scale = 3.0
	_fox_opacity = 1.0
	_body_speed_multiplier = 1.0
	_taskbar_snap_enabled = true
	taskbar_height = 48.0
	_apply_fox_settings(_preview_fox)
	_apply_fox_settings(_fox)
	_apply_fox_cosmetics(_preview_fox)
	_apply_fox_cosmetics(_fox)
	_refresh_ui()
	_status_label.text = "Fox settings reset"


func _on_body_speed_changed(value: float) -> void:
	if _syncing_ui:
		return
	_body_speed_multiplier = value
	_apply_fox_cosmetics(_preview_fox)
	_apply_fox_cosmetics(_fox)
	_status_label.text = "Sprite speed %.1fx" % value


func _refresh_ui() -> void:
	_syncing_ui = true
	_fox_status_label.text = "Fox: active" if _fox_spawned else "Fox: menu preview"
	_scale_slider.value = _fox_scale
	_opacity_slider.value = _fox_opacity
	_taskbar_height_slider.value = taskbar_height
	_taskbar_snap_toggle.button_pressed = _taskbar_snap_enabled
	_body_speed_slider.value = _body_speed_multiplier
	_settings_hint_label.text = "Taskbar height controls where the fox lands."
	_syncing_ui = false


func _on_overlay_window_input(event: InputEvent) -> void:
	if _click_through_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_screen_position := Vector2(DisplayServer.mouse_get_position())
		if event.pressed:
			if _local_position_hits_fox(event.position):
				_start_drag(mouse_screen_position)
				get_viewport().set_input_as_handled()
		elif _dragging:
			_release_drag()
			get_viewport().set_input_as_handled()


func _start_drag(mouse_screen_position: Vector2) -> void:
	_dragging = true
	_drag_screen_offset = _fox_screen_position - mouse_screen_position
	_fox_velocity = Vector2.ZERO
	_set_fox_highlight(true)
	_apply_fox_visual_state()
	if is_instance_valid(_fox):
		_fox.call("pulse_click")


func _release_drag() -> void:
	_dragging = false
	_fox_velocity = (_mouse_velocity * throw_boost).limit_length(max_throw_speed)
	_set_fox_highlight(false)
	_apply_fox_visual_state()


func _apply_gravity(delta: float) -> void:
	_fox_velocity.y += fox_gravity * delta
	_fox_screen_position += _fox_velocity * delta
	_fox_velocity.x = move_toward(_fox_velocity.x, 0.0, floor_friction * 100.0 * delta)


func _apply_screen_bounds() -> void:
	var screen_rect := _get_target_screen_rect()
	var window_half_size := Vector2(fox_window_size) * 0.5
	var radius := _get_fox_radius() + fox_edge_padding
	var min_x := float(screen_rect.position.x) + maxf(window_half_size.x, radius)
	var max_x := float(screen_rect.end.x) - maxf(window_half_size.x, radius)
	var min_y := float(screen_rect.position.y) + maxf(window_half_size.y, radius)
	var floor_y := float(screen_rect.end.y) - _get_floor_offset() - maxf(window_half_size.y, radius)
	var bumped := false

	if _fox_screen_position.x < min_x:
		_fox_screen_position.x = min_x
		_fox_velocity.x = absf(_fox_velocity.x) * fox_bounce
		bumped = true
	elif _fox_screen_position.x > max_x:
		_fox_screen_position.x = max_x
		_fox_velocity.x = -absf(_fox_velocity.x) * fox_bounce
		bumped = true

	if _fox_screen_position.y < min_y:
		_fox_screen_position.y = min_y
		_fox_velocity.y = absf(_fox_velocity.y) * fox_bounce
		bumped = true
	elif _fox_screen_position.y > floor_y:
		_fox_screen_position.y = floor_y
		if absf(_fox_velocity.y) < 30.0:
			_fox_velocity.y = 0.0
		else:
			_fox_velocity.y = -absf(_fox_velocity.y) * fox_bounce
		_fox_velocity.x = move_toward(_fox_velocity.x, 0.0, floor_friction * 160.0 / maxf(1.0, _fox_scale))
		bumped = true

	if bumped and is_instance_valid(_fox):
		_fox.call("react_bumped")


func _get_floor_offset() -> float:
	return taskbar_height if _taskbar_snap_enabled else 0.0


func _sync_overlay_window() -> void:
	if is_instance_valid(_overlay_window):
		_overlay_window.position = Vector2i((_fox_screen_position - Vector2(fox_window_size) * 0.5).round())


func _update_hover(mouse_screen_position: Vector2) -> void:
	if not is_instance_valid(_overlay_window):
		return
	var local_mouse := mouse_screen_position - Vector2(_overlay_window.position)
	var hovering := _local_position_hits_fox(local_mouse)
	if hovering == _hovering:
		return
	_hovering = hovering
	_set_fox_highlight(_hovering)
	_apply_fox_visual_state()


func _local_position_hits_fox(local_position: Vector2) -> bool:
	return local_position.distance_to(Vector2(fox_window_size) * 0.5) <= _get_fox_radius()


func _set_fox_highlight(highlighted: bool) -> void:
	if is_instance_valid(_fox):
		_fox.call("set_highlight", highlighted, hover_modulate)


func _get_fox_radius() -> float:
	if is_instance_valid(_fox):
		var radius: Variant = _fox.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	if is_instance_valid(_preview_fox):
		var preview_radius: Variant = _preview_fox.call("get_pick_radius")
		if typeof(preview_radius) == TYPE_FLOAT or typeof(preview_radius) == TYPE_INT:
			return float(preview_radius)
	return 64.0


func _get_preview_fox_radius() -> float:
	if is_instance_valid(_preview_fox):
		var radius: Variant = _preview_fox.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	return 64.0


func _get_preview_fox_screen_position() -> Vector2:
	var window := get_window()
	var viewport_size := get_viewport_rect().size
	var window_size := Vector2(window.size)
	var scale := Vector2.ONE
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		scale = Vector2(window_size.x / viewport_size.x, window_size.y / viewport_size.y)
	return Vector2(window.position) + _preview_fox.global_position * scale


func _get_target_screen_rect() -> Rect2i:
	var screen_index := DisplayServer.window_get_current_screen()
	if use_usable_screen_area:
		return DisplayServer.screen_get_usable_rect(screen_index)
	return Rect2i(Vector2i.ZERO, DisplayServer.screen_get_size(screen_index))
