extends Sprite2D
class_name ThrowableProp

## Makes a menu prop (the desk plant) draggable and throwable inside the launcher
## window. Uses simple hand-rolled physics so it stays self-contained to the menu
## viewport - no RigidBody / world colliders needed. A child Area2D provides the
## click hit-test; a sibling "PlantShadow" sprite tracks it for a cozy depth cue.

@export var gravity := 2800.0
@export var bounce := 0.42
@export var air_friction := 0.6
@export var floor_friction := 7.0
@export var throw_boost := 1.0
@export var max_throw_speed := 2600.0
@export var rest_velocity_threshold := 22.0
@export var margin := 48.0
@export var shadow_lift_range := 220.0

signal grabbed
signal settled

@onready var _area: Area2D = $Area2D

var _shadow: Sprite2D
var _velocity := Vector2.ZERO
var _dragging := false
var _drag_offset := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO
var _floor_y := 0.0
var _ceil_y := 0.0
var _min_x := 0.0
var _max_x := 0.0
var _shadow_offset := Vector2.ZERO
var _resting := false


func _ready() -> void:
	_shadow = get_parent().get_node_or_null("PlantShadow")
	if _shadow != null:
		_shadow_offset = _shadow.position - position
	_compute_bounds()
	_last_mouse = get_global_mouse_position()
	if _area != null:
		_area.input_event.connect(_on_area_input)


func _compute_bounds() -> void:
	# The prop lives in the launcher viewport (960x540 design space). It rests at
	# its authored position and is free to be flung around the rest of the screen.
	var view := get_viewport_rect().size
	_floor_y = position.y
	_ceil_y = margin
	_min_x = margin
	_max_x = view.x - margin


func _process(delta: float) -> void:
	var mouse := get_global_mouse_position()
	_mouse_velocity = (mouse - _last_mouse) / maxf(delta, 0.001)
	_last_mouse = mouse

	if _dragging:
		position = mouse + _drag_offset
		_clamp_horizontal()
		position.y = minf(position.y, _floor_y)
		_velocity = _mouse_velocity
	else:
		_simulate(delta)

	_update_shadow()


func _simulate(delta: float) -> void:
	if _resting:
		return
	_velocity.y += gravity * delta
	_velocity.x = move_toward(_velocity.x, 0.0, air_friction * 100.0 * delta)
	position += _velocity * delta

	if position.x < _min_x:
		position.x = _min_x
		_velocity.x = absf(_velocity.x) * bounce
	elif position.x > _max_x:
		position.x = _max_x
		_velocity.x = -absf(_velocity.x) * bounce

	if position.y < _ceil_y:
		position.y = _ceil_y
		_velocity.y = absf(_velocity.y) * bounce

	if position.y >= _floor_y:
		position.y = _floor_y
		if absf(_velocity.y) <= rest_velocity_threshold:
			_velocity.y = 0.0
			_velocity.x = move_toward(_velocity.x, 0.0, floor_friction * 100.0 * delta)
			if absf(_velocity.x) <= rest_velocity_threshold:
				_velocity = Vector2.ZERO
				_resting = true
				settled.emit()
		else:
			_velocity.y = -absf(_velocity.y) * bounce


func _clamp_horizontal() -> void:
	position.x = clampf(position.x, _min_x, _max_x)


func _update_shadow() -> void:
	if _shadow == null:
		return
	_shadow.position.x = position.x + _shadow_offset.x
	var height := clampf((_floor_y - position.y) / shadow_lift_range, 0.0, 1.0)
	_shadow.scale = Vector2.ONE * lerpf(1.0, 0.62, height)
	_shadow.modulate.a = lerpf(0.9, 0.2, height)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _dragging:
		_begin_drag()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()
		get_viewport().set_input_as_handled()


func _begin_drag() -> void:
	_dragging = true
	_resting = false
	_drag_offset = position - get_global_mouse_position()
	_velocity = Vector2.ZERO
	grabbed.emit()


func _end_drag() -> void:
	_dragging = false
	_resting = false
	_velocity = (_mouse_velocity * throw_boost).limit_length(max_throw_speed)
