extends Node
class_name DesktopFox

const FOX_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")
const BALL_TEXTURE: Texture2D = preload("res://assets/extras/balls/basic-ball.png")
const BALL_SPRITE_PX := 11.0

@export var fox_window_size := Vector2i(320, 320)
@export var fox_window_padding := Vector2i(128, 128)
@export var use_usable_screen_area := true
@export var fox_edge_padding := 2.0
@export var taskbar_height := 24.0
@export var fox_gravity := 2450.0
@export var fox_bounce := 0.18
@export var throw_boost := 0.72
@export var max_throw_speed := 1850.0
@export var floor_friction := 6.5
@export var hover_modulate := Color(1.12, 1.08, 1.16, 1.0)
@export var landing_offset := 16.0
@export var floor_snap_tolerance := 2.0
@export var rest_velocity_threshold := 24.0

@export_group("Break play")
@export var trot_speed := 360.0
@export var pounce_range := 220.0   # distance the fox leaps from to land on the ball
@export var pounce_duration := 0.52
@export var pounce_height := 95.0   # arc peak, multiplied by fox scale
@export var settle_min := 2.0
@export var settle_max := 4.5
@export var play_gap_min := 6.0
@export var play_gap_max := 12.0
@export var ball_relative_scale := 3.5
@export var ball_window_padding := 56
@export var ball_gravity := 2600.0
@export var ball_bounce := 0.62
@export var ball_floor_friction := 2.4
@export var ball_throw_boost := 0.85
@export var ball_max_throw_speed := 2600.0
@export var ball_rest_threshold := 28.0
@export var ball_kick_up := 540.0
@export var ball_kick_side := 360.0

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
# Rendered footprint of the fox sprite at body scale 1 (texture * sprite's own
# scale). Cached from the fox/preview so the overlay window always fits the fox.
var _fox_sprite_base := Vector2(160.0, 160.0)

var _activity := "idle"  # idle / working / break
var _ball_window: Window
var _ball_root: Node2D
var _ball_sprite: Sprite2D
var _ball_active := false
var _ball_screen_position := Vector2.ZERO
var _ball_velocity := Vector2.ZERO
var _ball_dragging := false
var _ball_drag_offset := Vector2.ZERO
var _ball_resting := false
var _ball_px := 60.0
var _play_state := "none"  # none / trot / pounce / settle / gap
var _settle_timer := 0.0
var _gap_timer := 0.0
var _pounce_t := 0.0
var _pounce_start := Vector2.ZERO
var _pounce_target := Vector2.ZERO
var _pounce_peak := 0.0

var fox_palette := "default"
var _palettes := {
	"default": [Color("d67941"), Color("9d5021")],
	"red": [Color("d6534a"), Color("9e2c22")],
	"gray": [Color("b0b0b0"), Color("6b6b6b")],
	"lightbrown": [Color("c89b6a"), Color("936a3c")],
	"darkbrown": [Color("8a5a30"), Color("543313")],
	"black": [Color("4a4a4a"), Color("1e1e1e")],
}

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
		var skip_gravity := false
		if _play_state != "none":
			skip_gravity = _update_ball_play(delta)
		if not skip_gravity:
			_apply_gravity(delta)
		_update_hover(mouse_screen_position)

	_apply_screen_bounds()
	_fox_screen_position = _fox_screen_position.round()
	_sync_overlay_window()

	if _ball_active:
		_update_ball_physics(delta, mouse_screen_position)
		_sync_ball_window()


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
	_apply_palette_to(_fox)


func apply_cosmetics_to(node: RigidBody2D) -> void:
	if not is_instance_valid(node):
		return
	var pixel_scale := roundf(fox_scale)
	if pixel_scale < 1.0:
		pixel_scale = 1.0
	node.scale = Vector2.ONE * pixel_scale
	node.call("set_body_theme", "fox")
	node.call("set_body_rotation_speed", body_speed_multiplier)
	_apply_palette_to(node)
	_cache_sprite_base(node)
	_update_window_size_for_scale(pixel_scale)


