extends RigidBody2D

const FACE_DEFAULT: Texture2D = preload("res://assets/faces/mockup/1.png")
const FACE_CONTENT: Texture2D = preload("res://assets/faces/mockup/content.png")
const FACE_EXCITED: Texture2D = preload("res://assets/faces/mockup/excited.png")
const FACE_SURPRISED: Texture2D = preload("res://assets/faces/mockup/surprised.png")
const FACE_WINK: Texture2D = preload("res://assets/faces/mockup/wink.png")
const SMALL_METEOR: Texture2D = preload("res://assets/meteor/small_meteor.png")
const MEDIUM_METEOR: Texture2D = preload("res://assets/meteor/medium_meteor.png")
const GOLD_STAR: Texture2D = preload("res://assets/main_menu/stars/gold/small_star.png")
const PURPLE_STAR: Texture2D = preload("res://assets/main_menu/stars/purple/small_star.png")
const CLOUD_SMALL: Texture2D = preload("res://assets/main_menu/clouds/small_clouds.png")
const CLOUD_SMALL_2: Texture2D = preload("res://assets/main_menu/clouds/small_clouds_2.png")
const FOX_SPRITE_SHEET: Texture2D = preload("res://assets/fox/Fox Sprite Sheet.png")

const BODY_FRAME_DIRS := {
	"moon": "res://assets/orbitals/moon",
	"earth": "res://assets/orbitals/earth",
}
const FOX_SPRITE_SIZE := Vector2i(32, 32)
const FOX_IDLE_FRAME_COUNT := 5
const FOX_IDLE_ROW := 0
const ORBIT_PRESETS := {
	"none": [],
	"pebbles": [
		{"texture": SMALL_METEOR, "radius": Vector2(148.0, 44.0), "speed": 0.82, "scale": 1.8, "phase": 0.3},
		{"texture": SMALL_METEOR, "radius": Vector2(184.0, 58.0), "speed": -0.54, "scale": 1.45, "phase": 2.9},
	],
	"meteors": [
		{"texture": MEDIUM_METEOR, "radius": Vector2(128.0, 34.0), "speed": 0.58, "scale": 1.8, "phase": 0.7},
		{"texture": SMALL_METEOR, "radius": Vector2(168.0, 48.0), "speed": -0.42, "scale": 1.45, "phase": 3.8},
	],
	"halo": [
		{"texture": SMALL_METEOR, "radius": Vector2(142.0, 42.0), "speed": 0.96, "scale": 1.35, "phase": 0.0},
		{"texture": SMALL_METEOR, "radius": Vector2(158.0, 48.0), "speed": 0.82, "scale": 1.15, "phase": 1.0},
		{"texture": MEDIUM_METEOR, "radius": Vector2(176.0, 54.0), "speed": 0.68, "scale": 1.35, "phase": 2.1},
		{"texture": SMALL_METEOR, "radius": Vector2(192.0, 62.0), "speed": -0.46, "scale": 1.05, "phase": 3.1},
		{"texture": SMALL_METEOR, "radius": Vector2(210.0, 68.0), "speed": -0.38, "scale": 0.95, "phase": 4.2},
		{"texture": MEDIUM_METEOR, "radius": Vector2(226.0, 72.0), "speed": 0.32, "scale": 1.05, "phase": 5.2},
	],
}
const STAR_PRESETS := {
	"none": [],
	"gold": [
		{"texture": GOLD_STAR, "position": Vector2(-190.0, -120.0), "scale": 1.4, "phase": 0.1},
		{"texture": GOLD_STAR, "position": Vector2(178.0, -98.0), "scale": 1.1, "phase": 1.4},
		{"texture": GOLD_STAR, "position": Vector2(-150.0, 126.0), "scale": 0.95, "phase": 2.2},
		{"texture": GOLD_STAR, "position": Vector2(214.0, 110.0), "scale": 1.25, "phase": 3.1},
		{"texture": GOLD_STAR, "position": Vector2(32.0, -176.0), "scale": 0.8, "phase": 4.0},
	],
	"purple": [
		{"texture": PURPLE_STAR, "position": Vector2(-196.0, -96.0), "scale": 1.45, "phase": 0.6},
		{"texture": PURPLE_STAR, "position": Vector2(190.0, -132.0), "scale": 1.0, "phase": 1.8},
		{"texture": PURPLE_STAR, "position": Vector2(-216.0, 98.0), "scale": 0.9, "phase": 2.8},
		{"texture": PURPLE_STAR, "position": Vector2(146.0, 142.0), "scale": 1.3, "phase": 3.7},
		{"texture": PURPLE_STAR, "position": Vector2(18.0, -202.0), "scale": 0.75, "phase": 4.6},
	],
}
const CLOUD_PRESETS := {
	"none": [],
	"wisps": [
		{"texture": CLOUD_SMALL, "position": Vector2(-198.0, -32.0), "scale": 0.34, "phase": 0.2, "speed": 7.0},
		{"texture": CLOUD_SMALL_2, "position": Vector2(164.0, 74.0), "scale": 0.32, "phase": 2.4, "speed": -5.0},
	],
}

