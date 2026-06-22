extends RigidBody2D

const FOX_SPRITE_SHEET: Texture2D = preload("res://assets/fox/Fox Sprite Sheet.png")

const FOX_SPRITE_SIZE := Vector2i(32, 32)
const FOX_IDLE_FRAME_COUNT := 5
const FOX_IDLE_ROW := 0

@export_group("Feel")
@export var weight := 1.15

@export_group("Click Pulse")
@export var pulse_squash := Vector2(1.08, 0.92)
@export var pulse_pop := Vector2(0.96, 1.04)
@export var pulse_seconds := 0.22

@onready var _sprite: AnimatedSprite2D = $FoxSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _base_sprite_position := Vector2.ZERO
var _base_sprite_scale := Vector2.ONE
var _base_modulate := Color.WHITE
var _pulse_tween: Tween
var _body_speed_multiplier := 1.0


func _ready() -> void:
	add_to_group("focus_foxes")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base_sprite_position = _sprite.position
	_base_sprite_scale = _sprite.scale
	_base_modulate = _sprite.modulate
	mass = maxf(0.08, weight)
	gravity_scale = 0.0
	freeze = true
	sleeping = false
	can_sleep = false
	_sprite.sprite_frames = _build_fox_sprite_frames()
	_sprite.play("default")


func _physics_process(_delta: float) -> void:
	_sprite.position = _base_sprite_position


func set_highlight(highlighted: bool, highlight_modulate: Color) -> void:
	_sprite.modulate = highlight_modulate if highlighted else _base_modulate


func pulse_click() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	_sprite.scale = _base_sprite_scale
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_sprite, "scale", _base_sprite_scale * pulse_squash, pulse_seconds * 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_sprite, "scale", _base_sprite_scale * pulse_pop, pulse_seconds * 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_sprite, "scale", _base_sprite_scale, pulse_seconds * 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func react_clicked() -> void:
	pulse_click()


func react_bumped() -> void:
	pulse_click()


func set_body_theme(_theme: String) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("default"):
		_sprite.sprite_frames = _build_fox_sprite_frames()
		_sprite.play("default")
	set_body_rotation_speed(_body_speed_multiplier)


func set_body_rotation_speed(multiplier: float) -> void:
	_body_speed_multiplier = clampf(multiplier, 0.15, 3.0)
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation("default"):
		_sprite.sprite_frames.set_animation_speed("default", 10.0 * _body_speed_multiplier)


func set_eye_follow_enabled(_enabled: bool) -> void:
	pass


func get_sprite_pixel_size() -> Vector2:
	# Rendered size of the sprite frame in pixels, including the sprite's own
	# (intrinsic) scale but NOT the parent body's scale. Callers multiply by the
	# body scale themselves so the overlay window can be sized to fit the fox.
	var base := Vector2(FOX_SPRITE_SIZE)
	if _sprite.sprite_frames != null:
		var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
		if texture != null:
			base = texture.get_size()
	return base * _sprite.scale.abs()


func get_pick_radius() -> float:
	if _collision_shape.shape is CircleShape2D:
		var scale_max := maxf(absf(global_scale.x), absf(global_scale.y))
		return (_collision_shape.shape as CircleShape2D).radius * scale_max

	var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if texture != null:
		var size := texture.get_size() * Vector2(absf(_sprite.global_scale.x), absf(_sprite.global_scale.y))
		return maxf(size.x, size.y) * 0.5

	return 64.0


func _build_fox_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	# SpriteFrames is created with a built-in "default" animation already.
	if not frames.has_animation("default"):
		frames.add_animation("default")
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", 10.0 * _body_speed_multiplier)
	for frame_index in range(FOX_IDLE_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = FOX_SPRITE_SHEET
		atlas.region = Rect2(
			Vector2(frame_index * FOX_SPRITE_SIZE.x, FOX_IDLE_ROW * FOX_SPRITE_SIZE.y),
			Vector2(FOX_SPRITE_SIZE)
		)
		frames.add_frame("default", atlas)
	return frames
