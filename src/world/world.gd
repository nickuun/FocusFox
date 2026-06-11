extends Node2D

const PLANETOID_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")
const SHOOTING_STAR: Texture2D = preload("res://assets/main_menu/stars/shooting/shooting_star.png")

@export_group("Launcher")
@export var launcher_window_size := Vector2i(960, 540)
@export var minimize_launcher_after_spawn := true

@export_group("Moon Window")
@export var moon_window_size := Vector2i(560, 560)
@export var use_usable_screen_area := true
@export var moon_edge_padding := 18.0

@export_group("Moon Feel")
@export var moon_weight := 1.15
@export var throw_boost := 0.72
@export var max_throw_speed := 1850.0
@export var damping_at_weight_one := 1.08
@export var edge_bounce := 0.78
@export var moon_collision_bounce := 0.94
@export var hover_modulate := Color(1.18, 1.14, 1.28, 1.0)

@onready var _menu_root: Node2D = $MenuLayer/MainMenu
@onready var _menu_moon: RigidBody2D = $MenuLayer/MainMenu/MenuMoon
@onready var _clouds_root: Node2D = $MenuLayer/MainMenu/Clouds
@onready var _stars_root: Node2D = $MenuLayer/MainMenu/Stars
@onready var _start_button: TextureButton = $MenuLayer/MainMenu/Buttons/StartButton
@onready var _customize_button: TextureButton = $MenuLayer/MainMenu/Buttons/CustomizeButton
@onready var _settings_button: TextureButton = $MenuLayer/MainMenu/Buttons/SettingsButton
@onready var _about_button: TextureButton = $MenuLayer/MainMenu/Buttons/AboutButton
@onready var _quit_button: TextureButton = $MenuLayer/MainMenu/Buttons/QuitButton
@onready var _status_label: Label = $MenuLayer/MainMenu/StatusLabel
@onready var _settings_panel: Panel = $MenuLayer/MainMenu/SettingsPanel
@onready var _settings_close_button: Button = $MenuLayer/MainMenu/SettingsPanel/CloseButton
@onready var _click_through_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/ClickThroughToggle
@onready var _eye_follow_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/EyeFollowToggle
@onready var _hover_fade_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/HoverFadeToggle
@onready var _moon_collision_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/MoonCollisionToggle
@onready var _scale_slider: HSlider = $MenuLayer/MainMenu/SettingsPanel/ScaleSlider
@onready var _opacity_slider: HSlider = $MenuLayer/MainMenu/SettingsPanel/OpacitySlider
@onready var _volume_slider: HSlider = $MenuLayer/MainMenu/SettingsPanel/VolumeSlider
@onready var _mute_toggle: CheckButton = $MenuLayer/MainMenu/SettingsPanel/MuteToggle
@onready var _reset_position_button: Button = $MenuLayer/MainMenu/SettingsPanel/ResetPositionButton
@onready var _add_moon_button: Button = $MenuLayer/MainMenu/SettingsPanel/AddMoonButton
@onready var _previous_moon_button: Button = $MenuLayer/MainMenu/SettingsPanel/PreviousMoonButton
@onready var _next_moon_button: Button = $MenuLayer/MainMenu/SettingsPanel/NextMoonButton
@onready var _remove_moon_button: Button = $MenuLayer/MainMenu/SettingsPanel/RemoveMoonButton
@onready var _clear_moons_button: Button = $MenuLayer/MainMenu/SettingsPanel/ClearMoonsButton
@onready var _selected_moon_label: Label = $MenuLayer/MainMenu/SettingsPanel/SelectedMoonLabel
@onready var _customize_panel: Panel = $MenuLayer/MainMenu/CustomizePanel
@onready var _customize_close_button: Button = $MenuLayer/MainMenu/CustomizePanel/CloseButton
@onready var _moon_body_button: Button = $MenuLayer/MainMenu/CustomizePanel/MoonBodyButton
@onready var _earth_body_button: Button = $MenuLayer/MainMenu/CustomizePanel/EarthBodyButton
@onready var _fox_body_button: Button = $MenuLayer/MainMenu/CustomizePanel/FoxBodyButton
@onready var _body_speed_slider: HSlider = $MenuLayer/MainMenu/CustomizePanel/BodySpeedSlider
@onready var _no_orbits_button: Button = $MenuLayer/MainMenu/CustomizePanel/NoOrbitsButton
@onready var _pebbles_orbit_button: Button = $MenuLayer/MainMenu/CustomizePanel/PebblesOrbitButton
@onready var _meteors_orbit_button: Button = $MenuLayer/MainMenu/CustomizePanel/MeteorsOrbitButton
@onready var _halo_orbit_button: Button = $MenuLayer/MainMenu/CustomizePanel/HaloOrbitButton
@onready var _gold_stars_button: Button = $MenuLayer/MainMenu/CustomizePanel/GoldStarsButton
@onready var _purple_stars_button: Button = $MenuLayer/MainMenu/CustomizePanel/PurpleStarsButton
@onready var _no_stars_button: Button = $MenuLayer/MainMenu/CustomizePanel/NoStarsButton
@onready var _clouds_button: Button = $MenuLayer/MainMenu/CustomizePanel/CloudsButton
@onready var _no_clouds_button: Button = $MenuLayer/MainMenu/CustomizePanel/NoCloudsButton