@export_group("Feel")
@export var weight := 1.15

@export_group("Orbit Bob")
@export var bob_amplitude := 8.0
@export var bob_seconds := 4.8
@export var bob_phase_offset := 0.0

@export_group("Click Pulse")
@export var pulse_squash := Vector2(1.08, 0.92)
@export var pulse_pop := Vector2(0.96, 1.04)
@export var pulse_seconds := 0.22

@export_group("Face")
@export var face_follow_pixels := 9.0
@export var face_follow_deadzone := 4.0
@export var face_follow_max_distance := 180.0
@export var face_follow_smoothing := 14.0
@export var eye_follow_enabled := true

@export_group("Face Reactions")
@export var idle_face_min_seconds := 4.0
@export var idle_face_max_seconds := 8.0
@export var bump_surprise_seconds := 0.42
@export var click_surprise_seconds := 0.14
@export var click_followup_seconds := 0.55

@onready var _visual: Node2D = $MoonSprite
@onready var _face: Sprite2D = $FaceSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _orbitals_root: Node2D = $Orbitals
@onready var _ambient_root: Node2D = $AmbientParticles

var _base_visual_position := Vector2.ZERO
var _base_visual_scale := Vector2.ONE
var _base_face_position := Vector2.ZERO
var _face_look_offset := Vector2.ZERO
var _face_target_offset := Vector2.ZERO
var _bob_offset := Vector2.ZERO
var _bob_time := 0.0
var _base_modulate := Color.WHITE
var _pulse_tween: Tween
var _face_tween: Tween
var _idle_face_seconds := 0.0
var _idle_face_target := 5.0
var _idle_face_uses_content := false
var _body_theme := "moon"
var _body_speed_multiplier := 1.0
var _orbit_preset := "none"
var _orbiters: Array[Dictionary] = []
var _star_preset := "none"
var _cloud_preset := "none"
var _star_particles: Array[Dictionary] = []
var _cloud_particles: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("desktop_moons")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_face.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base_visual_position = _visual.position
	_base_visual_scale = _visual.scale
	_base_face_position = _face.position
	_base_modulate = _visual.modulate
	_bob_time = bob_phase_offset + randf() * TAU
	mass = maxf(0.08, weight)
	gravity_scale = 0.0
	freeze = true
	sleeping = false
	can_sleep = false
	if _visual is AnimatedSprite2D:
		(_visual as AnimatedSprite2D).play("default")
	if _face != null:
		_face.texture = FACE_DEFAULT
	_queue_next_idle_face()


func _physics_process(delta: float) -> void:
	_update_bob(delta)
	_update_idle_face(delta)
	_update_orbiters(delta)
	_update_ambient_particles(delta)


func set_highlight(highlighted: bool, highlight_modulate: Color) -> void:
	if _visual == null:
		return
	_visual.modulate = highlight_modulate if highlighted else _base_modulate