func _apply_palette_to(node: RigidBody2D) -> void:
	if not is_instance_valid(node) or not node.has_method("set_palette"):
		return
	var is_rainbow := fox_palette == "rainbow"
	var pair: Array = _palettes.get(fox_palette, _palettes["default"])
	node.call("set_palette", pair[0], pair[1], is_rainbow)


func _cache_sprite_base(node: RigidBody2D) -> void:
	if not is_instance_valid(node) or not node.has_method("get_sprite_pixel_size"):
		return
	var size: Variant = node.call("get_sprite_pixel_size")
	if size is Vector2 and (size as Vector2).x > 0.0 and (size as Vector2).y > 0.0:
		_fox_sprite_base = size


func spawn_fox(spawn_position: Vector2) -> void:
	_create_overlay_window()
	if not is_instance_valid(_fox):
		_fox = FOX_SCENE.instantiate() as RigidBody2D
		_overlay_root.add_child(_fox)
		_fox.position = Vector2(_get_window_size_for_scale()) * 0.5
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
	_apply_activity()
	fox_spawned_changed.emit(true)


func spawn_at_screen_center() -> void:
	var screen_rect := _get_target_screen_rect()
	spawn_fox(Vector2(screen_rect.get_center()))
	status_changed.emit("Fox spawned")


func despawn_fox() -> void:
	_end_ball_play()
	if is_instance_valid(_overlay_window):
		_overlay_window.hide()
	if is_instance_valid(_fox):
		_fox.queue_free()
		_fox = null
	_dragging = false
	_hovering = false
	fox_spawned_changed.emit(false)
	status_changed.emit("Fox hidden")


func celebrate() -> void:
	# A little happy bounce — used when a session starts or completes.
	if is_instance_valid(_fox):
		_resting_on_floor = false
		_fox_velocity.y = -560.0 * _fox_pixel_scale()
		_fox.call("pulse_click")


# --- Activity / behaviour --------------------------------------------------

func set_activity(activity: String) -> void:
	# "idle" (resting), "working" (sleeps while you focus), "break" (plays with a ball).
	_activity = activity
	_apply_activity()


func _apply_activity() -> void:
	if not is_instance_valid(_fox):
		return
	match _activity:
		"working":
			_end_ball_play()
			_fox.call("set_base_state", "sleep")
		"break":
			_fox.call("set_base_state", "idle")
			if _play_state == "none":
				_start_ball_play()
		_:
			_end_ball_play()
			_fox.call("set_base_state", "idle")


func _start_ball_play() -> void:
	# One ball for the whole break; the fox keeps going back to play with it,
	# and the player can grab and throw it at any time.
	_spawn_ball()
	_begin_chase()


func _begin_chase() -> void:
	if not is_instance_valid(_fox):
		return
	_play_state = "trot"
	_fox.call("set_loop_anim", "trot")


func _update_ball_play(delta: float) -> bool:
	# Returns true when it has fully taken over the fox's position this frame
	# (during the scripted pounce arc), so the caller skips gravity.
	match _play_state:
		"trot":
			if not _ball_active:
				_play_state = "none"
				return false
			var dx := _ball_screen_position.x - _fox_screen_position.x
			_fox.call("set_facing", signf(dx))
			_fox_screen_position.x = move_toward(_fox_screen_position.x, _ball_screen_position.x, trot_speed * delta)
			_fox_velocity.x = 0.0
			# Only pounce on a ball that's holding still on the floor.
			if _ball_resting and not _ball_dragging and absf(dx) <= pounce_range and _resting_on_floor:
				_begin_pounce(signf(dx))
			return false
		"pounce":
			_pounce_t += delta / maxf(0.1, pounce_duration)
			var t := clampf(_pounce_t, 0.0, 1.0)
			var arc := -_pounce_peak * 4.0 * t * (1.0 - t)
			_fox_screen_position = Vector2(
				lerpf(_pounce_start.x, _pounce_target.x, t),
				lerpf(_pounce_start.y, _pounce_target.y, t) + arc
			)
			_fox_velocity = Vector2.ZERO
			_resting_on_floor = false
			if t >= 1.0:
				_fox_screen_position = _pounce_target
				_resting_on_floor = true
				_enter_settle()
			return true
		"settle":
			_settle_timer -= delta
			if _settle_timer <= 0.0:
				_begin_gap()
			return false
		"gap":
			_gap_timer -= delta
			# Wait for the ball to settle before chasing it again.
			if _gap_timer <= 0.0 and _ball_active and _ball_resting and not _ball_dragging:
				_begin_chase()
			return false
	return false