var _overlay_window: Window
var _overlay_root: Node2D
var _moon: RigidBody2D
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
var _moon_scale := 1.0
var _moon_opacity := 1.0
var _click_through_enabled := false
var _eye_follow_enabled := true
var _hover_fade_enabled := false
var _muted := false
var _volume := 0.8
var _body_theme := "moon"
var _body_speed_multiplier := 1.0
var _orbit_preset := "none"
var _star_preset := "none"
var _cloud_preset := "none"
var _moon_collisions_enabled := true
var _moon_entries: Array[Dictionary] = []
var _selected_moon_index := -1
var _syncing_selected_ui := false


func _ready() -> void:
	randomize()
	_setup_launcher_window()
	_setup_menu_nodes()
	_last_mouse_screen_position = Vector2(DisplayServer.mouse_get_position())


func _process(delta: float) -> void:
	_update_menu_ambient(delta)
	if is_instance_valid(_menu_moon) and not _is_starting:
		var mouse_position := get_global_mouse_position()
		if _menu_moon.has_method("look_at_screen_position"):
			_menu_moon.call("look_at_screen_position", mouse_position, _menu_moon.global_position)


func _physics_process(delta: float) -> void:
	if _moon_entries.is_empty():
		return

	var mouse_screen_position := Vector2(DisplayServer.mouse_get_position())
	_mouse_velocity = (mouse_screen_position - _last_mouse_screen_position) / maxf(delta, 0.001)
	_last_mouse_screen_position = mouse_screen_position

	for index in range(_moon_entries.size()):
		var entry := _moon_entries[index]
		if not _entry_is_valid(entry):
			continue
		_load_entry_state(entry)

		if _dragging:
			_moon_screen_position = (mouse_screen_position + _drag_screen_offset).round()
			_moon_velocity = _mouse_velocity
		else:
			_apply_drift(delta)
			_update_hover(mouse_screen_position)

		_apply_screen_bounds()
		_update_moon_face(mouse_screen_position)
		_sync_overlay_window()
		_store_entry_state(entry)

	_apply_moon_collisions()

	if _selected_moon_index >= 0 and _selected_moon_index < _moon_entries.size():
		_load_entry_state(_moon_entries[_selected_moon_index])


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
	_moon_body_button.pressed.connect(_set_body_theme.bind("moon"))
	_earth_body_button.pressed.connect(_set_body_theme.bind("earth"))
	_fox_body_button.pressed.connect(_set_body_theme.bind("fox"))
	_body_speed_slider.value_changed.connect(_on_body_speed_changed)
	_no_orbits_button.pressed.connect(_set_orbit_preset.bind("none"))
	_pebbles_orbit_button.pressed.connect(_set_orbit_preset.bind("pebbles"))
	_meteors_orbit_button.pressed.connect(_set_orbit_preset.bind("meteors"))
	_halo_orbit_button.pressed.connect(_set_orbit_preset.bind("halo"))
	_no_stars_button.pressed.connect(_set_star_preset.bind("none"))
	_gold_stars_button.pressed.connect(_set_star_preset.bind("gold"))
	_purple_stars_button.pressed.connect(_set_star_preset.bind("purple"))
	_no_clouds_button.pressed.connect(_set_cloud_preset.bind("none"))
	_clouds_button.pressed.connect(_set_cloud_preset.bind("wisps"))
	_click_through_toggle.toggled.connect(_on_click_through_toggled)
	_eye_follow_toggle.toggled.connect(_on_eye_follow_toggled)
	_hover_fade_toggle.toggled.connect(_on_hover_fade_toggled)
	_moon_collision_toggle.toggled.connect(_on_moon_collision_toggled)
	_scale_slider.value_changed.connect(_on_scale_changed)
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_mute_toggle.toggled.connect(_on_mute_toggled)
	_reset_position_button.pressed.connect(_reset_moon_position)
	_add_moon_button.pressed.connect(_add_moon_from_settings)
	_previous_moon_button.pressed.connect(_select_previous_moon)
	_next_moon_button.pressed.connect(_select_next_moon)
	_remove_moon_button.pressed.connect(_remove_selected_moon)
	_clear_moons_button.pressed.connect(_clear_all_moons)

	_menu_moon.freeze = true
	if _menu_moon.has_method("set_highlight"):
		_menu_moon.call("set_highlight", false, hover_modulate)
	_apply_moon_settings(_menu_moon)
	_apply_moon_cosmetics(_menu_moon)

	for child in _clouds_root.get_children():
		var cloud := child as Sprite2D
		if cloud == null:
			continue
		_clouds.append({
			"sprite": cloud,
			"speed": float(cloud.get_meta("speed", 0.0)),
			"start_y": cloud.position.y,
			"wave": randf_range(0.6, 1.4),
			"phase": randf() * TAU,
		})

	for child in _stars_root.get_children():
		var star := child as Sprite2D
		if star != null:
			_twinkle_star(star, randf_range(0.7, 2.2), randf_range(0.25, 0.8))

	_setup_shooting_stars()


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


