extends RigidBody2D

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

@onready var _visual: Node2D = $MoonSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _base_visual_position := Vector2.ZERO
var _base_visual_scale := Vector2.ONE
var _bob_time := 0.0
var _base_modulate := Color.WHITE
var _pulse_tween: Tween


func _ready() -> void:
	add_to_group("desktop_moons")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base_visual_position = _visual.position
	_base_visual_scale = _visual.scale
	_base_modulate = _visual.modulate
	_bob_time = bob_phase_offset + randf() * TAU
	mass = maxf(0.08, weight)
	gravity_scale = 0.0
	freeze = true
	sleeping = false
	can_sleep = false
	if _visual is AnimatedSprite2D:
		(_visual as AnimatedSprite2D).play("default")


func _physics_process(delta: float) -> void:
	_update_bob(delta)


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
	_visual.position = _base_visual_position + Vector2(0.0, bob)