func _begin_pounce(direction: float) -> void:
	_play_state = "pounce"
	_resting_on_floor = false
	_fox_velocity = Vector2.ZERO
	_pounce_t = 0.0
	_pounce_start = _fox_screen_position
	_pounce_target = Vector2(_ball_screen_position.x, _floor_center_y())
	_pounce_peak = pounce_height * _fox_pixel_scale()
	_fox.call("set_facing", direction)
	_fox.call("play_pounce", pounce_duration)


func _floor_center_y() -> float:
	var rect := _get_target_screen_rect()
	return float(rect.end.y) - _get_floor_offset() - _fox_visual_half().y + landing_offset * _fox_pixel_scale()


func _enter_settle() -> void:
	_play_state = "settle"
	_settle_timer = randf_range(settle_min, settle_max)
	_fox.call("set_base_state", "idle")
	_kick_ball()


func _kick_ball() -> void:
	# The fox boops the ball as it lands, popping it into a little bounce.
	if not _ball_active or _ball_dragging:
		return
	var dir := signf(_ball_screen_position.x - _fox_screen_position.x)
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	_ball_velocity = Vector2(dir * ball_kick_side, -ball_kick_up)
	_ball_resting = false


func _begin_gap() -> void:
	_play_state = "gap"
	_gap_timer = randf_range(play_gap_min, play_gap_max)


func _end_ball_play() -> void:
	_play_state = "none"
	_despawn_ball()


# --- Ball overlay window ---------------------------------------------------

func handle_ball_input(event: InputEvent) -> void:
	if click_through_enabled or not _ball_active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := Vector2(DisplayServer.mouse_get_position())
		if event.pressed:
			if _ball_local_hits(event.position):
				_start_ball_drag(mouse)
				get_viewport().set_input_as_handled()
		elif _ball_dragging:
			_release_ball_drag()
			get_viewport().set_input_as_handled()


func _ball_local_hits(local_position: Vector2) -> bool:
	return local_position.distance_to(Vector2(_ball_window.size) * 0.5) <= _ball_radius()


func _start_ball_drag(mouse_screen_position: Vector2) -> void:
	_ball_dragging = true
	_ball_resting = false
	_ball_drag_offset = _ball_screen_position - mouse_screen_position
	_ball_velocity = Vector2.ZERO
	if is_instance_valid(_fox):
		_fox.call("pulse_click")


func _release_ball_drag() -> void:
	_ball_dragging = false
	_ball_resting = false
	_ball_velocity = (_mouse_velocity * ball_throw_boost).limit_length(ball_max_throw_speed)


func _update_ball_physics(delta: float, mouse_screen_position: Vector2) -> void:
	if _ball_dragging:
		_ball_screen_position = mouse_screen_position + _ball_drag_offset
		_ball_velocity = _mouse_velocity
		_ball_resting = false
	elif not _ball_resting:
		_ball_velocity.y += ball_gravity * delta
		_ball_screen_position += _ball_velocity * delta
	_apply_ball_bounds(delta)
	_ball_screen_position = _ball_screen_position.round()


