extends RigidBody2D

const FOX_SPRITE_SHEET: Texture2D = preload("res://assets/fox/Fox Sprite Sheet.png")

const FOX_SPRITE_SIZE := Vector2i(32, 32)

# Animations on the 14x7 sheet. row = sheet row, frames = column count used.
# (Row 4 "surprise" and row 6 are intentionally not wired up yet.)
const ANIMS := {
	"idle": {"row": 0, "frames": 5, "fps": 6.0, "loop": true},
	"idle_look": {"row": 1, "frames": 14, "fps": 11.0, "loop": false},
	"trot": {"row": 2, "frames": 8, "fps": 12.0, "loop": true},
	"pounce": {"row": 3, "frames": 11, "fps": 14.0, "loop": false},
	"sleep": {"row": 5, "frames": 6, "fps": 4.0, "loop": true},
}

@export_group("Feel")
@export var weight := 1.15
@export var idle_look_min := 5.0
@export var idle_look_max := 13.0

@export_group("Click Pulse")
@export var pulse_squash := Vector2(1.08, 0.92)
@export var pulse_pop := Vector2(0.96, 1.04)
@export var pulse_seconds := 0.22

@onready var _sprite: AnimatedSprite2D = $FoxSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

signal oneshot_finished(anim: String)

var _base_sprite_position := Vector2.ZERO
var _base_sprite_scale := Vector2.ONE
var _base_modulate := Color.WHITE
var _pulse_tween: Tween
var _body_speed_multiplier := 1.0

var _base_state := "idle"  # the resting loop the fox returns to (idle / sleep)
var _transient := ""       # a non-looping anim currently playing (idle_look / pounce)
var _idle_look_timer := 0.0


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
	if not _sprite.animation_finished.is_connected(_on_anim_finished):
		_sprite.animation_finished.connect(_on_anim_finished)
	_play("idle")
	_reset_idle_look_timer()


func _physics_process(_delta: float) -> void:
	_sprite.position = _base_sprite_position


func _process(delta: float) -> void:
	# Ambient charm: while standing idle the fox occasionally glances around.
	if _transient == "" and _sprite.animation == "idle":
		_idle_look_timer -= delta
		if _idle_look_timer <= 0.0:
			play_oneshot("idle_look")
			_reset_idle_look_timer()


# --- Animation state -------------------------------------------------------

func set_base_state(state: String) -> void:
	# The resting loop the fox holds and returns to: "idle" or "sleep".
	if not ANIMS.has(state):
		return
	_base_state = state
	if _transient == "":
		_play(state)
		_reset_idle_look_timer()


func set_loop_anim(state: String) -> void:
	# Switch immediately to a looping anim (e.g. "trot") without changing base.
	if not ANIMS.has(state):
		return
	_transient = ""
	_play(state)


func play_oneshot(state: String) -> void:
	# Play a non-looping anim once, then fall back to the base state.
	if not ANIMS.has(state):
		return
	_transient = state
	_play(state)


func set_facing(direction: float) -> void:
	if absf(direction) > 0.01:
		_sprite.flip_h = direction < 0.0


func _on_anim_finished() -> void:
	if _transient == "":
		return
	var finished := _transient
	_transient = ""
	_play(_base_state)
	_reset_idle_look_timer()
	oneshot_finished.emit(finished)


func _play(anim: String) -> void:
	if _sprite.animation != anim:
		_sprite.animation = anim
	_sprite.play(anim)


func _reset_idle_look_timer() -> void:
	_idle_look_timer = randf_range(idle_look_min, idle_look_max)


# --- Look / feel -----------------------------------------------------------

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
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("idle"):
		_sprite.sprite_frames = _build_fox_sprite_frames()
		_play(_base_state)
	set_body_rotation_speed(_body_speed_multiplier)


func set_body_rotation_speed(multiplier: float) -> void:
	_body_speed_multiplier = clampf(multiplier, 0.15, 3.0)
	if _sprite.sprite_frames == null:
		return
	for anim in ANIMS:
		_sprite.sprite_frames.set_animation_speed(anim, ANIMS[anim]["fps"] * _body_speed_multiplier)


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
	for anim in ANIMS:
		var spec: Dictionary = ANIMS[anim]
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_loop(anim, spec["loop"])
		frames.set_animation_speed(anim, spec["fps"] * _body_speed_multiplier)
		for frame_index in range(spec["frames"]):
			var atlas := AtlasTexture.new()
			atlas.atlas = FOX_SPRITE_SHEET
			atlas.region = Rect2(
				Vector2(frame_index * FOX_SPRITE_SIZE.x, spec["row"] * FOX_SPRITE_SIZE.y),
				Vector2(FOX_SPRITE_SIZE)
			)
			frames.add_frame(anim, atlas)
	# Drop the empty animation SpriteFrames ships with.
	if frames.has_animation("default"):
		frames.remove_animation("default")
	return frames