func pulse_click() -> void:
	if _visual == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	_visual.scale = _base_visual_scale
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_visual, "scale", _base_visual_scale * pulse_squash, pulse_seconds * 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_visual, "scale", _base_visual_scale * pulse_pop, pulse_seconds * 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_visual, "scale", _base_visual_scale, pulse_seconds * 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func react_clicked() -> void:
	if _face == null:
		return
	_start_face_reaction()
	_set_face_texture(FACE_SURPRISED)
	_face_tween = create_tween()
	_face_tween.tween_interval(click_surprise_seconds)
	_face_tween.tween_callback(func() -> void:
		_set_face_texture(FACE_WINK if randf() < 0.5 else FACE_EXCITED)
	)
	_face_tween.tween_interval(click_followup_seconds)
	_face_tween.tween_callback(_return_to_idle_face)


func react_bumped() -> void:
	if _face == null:
		return
	_start_face_reaction()
	_set_face_texture(FACE_SURPRISED)
	_face_tween = create_tween()
	_face_tween.tween_interval(bump_surprise_seconds)
	_face_tween.tween_callback(_return_to_idle_face)


func look_at_screen_position(mouse_screen_position: Vector2, moon_screen_position: Vector2) -> void:
	if _face == null:
		return
	if not eye_follow_enabled:
		_face_target_offset = Vector2.ZERO
		return

	var delta := mouse_screen_position - moon_screen_position
	var distance := delta.length()
	if distance <= face_follow_deadzone:
		_face_target_offset = Vector2.ZERO
		return

	var direction := delta / distance
	var distance_range := maxf(1.0, face_follow_max_distance - face_follow_deadzone)
	var follow_amount := clampf((distance - face_follow_deadzone) / distance_range, 0.0, 1.0)
	follow_amount = smoothstep(0.0, 1.0, follow_amount)

	var source_pixel_offset := direction * face_follow_pixels * follow_amount
	_face_target_offset = source_pixel_offset * _base_visual_scale


func set_eye_follow_enabled(enabled: bool) -> void:
	eye_follow_enabled = enabled
	if not eye_follow_enabled:
		_face_target_offset = Vector2.ZERO


func set_body_theme(theme: String) -> void:
	if not (_visual is AnimatedSprite2D):
		return
	var frames := _build_body_sprite_frames(theme)
	if frames == null:
		return
	_body_theme = theme
	var sprite := _visual as AnimatedSprite2D
	sprite.sprite_frames = frames
	sprite.play("default")


func set_body_rotation_speed(multiplier: float) -> void:
	_body_speed_multiplier = clampf(multiplier, 0.15, 3.0)
	if _visual is AnimatedSprite2D:
		var sprite := _visual as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("default"):
			sprite.sprite_frames.set_animation_speed("default", _get_body_base_speed() * _body_speed_multiplier)


func set_orbit_preset(preset: String) -> void:
	if not ORBIT_PRESETS.has(preset) or _orbitals_root == null:
		return
	if _orbit_preset == preset and (preset == "none" or not _orbiters.is_empty()):
		return
	_orbit_preset = preset
	for child in _orbitals_root.get_children():
		child.queue_free()
	_orbiters.clear()

	var preset_data: Array = ORBIT_PRESETS[preset]
	for data: Dictionary in preset_data:
		var sprite := Sprite2D.new()
		sprite.texture = data["texture"]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = true
		sprite.scale = Vector2.ONE * float(data["scale"])
		sprite.z_index = -1
		var color: Color = data.get("color", Color.WHITE)
		sprite.modulate = color
		_orbitals_root.add_child(sprite)
		_orbiters.append({
			"sprite": sprite,
			"radius": data["radius"],
			"speed": float(data["speed"]),
			"phase": float(data["phase"]),
			"color": color,
			"twinkle": float(data.get("twinkle", 0.0)),
			"time": randf() * TAU,
		})
	_update_orbiters(0.0)


func set_star_preset(preset: String) -> void:
	if not STAR_PRESETS.has(preset) or _ambient_root == null:
		return
	if _star_preset == preset and (preset == "none" or not _star_particles.is_empty()):
		return
	_star_preset = preset
	_clear_particles(_star_particles)
	var preset_data: Array = STAR_PRESETS[preset]
	for data: Dictionary in preset_data:
		_star_particles.append(_create_ambient_particle(data, 24, false))
	_update_ambient_particles(0.0)