func _twinkle_star(sprite: Sprite2D, duration: float, low_alpha: float) -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(sprite, "modulate:a", low_alpha, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "modulate:a", 1.0, duration * randf_range(0.75, 1.25)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(randf_range(0.05, 0.5))


func _setup_shooting_stars() -> void:
	_shooting_star_timer = Timer.new()
	_shooting_star_timer.one_shot = true
	_shooting_star_timer.timeout.connect(_spawn_shooting_star)
	add_child(_shooting_star_timer)
	_queue_next_shooting_star()


func _queue_next_shooting_star() -> void:
	if _shooting_star_timer != null:
		_shooting_star_timer.start(randf_range(3.0, 7.0))


func _spawn_shooting_star() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = SHOOTING_STAR
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(randf_range(620, 880), randf_range(65, 160))
	sprite.scale = Vector2.ONE * randf_range(0.45, 0.68)
	sprite.modulate = Color(1, 1, 1, 0.0)
	sprite.z_index = 32
	_menu_root.add_child(sprite)

	var end_position := sprite.position + Vector2(-150, 105)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "position", end_position, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.16)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.38).set_delay(0.32)
	tween.set_parallel(false)
	tween.tween_callback(sprite.queue_free)
	_queue_next_shooting_star()


func _on_start_pressed() -> void:
	if _is_starting:
		return
	_is_starting = true
	_start_button.disabled = true
	_status_label.text = "Moon launching..."

	if _menu_moon.has_method("pulse_click"):
		_menu_moon.call("pulse_click")

	await get_tree().create_timer(0.14).timeout
	var spawn_position := _get_menu_moon_screen_position()

	var entry := _create_moon_entry(spawn_position)
	_set_selected_moon_index(_moon_entries.find(entry))
	_overlay_window.show()
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_click_through_mode_to_entry(entry)

	_load_entry_state(entry)
	_sync_overlay_window()
	_store_entry_state(entry)
	_menu_moon.visible = false
	if _moon.has_method("pulse_click"):
		_moon.call("pulse_click")

	if minimize_launcher_after_spawn:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_settings_pressed() -> void:
	_customize_panel.visible = false
	_settings_panel.visible = true
	_status_label.text = "Tune your moon."


func _on_customize_pressed() -> void:
	_settings_panel.visible = false
	_customize_panel.visible = true
	_status_label.text = "Moon wardrobe soon."


func _on_about_pressed() -> void:
	_status_label.text = "A tiny moon that keeps you company."


func _hide_settings_panel() -> void:
	_settings_panel.visible = false
	_status_label.text = "Click the moon to boop it!"


func _hide_customize_panel() -> void:
	_customize_panel.visible = false
	_status_label.text = "Click the moon to boop it!"


func _on_click_through_toggled(enabled: bool) -> void:
	_click_through_enabled = enabled
	if enabled and _dragging:
		_release_drag()
	_apply_click_through_mode()
	_status_label.text = "Click-through on" if enabled else "Click-through off"


