extends Node2D

const PLANETOID_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")
const MENU_BACKGROUND: Texture2D = preload("res://assets/main_menu/background.png")
const MENU_TITLE: Texture2D = preload("res://assets/main_menu/title.png")
const BUTTON_DEFAULT: Texture2D = preload("res://assets/main_menu/default_button.png")
const BUTTON_HOVERED: Texture2D = preload("res://assets/main_menu/hovered_button.png")
const ICON_START: Texture2D = preload("res://assets/main_menu/icons/start.png")
const ICON_SETTINGS: Texture2D = preload("res://assets/main_menu/icons/settings.png")
const ICON_ABOUT: Texture2D = preload("res://assets/main_menu/icons/about.png")
const ICON_QUIT: Texture2D = preload("res://assets/main_menu/icons/quit.png")
const CLOUD_LARGE: Texture2D = preload("res://assets/main_menu/clouds/large_clouds.png")
const CLOUD_MEDIUM: Texture2D = preload("res://assets/main_menu/clouds/medium_clouds.png")
const CLOUD_SMALL: Texture2D = preload("res://assets/main_menu/clouds/small_clouds.png")
const CLOUD_SMALL_2: Texture2D = preload("res://assets/main_menu/clouds/small_clouds_2.png")
const STAR_GOLD_LARGE: Texture2D = preload("res://assets/main_menu/stars/gold/large_star.png")
const STAR_GOLD_MEDIUM: Texture2D = preload("res://assets/main_menu/stars/gold/medium_star.png")
const STAR_GOLD_SMALL: Texture2D = preload("res://assets/main_menu/stars/gold/small_star.png")
const STAR_PURPLE_LARGE: Texture2D = preload("res://assets/main_menu/stars/purple/large_star.png")
const STAR_PURPLE_MEDIUM: Texture2D = preload("res://assets/main_menu/stars/purple/medium_star.png")
const STAR_PURPLE_SMALL: Texture2D = preload("res://assets/main_menu/stars/purple/small_star.png")
const SHOOTING_STAR: Texture2D = preload("res://assets/main_menu/stars/shooting/shooting_star.png")
const FONT_REGULAR: FontFile = preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")
const FONT_BOLD: FontFile = preload("res://assets/not_sprites/pixel_operator/PixelOperator-Bold.ttf")

@export_group("Launcher")
@export var launcher_window_size := Vector2i(960, 540)
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

@onready var _menu_root: Node2D = $MenuLayer/MainMenu

var _overlay_window: Window
var _overlay_root: Node2D
var _moon: RigidBody2D
var _menu_moon: RigidBody2D
var _start_button: TextureButton
var _status_label: Label
var _shooting_star_timer: Timer
var _clouds: Array[Dictionary] = []
var _moon_screen_position := Vector2.ZERO
var _moon_velocity := Vector2.ZERO
var _last_mouse_screen_position := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO
var _dragging := false
var _drag_screen_offset := Vector2.ZERO
var _hovering := false
var _is_starting := false


func _ready() -> void:
	randomize()
	_setup_launcher_window()
	_build_main_menu()
	_last_mouse_screen_position = Vector2(DisplayServer.mouse_get_position())


func _process(delta: float) -> void:
	_update_menu_ambient(delta)

	if is_instance_valid(_menu_moon) and not _is_starting:
		var mouse_position := get_global_mouse_position()
		if _menu_moon.has_method("look_at_screen_position"):
			_menu_moon.call("look_at_screen_position", mouse_position, _menu_moon.global_position)


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
	_update_moon_face(mouse_screen_position)
	_sync_overlay_window()


func _unhandled_input(event: InputEvent) -> void:
	if _is_starting or not is_instance_valid(_menu_moon):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _menu_moon.global_position.distance_to(get_global_mouse_position()) <= _get_menu_moon_radius():
			if _menu_moon.has_method("pulse_click"):
				_menu_moon.call("pulse_click")


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


