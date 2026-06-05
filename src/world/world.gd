extends Node2D

const PLANETOID_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")

@export_group("Launcher")
@export var launcher_window_size := Vector2i(520, 320)
@export var minimize_launcher_after_spawn := true

@export_group("Moon Window")
@export var moon_window_size := Vector2i(420, 420)
@export var use_usable_screen_area := true
@export var moon_edge_padding := 18.0

@export_group("Moon Feel")
@export var moon_weight := 1.15
@export var throw_boost := 0.72
@export var max_throw_speed := 1850.0
@export var damping_at_weight_one := 1.08
@export var edge_bounce := 0.78
@export var hover_modulate := Color(1.18, 1.14, 1.28, 1.0)

@onready var _spawn_button: Button = $MenuLayer/MainMenu/Panel/Actions/SpawnMoonButton
@onready var _quit_button: Button = $MenuLayer/MainMenu/Panel/Actions/QuitButton
@onready var _status_label: Label = $MenuLayer/MainMenu/Panel/StatusLabel

var _overlay_window: Window
var _overlay_root: Node2D
var _moon: RigidBody2D
var _moon_screen_position := Vector2.ZERO
var _moon_velocity := Vector2.ZERO
var _last_mouse_screen_position := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO
var _dragging := false
var _drag_screen_offset := Vector2.ZERO
var _hovering := false


func _ready() -> void:
	randomize()
	_setup_launcher_window()
	_spawn_button.pressed.connect(_on_spawn_moon_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_last_mouse_screen_position = Vector2(DisplayServer.mouse_get_position())


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_overlay_window) or not is_instance_valid(_moon):
		return

	var mouse_screen_position := Vector2(DisplayServer.mouse_get_position())
	_mouse_velocity = (mouse_screen_position - _last_mouse_screen_position) / maxf(delta, 0.001)
	_last_mouse_screen_position = mouse_screen_position

	if _dragging:
		_moon_screen_position = (mouse_screen_position + _drag_screen_offset).round()
		_moon_velocity = _mouse_velocity
	else:
		_apply_drift(delta)
		_update_hover(mouse_screen_position)

	_apply_screen_bounds()
	_sync_overlay_window()


func _setup_launcher_window() -> void:
	RenderingServer.set_default_clear_color(Color.TRANSPARENT)
	get_viewport().transparent_bg = false

	var window := get_window()
	window.title = "Desktop Moons"
	window.borderless = false
	window.always_on_top = false
	window.transparent = false
	window.transparent_bg = false
	window.unresizable = false
	window.gui_embed_subwindows = false
	window.size = launcher_window_size

	var usable_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	window.position = usable_rect.position + (usable_rect.size - launcher_window_size) / 2


func _on_spawn_moon_pressed() -> void:
	_spawn_button.disabled = true
	_status_label.text = "Moon active"

	if not is_instance_valid(_overlay_window):
		_create_overlay_window()
		await _show_overlay_window()

	if not is_instance_valid(_moon):
		_spawn_moon()

	if minimize_launcher_after_spawn:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _create_overlay_window() -> void:
	_overlay_window = Window.new()
	_overlay_window.name = "DesktopMoonOverlay"
	_overlay_window.size = moon_window_size
	_overlay_window.borderless = true
	_overlay_window.always_on_top = true
	_overlay_window.transparent = true
	_overlay_window.transparent_bg = true
	_overlay_window.unresizable = true
	_overlay_window.gui_embed_subwindows = false
	_overlay_window.visible = false
	_overlay_window.close_requested.connect(get_tree().quit)
	_overlay_window.window_input.connect(_on_overlay_window_input)
	add_child(_overlay_window)

	_overlay_root = Node2D.new()
	_overlay_root.name = "OverlayWorld"
	_overlay_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay_window.add_child(_overlay_root)


func _show_overlay_window() -> void:
	var screen_rect := _get_target_screen_rect()
	_moon_screen_position = Vector2(screen_rect.get_center())
	_sync_overlay_window()
	_overlay_window.show()
	await get_tree().process_frame