func _on_eye_follow_toggled(enabled: bool) -> void:
	_eye_follow_enabled = enabled
	_apply_moon_settings(_menu_moon)
	for entry in _moon_entries:
		if _entry_is_valid(entry):
			_load_entry_state(entry)
			_apply_moon_settings(_moon)
			_store_entry_state(entry)
	_load_selected_moon_state()
	_status_label.text = "Eye follow on" if enabled else "Eye follow off"


func _on_hover_fade_toggled(enabled: bool) -> void:
	_hover_fade_enabled = enabled
	_apply_visual_state_to_all_moons()
	_status_label.text = "Opacity applies on hover" if enabled else "Opacity always applies"


func _on_moon_collision_toggled(enabled: bool) -> void:
	if _syncing_selected_ui:
		return
	_moon_collisions_enabled = enabled
	_store_selected_moon_state()
	_status_label.text = "Planet bumps on" if enabled else "Planet bumps off"


func _on_scale_changed(value: float) -> void:
	if _syncing_selected_ui:
		return
	_moon_scale = value
	if _moon_entries.is_empty():
		_apply_moon_settings(_menu_moon)
	_apply_moon_settings(_moon)
	_store_selected_moon_state()
	_status_label.text = "Scale %.2fx" % value


func _on_opacity_changed(value: float) -> void:
	if _syncing_selected_ui:
		return
	_moon_opacity = value
	_apply_moon_visual_state()
	_store_selected_moon_state()
	_status_label.text = "Opacity %d%%" % roundi(value * 100.0)


func _on_volume_changed(value: float) -> void:
	_volume = value
	_status_label.text = "Volume %d%%" % roundi(value * 100.0)


func _on_mute_toggled(enabled: bool) -> void:
	_muted = enabled
	_status_label.text = "Muted" if enabled else "Sound on"


func _reset_moon_position() -> void:
	if not is_instance_valid(_moon):
		return
	var screen_rect := _get_target_screen_rect()
	_moon_screen_position = Vector2(screen_rect.get_center())
	_moon_velocity = Vector2.ZERO
	_dragging = false
	_sync_overlay_window()
	_store_selected_moon_state()
	_status_label.text = "Moon position reset"


func _apply_moon_settings(moon: RigidBody2D) -> void:
	if not is_instance_valid(moon):
		return
	moon.scale = Vector2.ONE * _moon_scale
	if moon.has_method("set_eye_follow_enabled"):
		moon.call("set_eye_follow_enabled", _eye_follow_enabled)
	_apply_moon_visual_state()


func _apply_moon_cosmetics(moon: RigidBody2D) -> void:
	if not is_instance_valid(moon):
		return
	if moon.has_method("set_body_theme"):
		moon.call("set_body_theme", _body_theme)
	if moon.has_method("set_body_rotation_speed"):
		moon.call("set_body_rotation_speed", _body_speed_multiplier)
	if moon.has_method("set_orbit_preset"):
		moon.call("set_orbit_preset", _orbit_preset)
	if moon.has_method("set_star_preset"):
		moon.call("set_star_preset", _star_preset)
	if moon.has_method("set_cloud_preset"):
		moon.call("set_cloud_preset", _cloud_preset)


func _create_moon_entry(spawn_position: Vector2) -> Dictionary:
	var entry := {
		"window": null,
		"root": null,
		"moon": null,
		"position": spawn_position,
		"velocity": Vector2.ZERO,
		"dragging": false,
		"drag_offset": Vector2.ZERO,
		"hovering": false,
		"scale": _moon_scale,
		"opacity": _moon_opacity,
		"body_theme": _body_theme,
		"body_speed": _body_speed_multiplier,
		"orbit_preset": _orbit_preset,
		"star_preset": _star_preset,
		"cloud_preset": _cloud_preset,
		"collides": _moon_collisions_enabled,
	}
	_create_overlay_window(entry)
	_spawn_moon(entry)
	_moon_entries.append(entry)
	_load_entry_state(entry)
	_sync_overlay_window()
	_store_entry_state(entry)
	_apply_click_through_mode_to_entry(entry)
	return entry


func _entry_is_valid(entry: Dictionary) -> bool:
	return is_instance_valid(entry.get("window")) and is_instance_valid(entry.get("moon"))


