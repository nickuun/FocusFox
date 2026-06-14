extends Node
class_name DesktopFox

const FOX_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")

@export var fox_window_size := Vector2i(320, 320)
@export var fox_window_padding := Vector2i(192, 192)
@export var use_usable_screen_area := true
@export var fox_edge_padding := 2.0
@export var taskbar_height := 24.0
@export var fox_gravity := 2450.0
@export var fox_bounce := 0.18
@export var throw_boost := 0.72
@export var max_throw_speed := 1850.0
@export var floor_friction := 6.5
@export var hover_modulate := Color(1.12, 1.08, 1.16, 1.0)
@export var landing_offset := 40.0
@export var floor_snap_tolerance := 2.0
@export var rest_velocity_threshold := 24.0

var fox_scale := 3.0
var fox_opacity := 1.0
var click_through_enabled := false
var hover_fade_enabled := false
var taskbar_snap_enabled := true
var body_speed_multiplier := 1.0

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
var _resting_on_floor := false

signal fox_spawned_changed(active: bool)
signal status_changed(message: String)


func initialize() -> void:
	_last_mouse_screen_position = Vector2(DisplayServer.mouse_get_position())


func physics_step(delta: float) -> void:
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
	_fox_screen_position = _fox_screen_position.round()
	_sync_overlay_window()


func handle_overlay_input(event: InputEvent) -> void:
	if click_through_enabled:
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


func apply_visual_settings() -> void:
	_apply_fox_visual_state()
	_apply_click_through_mode()
	_apply_fox_settings(_fox)


func apply_cosmetics_to(node: RigidBody2D) -> void:
	if not is_instance_valid(node):
		return
	var pixel_scale := roundf(fox_scale)
	if pixel_scale < 1.0:
		pixel_scale = 1.0
	node.scale = Vector2.ONE * pixel_scale
	node.call("set_body_theme", "fox")
	node.call("set_body_rotation_speed", body_speed_multiplier)
	_update_window_size_for_scale(pixel_scale)


func spawn_fox(spawn_position: Vector2) -> void:
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
		apply_cosmetics_to(_fox)
	_fox_screen_position = spawn_position
	_fox_velocity = Vector2.ZERO
	_dragging = false
	_hovering = false
	_overlay_window.show()
	_apply_click_through_mode()
	_sync_overlay_window()
	fox_spawned_changed.emit(true)


func spawn_at_screen_center() -> void:
	var screen_rect := _get_target_screen_rect()
	spawn_fox(Vector2(screen_rect.get_center()))
	status_changed.emit("Fox spawned")


func despawn_fox() -> void:
	if is_instance_valid(_overlay_window):
		_overlay_window.hide()
	if is_instance_valid(_fox):
		_fox.queue_free()
		_fox = null
	_dragging = false
	_hovering = false
	fox_spawned_changed.emit(false)
	status_changed.emit("Fox hidden")


func reset_fox_position() -> void:
	if not is_instance_valid(_fox):
		return
	var screen_rect := _get_target_screen_rect()
	var radius := _get_fox_radius() + fox_edge_padding
	var window_half_size := Vector2(_get_window_size_for_scale()) * 0.5
	_fox_screen_position = Vector2(screen_rect.position.x + screen_rect.size.x * 0.5, screen_rect.end.y - _get_floor_offset() - maxf(window_half_size.y, radius) + landing_offset)
	_fox_velocity = Vector2.ZERO
	_dragging = false
	_sync_overlay_window()
	status_changed.emit("Fox position reset")


func is_spawned() -> bool:
	return is_instance_valid(_fox)


func get_fox_radius(preview_fox: RigidBody2D) -> float:
	if is_instance_valid(_fox):
		var radius: Variant = _fox.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	if is_instance_valid(preview_fox):
		var preview_radius: Variant = preview_fox.call("get_pick_radius")
		if typeof(preview_radius) == TYPE_FLOAT or typeof(preview_radius) == TYPE_INT:
			return float(preview_radius)
	return 64.0


func get_preview_screen_position(preview_fox: RigidBody2D) -> Vector2:
	var window := get_window()
	var viewport_size := get_tree().root.get_visible_rect().size
	var window_size := Vector2(window.size)
	var scale := Vector2.ONE
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		scale = Vector2(window_size.x / viewport_size.x, window_size.y / viewport_size.y)
	return Vector2(window.position) + preview_fox.global_position * scale


func _apply_fox_settings(fox_node: RigidBody2D) -> void:
	if not is_instance_valid(fox_node):
		return
	var pixel_scale := roundf(fox_scale)
	if pixel_scale < 1.0:
		pixel_scale = 1.0
	fox_node.scale = Vector2.ONE * pixel_scale
	_apply_fox_visual_state()


func _apply_fox_visual_state() -> void:
	var target_alpha := fox_opacity
	if hover_fade_enabled:
		target_alpha = fox_opacity if (_hovering or _dragging) else 1.0
	if is_instance_valid(_fox):
		_fox.modulate.a = target_alpha


func _apply_click_through_mode() -> void:
	if not is_instance_valid(_overlay_window):
		return
	_overlay_window.mouse_passthrough = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false, _overlay_window.get_window_id())
	var active_polygon := _get_full_window_polygon() if click_through_enabled else _get_fox_click_polygon()
	_overlay_window.mouse_passthrough_polygon = active_polygon
	DisplayServer.window_set_mouse_passthrough(active_polygon, _overlay_window.get_window_id())


func _get_full_window_polygon() -> PackedVector2Array:
	var size := Vector2(fox_window_size)
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])