func _build_main_menu() -> void:
	_add_sprite(_menu_root, MENU_BACKGROUND, Vector2(480, 270), 0)
	_add_cloud(CLOUD_LARGE, Vector2(50, 320), 0.95, 8.0, 7)
	_add_cloud(CLOUD_MEDIUM, Vector2(725, 265), 0.75, -5.0, 8)
	_add_cloud(CLOUD_SMALL, Vector2(780, 180), 0.72, 4.0, 8)
	_add_cloud(CLOUD_SMALL_2, Vector2(145, 365), 0.65, -3.0, 7)
	_add_stars()

	var title := _add_sprite(_menu_root, MENU_TITLE, Vector2(274, 165), 20)
	title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_menu_moon = PLANETOID_SCENE.instantiate() as RigidBody2D
	_menu_root.add_child(_menu_moon)
	_menu_moon.position = Vector2(635, 245)
	_menu_moon.z_index = 28
	_menu_moon.freeze = true
	if _menu_moon.has_method("set_highlight"):
		_menu_moon.call("set_highlight", false, hover_modulate)

	_start_button = _create_menu_button(Vector2(195, 267), "Start", ICON_START, _on_start_pressed, true)
	_create_menu_button(Vector2(195, 333), "Settings", ICON_SETTINGS, _on_settings_pressed, false)
	_create_menu_button(Vector2(195, 399), "About", ICON_ABOUT, _on_about_pressed, false)
	_create_menu_button(Vector2(195, 465), "Quit", ICON_QUIT, Callable(get_tree(), "quit"), false)

	_status_label = Label.new()
	_status_label.position = Vector2(594, 392)
	_status_label.size = Vector2(250, 40)
	_status_label.text = "Click the moon to boop it!"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_override("font", FONT_REGULAR)
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.64, 0.92))
	_status_label.z_index = 35
	_menu_root.add_child(_status_label)

	_add_status_star(Vector2(605, 413))
	_setup_shooting_stars()


func _create_menu_button(position: Vector2, text: String, icon: Texture2D, callback: Callable, selected: bool) -> TextureButton:
	var button := TextureButton.new()
	button.position = position
	button.texture_normal = BUTTON_DEFAULT
	button.texture_hover = BUTTON_HOVERED
	button.texture_pressed = BUTTON_HOVERED
	button.ignore_texture_size = false
	button.focus_mode = Control.FOCUS_NONE
	button.z_index = 40
	_menu_root.add_child(button)
	button.pressed.connect(callback)

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.position = Vector2(20, 10)
	icon_rect.size = Vector2(43, 46)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon_rect)

	var label := Label.new()
	label.position = Vector2(70, 12)
	label.size = Vector2(130, 40)
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT_BOLD if selected else FONT_REGULAR)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.64, 1.0) if selected else Color(0.82, 0.72, 0.93, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button


func _add_stars() -> void:
	var textures: Array[Texture2D] = [
		STAR_GOLD_LARGE, STAR_GOLD_MEDIUM, STAR_GOLD_SMALL,
		STAR_PURPLE_LARGE, STAR_PURPLE_MEDIUM, STAR_PURPLE_SMALL,
	]
	for index in range(46):
		var texture: Texture2D = textures.pick_random()
		var sprite := _add_sprite(_menu_root, texture, Vector2(randf_range(55, 880), randf_range(42, 405)), 12)
		sprite.scale = Vector2.ONE * randf_range(0.35, 0.82)
		sprite.modulate = Color(1, 1, 1, randf_range(0.35, 0.9))
		_twinkle_star(sprite, randf_range(0.6, 2.4), randf_range(0.22, 0.95))


func _add_status_star(position: Vector2) -> void:
	var sprite := _add_sprite(_menu_root, STAR_GOLD_LARGE, position, 36)
	sprite.scale = Vector2(0.8, 0.8)
	_twinkle_star(sprite, 0.85, 0.55)


func _twinkle_star(sprite: Sprite2D, duration: float, low_alpha: float) -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(sprite, "modulate:a", low_alpha, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "modulate:a", 1.0, duration * randf_range(0.75, 1.25)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(randf_range(0.05, 0.5))


func _add_cloud(texture: Texture2D, position: Vector2, scale: float, speed: float, z: int) -> void:
	var sprite := _add_sprite(_menu_root, texture, position, z)
	sprite.scale = Vector2.ONE * scale
	sprite.modulate = Color(1, 1, 1, 0.72)
	_clouds.append({
		"sprite": sprite,
		"speed": speed,
		"start_y": position.y,
		"wave": randf_range(0.6, 1.4),
		"phase": randf() * TAU,
	})


func _update_menu_ambient(delta: float) -> void:
	for cloud_data in _clouds:
		var sprite := cloud_data["sprite"] as Sprite2D
		if sprite == null:
			continue
		var speed := float(cloud_data["speed"])
		sprite.position.x += speed * delta
		sprite.position.y = float(cloud_data["start_y"]) + sin(Time.get_ticks_msec() * 0.00035 * float(cloud_data["wave"]) + float(cloud_data["phase"])) * 4.0
		if speed > 0.0 and sprite.position.x > 1040.0:
			sprite.position.x = -90.0
		elif speed < 0.0 and sprite.position.x < -90.0:
			sprite.position.x = 1040.0


func _setup_shooting_stars() -> void:
	_shooting_star_timer = Timer.new()
	_shooting_star_timer.one_shot = true
	_shooting_star_timer.timeout.connect(_spawn_shooting_star)
	add_child(_shooting_star_timer)
	_queue_next_shooting_star()


func _queue_next_shooting_star() -> void:
	if _shooting_star_timer == null:
		return
	_shooting_star_timer.start(randf_range(3.0, 7.0))


func _spawn_shooting_star() -> void:
	var sprite := _add_sprite(_menu_root, SHOOTING_STAR, Vector2(randf_range(620, 880), randf_range(65, 160)), 32)
	sprite.scale = Vector2.ONE * randf_range(0.45, 0.68)
	sprite.modulate = Color(1, 1, 1, 0.0)
	var end_position := sprite.position + Vector2(-150, 105)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "position", end_position, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.16)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.38).set_delay(0.32)
	tween.set_parallel(false)
	tween.tween_callback(sprite.queue_free)
	_queue_next_shooting_star()