func _load_entry_state(entry: Dictionary) -> void:
	_overlay_window = entry["window"] as Window
	_overlay_root = entry["root"] as Node2D
	_moon = entry["moon"] as RigidBody2D
	_moon_screen_position = entry["position"]
	_moon_velocity = entry["velocity"]
	_dragging = bool(entry["dragging"])
	_drag_screen_offset = entry["drag_offset"]
	_hovering = bool(entry["hovering"])
	_moon_scale = float(entry["scale"])
	_moon_opacity = float(entry["opacity"])
	_body_theme = str(entry["body_theme"])
	_body_speed_multiplier = float(entry["body_speed"])
	_orbit_preset = str(entry["orbit_preset"])
	_star_preset = str(entry["star_preset"])
	_cloud_preset = str(entry["cloud_preset"])
	_moon_collisions_enabled = bool(entry.get("collides", true))


func _store_entry_state(entry: Dictionary) -> void:
	entry["position"] = _moon_screen_position
	entry["velocity"] = _moon_velocity
	entry["dragging"] = _dragging
	entry["drag_offset"] = _drag_screen_offset
	entry["hovering"] = _hovering
	entry["scale"] = _moon_scale
	entry["opacity"] = _moon_opacity
	entry["body_theme"] = _body_theme
	entry["body_speed"] = _body_speed_multiplier
	entry["orbit_preset"] = _orbit_preset
	entry["star_preset"] = _star_preset
	entry["cloud_preset"] = _cloud_preset
	entry["collides"] = _moon_collisions_enabled


func _apply_moon_visual_state() -> void:
	var target_alpha := _moon_opacity
	if _hover_fade_enabled:
		target_alpha = _moon_opacity if (_hovering or _dragging) else 1.0
	if is_instance_valid(_moon):
		_moon.modulate.a = target_alpha
	if is_instance_valid(_menu_moon):
		_menu_moon.modulate.a = _moon_opacity


func _apply_click_through_mode() -> void:
	for entry in _moon_entries:
		_apply_click_through_mode_to_entry(entry)


func _apply_click_through_mode_to_entry(entry: Dictionary) -> void:
	var window := entry.get("window") as Window
	if not is_instance_valid(window):
		return
	if _click_through_enabled:
		# Windows clips drawing outside passthrough polygons, so preserve the full visual window.
		window.mouse_passthrough = false
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false, window.get_window_id())
		var full_polygon := _get_full_window_polygon()
		window.mouse_passthrough_polygon = full_polygon
		DisplayServer.window_set_mouse_passthrough(full_polygon, window.get_window_id())
	else:
		window.mouse_passthrough = false
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, false, window.get_window_id())
		var active_polygon := _get_full_window_polygon() if _entry_needs_full_visual_window(entry) else _get_moon_click_polygon(entry)
		window.mouse_passthrough_polygon = active_polygon
		DisplayServer.window_set_mouse_passthrough(active_polygon, window.get_window_id())


func _get_full_window_polygon() -> PackedVector2Array:
	var size := Vector2(moon_window_size)
	return PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		size,
		Vector2(0.0, size.y),
	])


func _get_moon_click_polygon(entry: Dictionary) -> PackedVector2Array:
	var radius := _get_entry_visual_radius(entry)
	var center := Vector2(moon_window_size) * 0.5
	var points := PackedVector2Array()
	var segments := 32
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _entry_needs_full_visual_window(entry: Dictionary) -> bool:
	return str(entry.get("orbit_preset", "none")) != "none" \
		or str(entry.get("star_preset", "none")) != "none" \
		or str(entry.get("cloud_preset", "none")) != "none"


func _create_overlay_window(entry: Dictionary) -> void:
	var window := Window.new()
	window.name = "DesktopMoonOverlay%d" % (_moon_entries.size() + 1)
	window.size = moon_window_size
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	window.unresizable = true
	window.gui_embed_subwindows = false
	window.position = _get_offscreen_overlay_position()
	window.visible = false
	window.close_requested.connect(_remove_entry.bind(entry))
	window.window_input.connect(_on_overlay_window_input.bind(entry))
	add_child(window)

	var root := Node2D.new()
	root.name = "OverlayWorld"
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window.add_child(root)
	entry["window"] = window
	entry["root"] = root


func _get_offscreen_overlay_position() -> Vector2i:
	var screen_rect := _get_target_screen_rect()
	return screen_rect.end + moon_window_size + Vector2i(96, 96)