func _apply_ball_bounds(delta: float) -> void:
	var rect := _get_target_screen_rect()
	var r := _ball_radius()
	var min_x := float(rect.position.x) + r
	var max_x := float(rect.end.x) - r
	var min_y := float(rect.position.y) + r
	var floor_y := float(rect.end.y) - _get_floor_offset() - r
	var on_floor := false

	if _ball_screen_position.x < min_x:
		_ball_screen_position.x = min_x
		_ball_velocity.x = absf(_ball_velocity.x) * ball_bounce
	elif _ball_screen_position.x > max_x:
		_ball_screen_position.x = max_x
		_ball_velocity.x = -absf(_ball_velocity.x) * ball_bounce

	if _ball_screen_position.y < min_y:
		_ball_screen_position.y = min_y
		_ball_velocity.y = absf(_ball_velocity.y) * ball_bounce
	elif _ball_screen_position.y >= floor_y:
		_ball_screen_position.y = floor_y
		on_floor = true
		if absf(_ball_velocity.y) > ball_rest_threshold:
			_ball_velocity.y = -absf(_ball_velocity.y) * ball_bounce
		else:
			_ball_velocity.y = 0.0
		_ball_velocity.x = move_toward(_ball_velocity.x, 0.0, ball_floor_friction * 100.0 * delta)

	if _ball_dragging:
		_ball_resting = false
	elif on_floor and absf(_ball_velocity.y) <= ball_rest_threshold and absf(_ball_velocity.x) <= ball_rest_threshold:
		_ball_velocity = Vector2.ZERO
		_ball_resting = true
	elif not on_floor:
		_ball_resting = false


func _ball_radius() -> float:
	return _ball_px * 0.5


func _ensure_ball_window() -> void:
	if is_instance_valid(_ball_window):
		return
	var window := Window.new()
	window.name = "FocusFoxBall"
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	window.unresizable = true
	window.gui_embed_subwindows = false
	window.visible = false
	window.window_input.connect(handle_ball_input)
	add_child(window)
	var root := Node2D.new()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window.add_child(root)
	var sprite := Sprite2D.new()
	sprite.texture = BALL_TEXTURE
	root.add_child(sprite)
	_ball_window = window
	_ball_root = root
	_ball_sprite = sprite


func _spawn_ball() -> void:
	_ensure_ball_window()
	_ball_px = BALL_SPRITE_PX * _fox_pixel_scale() * ball_relative_scale
	var win := int(ceil(_ball_px)) + ball_window_padding
	_ball_window.size = Vector2i(win, win)
	_ball_sprite.scale = Vector2.ONE * (_fox_pixel_scale() * ball_relative_scale)
	_ball_sprite.position = Vector2(_ball_window.size) * 0.5

	var rect := _get_target_screen_rect()
	var half := _fox_visual_half()
	var min_x := float(rect.position.x) + half.x
	var max_x := float(rect.end.x) - half.x
	var mid := (min_x + max_x) * 0.5
	var ball_x: float
	if _fox_screen_position.x < mid:
		ball_x = randf_range(mid + (max_x - mid) * 0.2, max_x)
	else:
		ball_x = randf_range(min_x, mid - (mid - min_x) * 0.2)
	_ball_screen_position = Vector2(ball_x, _ball_floor_y(_ball_px))
	_ball_velocity = Vector2.ZERO
	_ball_resting = true
	_ball_dragging = false
	_ball_active = true
	_ball_window.show()
	_apply_ball_passthrough()
	_sync_ball_window()


func _despawn_ball() -> void:
	_ball_active = false
	_ball_dragging = false
	if is_instance_valid(_ball_window):
		_ball_window.hide()


func _apply_ball_passthrough() -> void:
	if not is_instance_valid(_ball_window):
		return
	var id := _ball_window.get_window_id()
	_ball_window.mouse_passthrough = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false, id)
	var polygon := _ball_full_polygon() if click_through_enabled else _ball_circle_polygon()
	_ball_window.mouse_passthrough_polygon = polygon
	DisplayServer.window_set_mouse_passthrough(polygon, id)


func _ball_full_polygon() -> PackedVector2Array:
	var size := Vector2(_ball_window.size)
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])