func _get_fox_click_polygon() -> PackedVector2Array:
	var radius := _get_fox_radius()
	var center := Vector2(_get_window_size_for_scale()) * 0.5
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
	window.size = _get_window_size_for_scale()
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	window.unresizable = true
	window.gui_embed_subwindows = false
	window.position = _get_offscreen_overlay_position()
	window.visible = false
	window.close_requested.connect(despawn_fox)
	window.window_input.connect(handle_overlay_input)
	add_child(window)

	var root := Node2D.new()
	root.name = "OverlayWorld"
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window.add_child(root)
	_overlay_window = window
	_overlay_root = root


func _get_offscreen_overlay_position() -> Vector2i:
	var screen_rect := _get_target_screen_rect()
	return screen_rect.end + _get_window_size_for_scale() + Vector2i(96, 96)


func _get_window_size_for_scale() -> Vector2i:
	var pixel_scale := roundi(maxf(1.0, roundf(fox_scale)))
	var sprite_size := Vector2i(32, 32) * pixel_scale
	return Vector2i(
		max(fox_window_size.x, sprite_size.x + fox_window_padding.x),
		max(fox_window_size.y, sprite_size.y + fox_window_padding.y)
	)


func _update_window_size_for_scale(pixel_scale: float) -> void:
	if not is_instance_valid(_overlay_window):
		return
	var old_size := _overlay_window.size
	var new_size := Vector2i(
		max(fox_window_size.x, int(32.0 * pixel_scale) + fox_window_padding.x),
		max(fox_window_size.y, int(32.0 * pixel_scale) + fox_window_padding.y)
	)
	if old_size == new_size:
		return
	_overlay_window.size = new_size
	_sync_overlay_window()


func _start_drag(mouse_screen_position: Vector2) -> void:
	_dragging = true
	_resting_on_floor = false
	_drag_screen_offset = _fox_screen_position - mouse_screen_position
	_fox_velocity = Vector2.ZERO
	_set_fox_highlight(true)
	_apply_fox_visual_state()
	if is_instance_valid(_fox):
		_fox.call("pulse_click")


func _release_drag() -> void:
	_dragging = false
	_resting_on_floor = false
	_fox_velocity = (_mouse_velocity * throw_boost).limit_length(max_throw_speed)
	_set_fox_highlight(false)
	_apply_fox_visual_state()


func _apply_gravity(delta: float) -> void:
	if _resting_on_floor:
		_fox_velocity = Vector2.ZERO
		return
	_fox_velocity.y += fox_gravity * delta
	_fox_screen_position += _fox_velocity * delta
	_fox_velocity.x = move_toward(_fox_velocity.x, 0.0, floor_friction * 100.0 * delta)


func _apply_screen_bounds() -> void:
	var screen_rect := _get_target_screen_rect()
	var window_half_size := Vector2(_get_window_size_for_scale()) * 0.5
	var radius := _get_fox_radius() + fox_edge_padding
	var min_x := float(screen_rect.position.x) + maxf(window_half_size.x, radius)
	var max_x := float(screen_rect.end.x) - maxf(window_half_size.x, radius)
	var min_y := float(screen_rect.position.y) + maxf(window_half_size.y, radius)
	var floor_y := float(screen_rect.end.y) - _get_floor_offset() - maxf(window_half_size.y, radius) + landing_offset
	var bumped := false
	var hit_floor := false

	if _fox_screen_position.x < min_x:
		_fox_screen_position.x = min_x
		if absf(_fox_velocity.x) > rest_velocity_threshold:
			_fox_velocity.x = absf(_fox_velocity.x) * fox_bounce
		else:
			_fox_velocity.x = 0.0
		bumped = true
	elif _fox_screen_position.x > max_x:
		_fox_screen_position.x = max_x
		if absf(_fox_velocity.x) > rest_velocity_threshold:
			_fox_velocity.x = -absf(_fox_velocity.x) * fox_bounce
		else:
			_fox_velocity.x = 0.0
		bumped = true

	if _fox_screen_position.y < min_y:
		_fox_screen_position.y = min_y
		if absf(_fox_velocity.y) > rest_velocity_threshold:
			_fox_velocity.y = absf(_fox_velocity.y) * fox_bounce
		else:
			_fox_velocity.y = 0.0
		bumped = true
	elif _fox_screen_position.y >= floor_y - floor_snap_tolerance:
		hit_floor = true
		_fox_screen_position.y = floor_y
		if absf(_fox_velocity.y) <= rest_velocity_threshold:
			_fox_velocity.y = 0.0
			if absf(_fox_velocity.x) <= rest_velocity_threshold:
				_fox_velocity.x = 0.0
				_resting_on_floor = true
		else:
			_fox_velocity.y = -absf(_fox_velocity.y) * fox_bounce
			_fox_velocity.x = move_toward(_fox_velocity.x, 0.0, floor_friction * 120.0 / maxf(1.0, fox_scale))
			bumped = true

	if not hit_floor:
		_resting_on_floor = false

	if bumped and is_instance_valid(_fox):
		_fox.call("react_bumped")


func _get_floor_offset() -> float:
	return taskbar_height if taskbar_snap_enabled else 0.0


func _sync_overlay_window() -> void:
	if is_instance_valid(_overlay_window):
		_overlay_window.position = Vector2i((_fox_screen_position - Vector2(_get_window_size_for_scale()) * 0.5).round())


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
	return 64.0


func _get_target_screen_rect() -> Rect2i:
	var screen_index := DisplayServer.window_get_current_screen()
	if use_usable_screen_area:
		return DisplayServer.screen_get_usable_rect(screen_index)
	return Rect2i(Vector2i.ZERO, DisplayServer.screen_get_size(screen_index))
