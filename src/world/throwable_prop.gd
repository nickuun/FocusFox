extends Sprite2D
class_name ThrowableProp

## Makes a menu prop (the desk plant) draggable and throwable inside the launcher
## window. Uses simple hand-rolled physics so it stays self-contained to the menu
## viewport - no RigidBody / world colliders needed. A child Area2D provides the
## click hit-test; a sibling "PlantShadow" sprite tracks it for a cozy depth cue.

@export var gravity := 2800.0
@export var bounce := 0.42
@export var air_friction := 0.6
## Deceleration once a prop is down on the floor, in hundreds of px/s². Low values
## read as ice: a hard throw keeps skating until it hits a wall. This is the number
## to turn if finds feel slippery — no scene overrides it, so it covers the menu
## plant and every den find at once.
@export var floor_friction := 28.0
@export var throw_boost := 1.0
@export var max_throw_speed := 2600.0
@export var rest_velocity_threshold := 22.0
@export var margin := 48.0
@export var shadow_lift_range := 220.0

## A hung find ignores gravity entirely: it stays on the nail wherever it's put,
## drags freely in both axes instead of only lifting off the floor, and settles the
## moment you let go. The den decides what counts as wall — see DenCatalog.is_wall.
@export var wall_mounted := false

## How far a hung find rocks when you let go of it — pixels of sideways sway per
## unit of throw speed, capped, then damped back to true. Purely cosmetic.
##
## Deliberately a nudge along x rather than a rotation: everything here is pixel art
## drawn at 1:1, and spinning a nearest-filtered sprite resamples it into uneven
## pixel sizes. Sliding it by whole pixels keeps the grid intact.
@export var wall_swing := 0.004
@export var wall_swing_max := 6.0
@export var wall_settle_time := 0.9

signal grabbed
## The moment the mouse lets go, before the prop has finished flying. The den
## listens for this to catch a find dropped back onto its drawer.
signal released
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
	# Measured to the sprite's visual top rather than to `position`, because a den
	# find is anchored at its base (Den._create_item) — left as a bare margin, a
	# tall find like the bookshelf would punch its whole height off the top.
	_ceil_y = margin + _top_extent()
	_min_x = margin
	_max_x = view.x - margin


## Distance from `position` up to the top edge of the drawn sprite, whatever the
## anchoring. A centred sprite with no offset — the menu's desk plant — gives half
## the texture, as before; a den find anchored at its base gives its full height.
func _top_extent() -> float:
	if texture == null:
		return 0.0
	var top := offset.y
	if centered:
		top -= texture.get_size().y * 0.5
	return -top


func _process(delta: float) -> void:
	var mouse := get_global_mouse_position()
	_mouse_velocity = (mouse - _last_mouse) / maxf(delta, 0.001)
	_last_mouse = mouse

	if _dragging:
		position = mouse + _drag_offset
		_clamp_horizontal()
		# A floor find can only be lifted off its floor, never pushed through it. A
		# hung one has no floor, so it follows the cursor freely and the den clamps
		# it to the wall band once it's let go.
		if not wall_mounted:
			position.y = minf(position.y, _floor_y)
		_velocity = _mouse_velocity
	else:
		_simulate(delta)

	_update_shadow()


func _simulate(delta: float) -> void:
	if _resting or wall_mounted:
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


## Ahead of the GUI on purpose: once a drag is underway the release has to land
## here wherever the cursor happens to be. Let it fall through to _unhandled_input
## and letting go over a panel — the den's drawer, say — would be swallowed by it
## and the prop would stay stuck to the mouse.
func _input(event: InputEvent) -> void:
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
	if wall_mounted:
		# Back on the nail where you left it — no flight, just a rock that damps out.
		# How hard you flicked it decides how far it sways.
		var swing := clampf(_velocity.x * wall_swing, -wall_swing_max, wall_swing_max)
		_velocity = Vector2.ZERO
		_resting = true
		released.emit()
		# Letting go over the open drawer puts it away, and the den frees us.
		if is_queued_for_deletion():
			return
		# Settle first: the den saves the resting spot on this signal, and may pull
		# the find back into the wall band. The sway is measured from wherever that
		# leaves us, and returns to exactly it.
		settled.emit()
		if is_queued_for_deletion():
			return
		_swing_from(swing)
		return
	released.emit()


## Rocks the prop sideways by `pixels` and lets it settle back. Snapped to whole
## pixels at both ends so a hung find never comes to rest half off the grid.
func _swing_from(pixels: float) -> void:
	var rest_x := roundf(position.x)
	position.x = rest_x
	var offset_px := roundf(pixels)
	if is_zero_approx(offset_px):
		return
	position.x = rest_x + offset_px
	var tw := create_tween()
	tw.tween_property(self, "position:x", rest_x, wall_settle_time) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Re-homes the prop: it comes to rest exactly here, and here is the floor it
## falls back to if it's thrown from now on. The den's drawer uses this so you can
## put a find wherever you like instead of on the shelf it was authored at — a
## plain throw still drops back to wherever it was last put down.
func rest_at(at: Vector2) -> void:
	position = at
	_velocity = Vector2.ZERO
	_compute_bounds()
	_resting = true