func set_cloud_preset(preset: String) -> void:
	if not CLOUD_PRESETS.has(preset) or _ambient_root == null:
		return
	if _cloud_preset == preset and (preset == "none" or not _cloud_particles.is_empty()):
		return
	_cloud_preset = preset
	_clear_particles(_cloud_particles)
	var preset_data: Array = CLOUD_PRESETS[preset]
	for data: Dictionary in preset_data:
		_cloud_particles.append(_create_ambient_particle(data, 3, true))
	_update_ambient_particles(0.0)


func get_pick_radius() -> float:
	if _collision_shape != null and _collision_shape.shape is CircleShape2D:
		var scale_max := maxf(absf(global_scale.x), absf(global_scale.y))
		return (_collision_shape.shape as CircleShape2D).radius * scale_max

	if _visual is Sprite2D:
		var sprite := _visual as Sprite2D
		if sprite.texture != null:
			var size := sprite.texture.get_size() * Vector2(absf(sprite.global_scale.x), absf(sprite.global_scale.y))
			return maxf(size.x, size.y) * 0.5

	if _visual is AnimatedSprite2D:
		var sprite := _visual as AnimatedSprite2D
		if sprite.sprite_frames != null:
			var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			if texture != null:
				var size := texture.get_size() * Vector2(absf(sprite.global_scale.x), absf(sprite.global_scale.y))
				return maxf(size.x, size.y) * 0.5

	return 120.0


func _update_bob(delta: float) -> void:
	if _visual == null:
		return
	_bob_time += delta
	var cycle_seconds := maxf(0.1, bob_seconds)
	var bob := sin((_bob_time / cycle_seconds) * TAU) * bob_amplitude
	_bob_offset = Vector2(0.0, bob)
	var smoothing := 1.0 - exp(-face_follow_smoothing * delta)
	_face_look_offset = _face_look_offset.lerp(_face_target_offset, smoothing)
	_visual.position = _base_visual_position + _bob_offset
	_face.position = _base_face_position + _bob_offset + _face_look_offset
	if _orbitals_root != null:
		_orbitals_root.position = _bob_offset


func _update_orbiters(delta: float) -> void:
	for orbiter in _orbiters:
		var sprite := orbiter["sprite"] as Sprite2D
		if sprite == null:
			continue
		orbiter["time"] = float(orbiter["time"]) + delta
		var angle := float(orbiter["phase"]) + float(orbiter["time"]) * TAU * float(orbiter["speed"]) * 0.14
		var radius: Vector2 = orbiter["radius"]
		var y := sin(angle) * radius.y
		sprite.position = Vector2(cos(angle) * radius.x, y)
		sprite.z_index = -1 if y < -radius.y * 0.18 else 2
		var color: Color = orbiter["color"]
		var twinkle := sin(float(orbiter["time"]) * TAU * 0.7 + float(orbiter["phase"])) * float(orbiter["twinkle"])
		color.a = clampf(0.72 + maxf(0.0, y / maxf(1.0, radius.y)) * 0.28 + twinkle, 0.38, 1.0)
		sprite.modulate = color


func _update_ambient_particles(delta: float) -> void:
	_update_particle_group(_star_particles, delta)
	_update_particle_group(_cloud_particles, delta)


func _update_particle_group(particles: Array[Dictionary], delta: float) -> void:
	for particle in particles:
		var sprite := particle["sprite"] as Sprite2D
		if sprite == null:
			continue
		particle["time"] = float(particle["time"]) + delta
		var time := float(particle["time"])
		var phase := float(particle["phase"])
		var base_position: Vector2 = particle["position"]
		var drift := float(particle["drift"])
		var float_y := sin(time * 0.55 + phase) * float(particle["float"])
		sprite.position = base_position + Vector2(sin(time * 0.18 + phase) * drift, float_y)
		var fade := (sin(time * float(particle["fade_speed"]) + phase) + 1.0) * 0.5
		var color: Color = particle["color"]
		color.a = lerpf(float(particle["min_alpha"]), float(particle["max_alpha"]), smoothstep(0.0, 1.0, fade))
		sprite.modulate = color