func _spawn_moon(entry: Dictionary) -> void:
	var moon := PLANETOID_SCENE.instantiate() as RigidBody2D
	var root := entry["root"] as Node2D
	root.add_child(moon)
	moon.position = Vector2(moon_window_size) * 0.5
	moon.mass = moon_weight
	moon.freeze = true
	moon.linear_velocity = Vector2.ZERO
	moon.angular_velocity = 0.0
	entry["moon"] = moon
	_load_entry_state(entry)
	if moon.has_method("set_highlight"):
		moon.call("set_highlight", false, hover_modulate)
	_apply_moon_settings(moon)
	_apply_moon_cosmetics(moon)
	_store_entry_state(entry)


func _set_body_theme(theme: String) -> void:
	_body_theme = theme
	if _moon_entries.is_empty():
		_apply_moon_cosmetics(_menu_moon)
	_apply_moon_cosmetics(_moon)
	_store_selected_moon_state()
	match theme:
		"earth":
			_status_label.text = "Earth mode"
		"fox":
			_status_label.text = "Fox mode"
		_:
			_status_label.text = "Moon mode"


func _on_body_speed_changed(value: float) -> void:
	if _syncing_selected_ui:
		return
	_body_speed_multiplier = value
	if _moon_entries.is_empty():
		_apply_moon_cosmetics(_menu_moon)
	_apply_moon_cosmetics(_moon)
	_store_selected_moon_state()
	_status_label.text = "Rotation %.1fx" % value


func _set_orbit_preset(preset: String) -> void:
	_orbit_preset = preset
	if _moon_entries.is_empty():
		_apply_moon_cosmetics(_menu_moon)
	_apply_moon_cosmetics(_moon)
	_store_selected_moon_state()
	match preset:
		"pebbles":
			_status_label.text = "Tiny orbitals equipped"
		"meteors":
			_status_label.text = "Meteor companions equipped"
		"halo":
			_status_label.text = "Busy little orbit equipped"
		_:
			_status_label.text = "Orbitals hidden"


func _set_star_preset(preset: String) -> void:
	_star_preset = preset
	if _moon_entries.is_empty():
		_apply_moon_cosmetics(_menu_moon)
	_apply_moon_cosmetics(_moon)
	_store_selected_moon_state()
	match preset:
		"gold":
			_status_label.text = "Gold star field equipped"
		"purple":
			_status_label.text = "Purple star field equipped"
		_:
			_status_label.text = "Stars hidden"


func _set_cloud_preset(preset: String) -> void:
	_cloud_preset = preset
	if _moon_entries.is_empty():
		_apply_moon_cosmetics(_menu_moon)
	_apply_moon_cosmetics(_moon)
	_store_selected_moon_state()
	_status_label.text = "Cloud wisps equipped" if preset == "wisps" else "Clouds hidden"


func _add_moon_from_settings() -> void:
	var screen_rect := _get_target_screen_rect()
	var offset := Vector2(42.0, -34.0) * float(_moon_entries.size() % 5)
	var entry := _create_moon_entry(Vector2(screen_rect.get_center()) + offset)
	var index := _moon_entries.find(entry)
	_set_selected_moon_index(index)
	_menu_moon.visible = false
	_start_button.disabled = true
	var window := entry["window"] as Window
	if is_instance_valid(window):
		window.show()
	_status_label.text = "Added moon %d" % (index + 1)


func _select_previous_moon() -> void:
	if _moon_entries.is_empty():
		return
	_set_selected_moon_index(posmod(_selected_moon_index - 1, _moon_entries.size()))


func _select_next_moon() -> void:
	if _moon_entries.is_empty():
		return
	_set_selected_moon_index(posmod(_selected_moon_index + 1, _moon_entries.size()))


func _remove_selected_moon() -> void:
	if _selected_moon_index < 0 or _selected_moon_index >= _moon_entries.size():
		return
	_remove_entry(_moon_entries[_selected_moon_index])


func _clear_all_moons() -> void:
	for entry in _moon_entries.duplicate():
		_remove_entry(entry)
	_status_label.text = "All moons cleared"


func _remove_entry(entry: Dictionary) -> void:
	var index := _moon_entries.find(entry)
	if index == -1:
		return
	var window := entry.get("window") as Window
	if is_instance_valid(window):
		window.queue_free()
	_moon_entries.remove_at(index)
	if _moon_entries.is_empty():
		_selected_moon_index = -1
		_overlay_window = null
		_overlay_root = null
		_moon = null
		_menu_moon.visible = true
		_start_button.disabled = false
		_refresh_selected_moon_ui()
		return
	_set_selected_moon_index(clampi(index, 0, _moon_entries.size() - 1))