func _ball_circle_polygon() -> PackedVector2Array:
	var center := Vector2(_ball_window.size) * 0.5
	var radius := _ball_radius()
	var points := PackedVector2Array()
	for index in range(20):
		var angle := TAU * float(index) / 20.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _ball_floor_y(ball_px: float) -> float:
	var rect := _get_target_screen_rect()
	return float(rect.end.y) - _get_floor_offset() - ball_px * 0.5


func _sync_ball_window() -> void:
	if is_instance_valid(_ball_window):
		_ball_window.position = Vector2i((_ball_screen_position - Vector2(_ball_window.size) * 0.5).round())


func reset_fox_position() -> void:
	if not is_instance_valid(_fox):
		return
	var screen_rect := _get_target_screen_rect()
	var visual_half := _fox_visual_half()
	_fox_screen_position = Vector2(screen_rect.position.x + screen_rect.size.x * 0.5, screen_rect.end.y - _get_floor_offset() - visual_half.y + landing_offset * _fox_pixel_scale())
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
	_apply_ball_passthrough()


func _get_full_window_polygon() -> PackedVector2Array:
	var size := Vector2(_get_window_size_for_scale())
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


func _fox_pixel_scale() -> float:
	return maxf(1.0, roundf(fox_scale))


func _fox_visual_half() -> Vector2:
	# Half the rendered sprite footprint, used so the fox rests on the taskbar and
	# stays on-screen based on what you actually see (not the padded window size).
	return _fox_sprite_base * _fox_pixel_scale() * 0.5


func _get_window_size_for_scale() -> Vector2i:
	var pixel_scale := _fox_pixel_scale()
	var footprint := _fox_sprite_base * pixel_scale
	return Vector2i(
		max(fox_window_size.x, int(ceil(footprint.x)) + fox_window_padding.x),
		max(fox_window_size.y, int(ceil(footprint.y)) + fox_window_padding.y)
	)


func _update_window_size_for_scale(_pixel_scale: float) -> void:
	if not is_instance_valid(_overlay_window):
		return
	var new_size := _get_window_size_for_scale()
	if _overlay_window.size != new_size:
		_overlay_window.size = new_size
	# Keep the fox centred in the (possibly resized) window so larger sizes are
	# never clipped against the window edge.
	if is_instance_valid(_fox):
		_fox.position = Vector2(new_size) * 0.5
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
	var visual_half := _fox_visual_half()
	var edge := fox_edge_padding
	var min_x := float(screen_rect.position.x) + visual_half.x + edge
	var max_x := float(screen_rect.end.x) - visual_half.x - edge
	var min_y := float(screen_rect.position.y) + visual_half.y + edge
	var floor_y := float(screen_rect.end.y) - _get_floor_offset() - visual_half.y + landing_offset * _fox_pixel_scale()
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


func _taskbar_thickness() -> float:
	# Tier-1 auto-detect: the gap between the full screen and the usable work area
	# along the bottom edge is the taskbar's thickness (0 if it's top/side/hidden).
	var idx := DisplayServer.window_get_current_screen()
	var full_pos := DisplayServer.screen_get_position(idx)
	var full_size := DisplayServer.screen_get_size(idx)
	var usable := DisplayServer.screen_get_usable_rect(idx)
	return maxf(0.0, float((full_pos.y + full_size.y) - (usable.position.y + usable.size.y)))


func _get_floor_offset() -> float:
	# taskbar_height is now a small "sit depth" nudge (0 = feet on the taskbar).
	if taskbar_snap_enabled:
		return -taskbar_height
	return _taskbar_thickness()


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
	return local_position.distance_to(Vector2(_get_window_size_for_scale()) * 0.5) <= _get_fox_radius()


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
	# Full monitor rect; the taskbar is accounted for in _get_floor_offset() now.
	var idx := DisplayServer.window_get_current_screen()
	return Rect2i(DisplayServer.screen_get_position(idx), DisplayServer.screen_get_size(idx))