func _add_sprite(parent: Node, texture: Texture2D, position: Vector2, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = position
	sprite.z_index = z
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)
	return sprite


func _on_start_pressed() -> void:
	if _is_starting:
		return
	_is_starting = true
	_start_button.disabled = true
	_status_label.text = "Moon launching..."

	if is_instance_valid(_menu_moon) and _menu_moon.has_method("pulse_click"):
		_menu_moon.call("pulse_click")

	await get_tree().create_timer(0.14).timeout
	var spawn_position := _get_menu_moon_screen_position()
	if is_instance_valid(_menu_moon):
		_menu_moon.visible = false

	if not is_instance_valid(_overlay_window):
		_create_overlay_window()
		await _show_overlay_window(spawn_position, true)

	if not is_instance_valid(_moon):
		_spawn_moon()
		_moon_screen_position = spawn_position
		_sync_overlay_window()
		if _moon.has_method("pulse_click"):
			_moon.call("pulse_click")

	if minimize_launcher_after_spawn:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_settings_pressed() -> void:
	if _status_label != null:
		_status_label.text = "Settings soon"


func _on_about_pressed() -> void:
	if _status_label != null:
		_status_label.text = "A tiny moon that keeps you company."


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


func _show_overlay_window(spawn_position: Vector2 = Vector2.ZERO, use_spawn_position := false) -> void:
	var screen_rect := _get_target_screen_rect()
	_moon_screen_position = spawn_position if use_spawn_position else Vector2(screen_rect.get_center())
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
	if is_instance_valid(_moon) and _moon.has_method("pulse_click"):
		_moon.call("pulse_click")


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
	var window_half_size := Vector2(moon_window_size) * 0.5
	var radius := _get_moon_radius() + moon_edge_padding
	var bounds_padding := Vector2(
		maxf(window_half_size.x, radius),
		maxf(window_half_size.y, radius)
	)
	var min_position := Vector2(screen_rect.position) + bounds_padding
	var max_position := Vector2(screen_rect.end) - bounds_padding

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


func _update_moon_face(mouse_screen_position: Vector2) -> void:
	if is_instance_valid(_moon) and _moon.has_method("look_at_screen_position"):
		_moon.call("look_at_screen_position", mouse_screen_position, _moon_screen_position)


func _get_moon_radius() -> float:
	if is_instance_valid(_moon) and _moon.has_method("get_pick_radius"):
		var radius: Variant = _moon.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	return 120.0


func _get_menu_moon_radius() -> float:
	if is_instance_valid(_menu_moon) and _menu_moon.has_method("get_pick_radius"):
		var radius: Variant = _menu_moon.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	return 120.0


func _get_menu_moon_screen_position() -> Vector2:
	if not is_instance_valid(_menu_moon):
		return Vector2(DisplayServer.mouse_get_position())
	var window := get_window()
	var viewport_size := get_viewport_rect().size
	var window_size := Vector2(window.size)
	var scale := Vector2.ONE
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		scale = Vector2(window_size.x / viewport_size.x, window_size.y / viewport_size.y)
	return Vector2(window.position) + _menu_moon.global_position * scale


func _get_target_screen_rect() -> Rect2i:
	var screen_index := DisplayServer.window_get_current_screen()
	if use_usable_screen_area:
		return DisplayServer.screen_get_usable_rect(screen_index)
	return Rect2i(Vector2i.ZERO, DisplayServer.screen_get_size(screen_index))