func _set_selected_moon_index(index: int) -> void:
	if _moon_entries.is_empty():
		_selected_moon_index = -1
		_refresh_selected_moon_ui()
		return
	_selected_moon_index = clampi(index, 0, _moon_entries.size() - 1)
	_load_entry_state(_moon_entries[_selected_moon_index])
	_refresh_selected_moon_ui()
	_status_label.text = "Selected moon %d of %d" % [_selected_moon_index + 1, _moon_entries.size()]


func _load_selected_moon_state() -> void:
	if _selected_moon_index >= 0 and _selected_moon_index < _moon_entries.size():
		_load_entry_state(_moon_entries[_selected_moon_index])


func _store_selected_moon_state() -> void:
	if _selected_moon_index >= 0 and _selected_moon_index < _moon_entries.size():
		_store_entry_state(_moon_entries[_selected_moon_index])


func _refresh_selected_moon_ui() -> void:
	_syncing_selected_ui = true
	_selected_moon_label.text = "Selected: none" if _moon_entries.is_empty() else "Selected: %d / %d" % [_selected_moon_index + 1, _moon_entries.size()]
	_scale_slider.value = _moon_scale
	_opacity_slider.value = _moon_opacity
	_body_speed_slider.value = _body_speed_multiplier
	_moon_collision_toggle.button_pressed = _moon_collisions_enabled
	_syncing_selected_ui = false


func _apply_visual_state_to_all_moons() -> void:
	for entry in _moon_entries:
		if _entry_is_valid(entry):
			_load_entry_state(entry)
			_apply_moon_visual_state()
			_store_entry_state(entry)
	_load_selected_moon_state()


func _apply_moon_collisions() -> void:
	if _moon_entries.size() < 2:
		return

	for a_index in range(_moon_entries.size() - 1):
		var a := _moon_entries[a_index]
		if not _entry_can_collide(a):
			continue
		for b_index in range(a_index + 1, _moon_entries.size()):
			var b := _moon_entries[b_index]
			if not _entry_can_collide(b):
				continue
			_resolve_moon_collision(a, b)


func _entry_can_collide(entry: Dictionary) -> bool:
	return _entry_is_valid(entry) and bool(entry.get("collides", true))


func _resolve_moon_collision(a: Dictionary, b: Dictionary) -> void:
	var position_a: Vector2 = a["position"]
	var position_b: Vector2 = b["position"]
	var delta := position_b - position_a
	var distance := delta.length()
	var radius_a := _get_entry_pick_radius(a)
	var radius_b := _get_entry_pick_radius(b)
	var minimum_distance := radius_a + radius_b
	if distance >= minimum_distance:
		return

	var normal := Vector2.RIGHT if distance <= 0.001 else delta / distance
	var penetration := minimum_distance - distance
	var a_dragging := bool(a["dragging"])
	var b_dragging := bool(b["dragging"])

	if a_dragging and not b_dragging:
		position_b += normal * penetration
	elif b_dragging and not a_dragging:
		position_a -= normal * penetration
	else:
		position_a -= normal * (penetration * 0.5)
		position_b += normal * (penetration * 0.5)

	var velocity_a: Vector2 = a["velocity"]
	var velocity_b: Vector2 = b["velocity"]
	var normal_speed := (velocity_a - velocity_b).dot(normal)
	var impact_speed := absf(normal_speed)
	if normal_speed > 0.0:
		var impulse := normal * normal_speed * moon_collision_bounce
		if a_dragging and not b_dragging:
			velocity_b += impulse
		elif b_dragging and not a_dragging:
			velocity_a -= impulse
		else:
			velocity_a -= impulse
			velocity_b += impulse

	a["position"] = position_a
	b["position"] = position_b
	a["velocity"] = velocity_a.limit_length(max_throw_speed)
	b["velocity"] = velocity_b.limit_length(max_throw_speed)
	_sync_entry_window(a)
	_sync_entry_window(b)
	if impact_speed > 80.0:
		_react_to_entry_collision(a)
		_react_to_entry_collision(b)


func _get_entry_pick_radius(entry: Dictionary) -> float:
	return _get_entry_visual_radius(entry) + moon_edge_padding


func _get_entry_visual_radius(entry: Dictionary) -> float:
	var moon := entry.get("moon") as RigidBody2D
	if is_instance_valid(moon) and moon.has_method("get_pick_radius"):
		var radius: Variant = moon.call("get_pick_radius")
		if typeof(radius) == TYPE_FLOAT or typeof(radius) == TYPE_INT:
			return float(radius)
	return 120.0