func _create_ambient_particle(data: Dictionary, z_index: int, is_cloud: bool) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = data["texture"]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	sprite.scale = Vector2.ONE * float(data["scale"])
	sprite.z_index = z_index
	_ambient_root.add_child(sprite)
	return {
		"sprite": sprite,
		"position": data["position"],
		"phase": float(data["phase"]),
		"time": randf() * TAU,
		"drift": float(data.get("speed", 2.0)) if is_cloud else 2.0,
		"float": 5.0 if is_cloud else 2.5,
		"fade_speed": 0.65 if is_cloud else 1.15,
		"min_alpha": 0.08 if is_cloud else 0.0,
		"max_alpha": 0.42 if is_cloud else 1.0,
		"color": Color.WHITE,
	}


func _clear_particles(particles: Array[Dictionary]) -> void:
	for particle in particles:
		var sprite := particle["sprite"] as Sprite2D
		if sprite != null:
			sprite.queue_free()
	particles.clear()


func _update_idle_face(delta: float) -> void:
	if _face == null or (_face_tween != null and _face_tween.is_valid()):
		return
	_idle_face_seconds += delta
	if _idle_face_seconds < _idle_face_target:
		return
	_idle_face_uses_content = not _idle_face_uses_content
	_set_face_texture(FACE_CONTENT if _idle_face_uses_content else FACE_DEFAULT)
	_queue_next_idle_face()


func _start_face_reaction() -> void:
	if _face_tween != null and _face_tween.is_valid():
		_face_tween.kill()
	_face_tween = null
	_idle_face_seconds = 0.0


func _return_to_idle_face() -> void:
	_face_tween = null
	_idle_face_uses_content = randf() < 0.5
	_set_face_texture(FACE_CONTENT if _idle_face_uses_content else FACE_DEFAULT)
	_queue_next_idle_face()


func _queue_next_idle_face() -> void:
	_idle_face_seconds = 0.0
	_idle_face_target = randf_range(idle_face_min_seconds, idle_face_max_seconds)


func _set_face_texture(texture: Texture2D) -> void:
	if _face != null and texture != null:
		_face.texture = texture


func _build_body_sprite_frames(theme: String) -> SpriteFrames:
	if theme == "fox":
		return _build_fox_sprite_frames()
	if not BODY_FRAME_DIRS.has(theme):
		return null
	return _build_sprite_frames_from_directory(str(BODY_FRAME_DIRS[theme]))


func _build_sprite_frames_from_directory(directory: String) -> SpriteFrames:
	var files := DirAccess.get_files_at(directory)
	var image_files: Array[String] = []
	for file in files:
		if file.get_extension().to_lower() == "png":
			image_files.append(file)
	image_files.sort_custom(func(a: String, b: String) -> bool:
		return _file_number(a) < _file_number(b)
	)
	if image_files.is_empty():
		return null

	var frames := _create_default_sprite_frames()
	for file in image_files:
		var texture := load(directory.path_join(file)) as Texture2D
		if texture != null:
			frames.add_frame("default", texture)
	return frames


func _build_fox_sprite_frames() -> SpriteFrames:
	if FOX_SPRITE_SHEET == null:
		return null

	var frames := _create_default_sprite_frames()
	for frame_index in range(FOX_IDLE_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = FOX_SPRITE_SHEET
		atlas.region = Rect2(
			Vector2(frame_index * FOX_SPRITE_SIZE.x, FOX_IDLE_ROW * FOX_SPRITE_SIZE.y),
			Vector2(FOX_SPRITE_SIZE)
		)
		frames.add_frame("default", atlas)
	return frames


func _create_default_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if not frames.has_animation("default"):
		frames.add_animation("default")
	frames.clear("default")
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", _get_body_base_speed() * _body_speed_multiplier)
	return frames


func _file_number(file_name: String) -> int:
	var digits := ""
	for index in range(file_name.length()):
		var character := file_name.substr(index, 1)
		if character >= "0" and character <= "9":
			digits += character
	return int(digits) if not digits.is_empty() else 0


func _get_body_base_speed() -> float:
	match _body_theme:
		"moon":
			return 8.0
		"fox":
			return 10.0
		_:
			return 12.0