func _spawn_moon() -> void:
	_moon = PLANETOID_SCENE.instantiate() as RigidBody2D
	_overlay_root.add_child(_moon)
	_moon.position = Vector2(moon_window_size) * 0.5
	_moon.mass = moon_weight
	_moon.freeze = true
	_moon.linear_velocity = Vector2.ZERO
	_moon.angular_velocity = 0.0
	if _moon.has_method("set_highlight"):
		_moon.call("set_highlight", false, hover_modulate)


func _on_overlay_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_screen_position := Vector2(DisplayServer.mouse_get_position())
		if event.pressed:
			if _local_position_hits_moon(event.position):
				_start_drag(mouse_screen_position)
				get_viewport().set_input_as_handled()
		elif _dragging:
			_release_drag()
			get_viewport().set_input_as_handled()


func _start_drag(mouse_screen_position: Vector2) -> void:
	_dragging = true
	_drag_screen_offset = _moon_screen_position - mouse_screen_position
	_moon_velocity = Vector2.ZERO
	_set_moon_highlight(true)


func _release_drag() -> void:
	_dragging = false
	_moon_velocity = (_mouse_velocity * throw_boost).limit_length(max_throw_speed)
	_set_moon_highlight(false)


func _apply_drift(delta: float) -> void:
	_moon_screen_position += _moon_velocity * delta
	var damping := damping_at_weight_one / maxf(0.08, moon_weight)
	_moon_velocity = _moon_velocity.move_toward(Vector2.ZERO, damping * 1000.0 * delta)


func _apply_screen_bounds() -> void:
	var screen_rect := _get_target_screen_rect()
	var radius := _get_moon_radius() + moon_edge_padding
	var min_position := Vector2(screen_rect.position) + Vector2(radius, radius)
	var max_position := Vector2(screen_rect.end) - Vector2(radius, radius)

	if _moon_screen_position.x < min_position.x:
		_moon_screen_position.x = min_position.x
		_moon_velocity.x = absf(_moon_velocity.x) * edge_bounce
	elif _moon_screen_position.x > max_position.x:
		_moon_screen_position.x = max_position.x
		_moon_velocity.x = -absf(_moon_velocity.x) * edge_bounce

	if _moon_screen_position.y < min_position.y:
		_moon_screen_position.y = min_position.y
		_moon_velocity.y = absf(_moon_velocity.y) * edge_bounce
	elif _moon_screen_position.y > max_position.y:
		_moon_screen_position.y = max_position.y
		_moon_velocity.y = -absf(_moon_velocity.y) * edge_bounce


func _sync_overlay_window() -> void:
	if not is_instance_valid(_overlay_window):
		return
	_overlay_window.position = Vector2i((_moon_screen_position - Vector2(moon_window_size) * 0.5).round())


func _update_hover(mouse_screen_position: Vector2) -> void:
	var local_mouse := mouse_screen_position - Vector2(_overlay_window.position)
	var hovering := _local_position_hits_moon(local_mouse)
	if hovering == _hovering:
		return
	_hovering = hovering
	_set_moon_highlight(_hovering)


func _local_position_hits_moon(local_position: Vector2) -> bool:
	return local_position.distance_to(Vector2(moon_window_size) * 0.5) <= _get_moon_radius()


func _set_moon_highlight(highlighted: bool) -> void:
	if is_instance_valid(_moon) and _moon.has_method("set_highlight"):
		_moon.call("set_highlight", highlighted, hover_modulate)


func _get_moon_radius() -> float:
	if is_instance_valid(_moon) and _moon.has_method("get_pick_radius"):
		var radius: Variant = _moon.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	return 120.0


func _get_target_screen_rect() -> Rect2i:
	var screen_index := DisplayServer.window_get_current_screen()
	if use_usable_screen_area:
		return DisplayServer.screen_get_usable_rect(screen_index)
	return Rect2i(Vector2i.ZERO, DisplayServer.screen_get_size(screen_index))