func _sync_entry_window(entry: Dictionary) -> void:
	var window := entry.get("window") as Window
	if is_instance_valid(window):
		var position: Vector2 = entry["position"]
		window.position = Vector2i((position - Vector2(moon_window_size) * 0.5).round())


func _react_to_entry_collision(entry: Dictionary) -> void:
	var moon := entry.get("moon") as RigidBody2D
	if not is_instance_valid(moon):
		return
	if moon.has_method("react_bumped"):
		moon.call("react_bumped")
	if moon.has_method("pulse_click"):
		moon.call("pulse_click")


func _on_overlay_window_input(event: InputEvent, entry: Dictionary) -> void:
	if _click_through_enabled:
		return
	var index := _moon_entries.find(entry)
	if index != -1 and index != _selected_moon_index:
		_set_selected_moon_index(index)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_screen_position := Vector2(DisplayServer.mouse_get_position())
		if event.pressed:
			if _local_position_hits_moon(event.position):
				_start_drag(mouse_screen_position)
				_store_entry_state(entry)
				get_viewport().set_input_as_handled()
		elif _dragging:
			_release_drag()
			_store_entry_state(entry)
			get_viewport().set_input_as_handled()


func _start_drag(mouse_screen_position: Vector2) -> void:
	_dragging = true
	_drag_screen_offset = _moon_screen_position - mouse_screen_position
	_moon_velocity = Vector2.ZERO
	_set_moon_highlight(true)
	_apply_moon_visual_state()
	if is_instance_valid(_moon) and _moon.has_method("pulse_click"):
		_moon.call("pulse_click")
	if is_instance_valid(_moon) and _moon.has_method("react_clicked"):
		_moon.call("react_clicked")


func _release_drag() -> void:
	_dragging = false
	_moon_velocity = (_mouse_velocity * throw_boost).limit_length(max_throw_speed)
	_set_moon_highlight(false)
	_apply_moon_visual_state()


func _apply_drift(delta: float) -> void:
	_moon_screen_position += _moon_velocity * delta
	var damping := damping_at_weight_one / maxf(0.08, moon_weight)
	_moon_velocity = _moon_velocity.move_toward(Vector2.ZERO, damping * 1000.0 * delta)


func _apply_screen_bounds() -> void:
	var screen_rect := _get_target_screen_rect()
	var window_half_size := Vector2(moon_window_size) * 0.5
	var radius := _get_moon_radius() + moon_edge_padding
	var bounds_padding := Vector2(maxf(window_half_size.x, radius), maxf(window_half_size.y, radius))
	var min_position := Vector2(screen_rect.position) + bounds_padding
	var max_position := Vector2(screen_rect.end) - bounds_padding
	var bounced := false

	if _moon_screen_position.x < min_position.x:
		_moon_screen_position.x = min_position.x
		_moon_velocity.x = absf(_moon_velocity.x) * edge_bounce
		bounced = true
	elif _moon_screen_position.x > max_position.x:
		_moon_screen_position.x = max_position.x
		_moon_velocity.x = -absf(_moon_velocity.x) * edge_bounce
		bounced = true

	if _moon_screen_position.y < min_position.y:
		_moon_screen_position.y = min_position.y
		_moon_velocity.y = absf(_moon_velocity.y) * edge_bounce
		bounced = true
	elif _moon_screen_position.y > max_position.y:
		_moon_screen_position.y = max_position.y
		_moon_velocity.y = -absf(_moon_velocity.y) * edge_bounce
		bounced = true

	if bounced and is_instance_valid(_moon) and _moon.has_method("react_bumped"):
		_moon.call("react_bumped")
	if bounced and is_instance_valid(_moon) and _moon.has_method("pulse_click"):
		_moon.call("pulse_click")


func _sync_overlay_window() -> void:
	if is_instance_valid(_overlay_window):
		_overlay_window.position = Vector2i((_moon_screen_position - Vector2(moon_window_size) * 0.5).round())


func _update_hover(mouse_screen_position: Vector2) -> void:
	var local_mouse := mouse_screen_position - Vector2(_overlay_window.position)
	var hovering := _local_position_hits_moon(local_mouse)
	if hovering == _hovering:
		return
	_hovering = hovering
	_set_moon_highlight(_hovering)
	_apply_moon_visual_state()


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
