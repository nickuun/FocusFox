extends Sprite2D
class_name ThrowableProp

## Makes a still menu prop (the desk plant, and every den find with one fixed image)
## draggable and throwable inside the launcher window. A child Area2D provides the click
## hit-test; a sibling shadow sprite tracks it for a cozy depth cue.
##
## The physics themselves live in prop_motion.gd, shared with animated_prop.gd — the
## same prop to the player, but an AnimatedSprite2D rather than a Sprite2D. This file
## keeps only what is specific to drawing one still texture. See the class note in
## prop_motion.gd for why the split is shaped this way.
##
## The exported knobs below are kept as @export on the node rather than moved onto the
## motion, because world.tscn authors the desk plant with them and the editor has to go
## on seeing them. _ready copies them across.

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

## Horizontal bounds a thrown prop is kept inside. The den overrides these per find,
## because the room's left end is a corner: a find standing on the floor there reads
## fine, one hung on the angled side wall does not. Left negative, both fall back to
## `margin` off each edge of the viewport.
@export var bound_left := -1.0
@export var bound_right := -1.0

## Where this prop comes to rest, asked of the room rather than remembered:
## `func(x: float, from_y: float) -> float`, returning the y of the nearest surface
## below `from_y` at horizontal position `x`.
##
## Unset — the menu's desk plant — the prop keeps resting at the y it was authored at,
## which is what everything did before the room had a floor worth asking about.
var floor_provider := Callable()

## The contact shadow that tracks this prop. The den assigns one before the prop enters
## the tree; the desk plant has its own authored sibling found by name instead.
var shadow: Sprite2D

var motion: PropMotion

signal grabbed
## The moment the mouse lets go, before the prop has finished flying. The den
## listens for this to catch a find dropped back onto its drawer.
signal released
signal settled

@onready var _area: Area2D = $Area2D

var _shadow: Sprite2D
var _shadow_base_scale := Vector2.ONE
var _shadow_offset := Vector2.ZERO
var _dragging := false
var _drag_offset := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO


func _init() -> void:
	motion = PropMotion.new(self)
	motion.settled.connect(func() -> void: settled.emit())


func _ready() -> void:
	# The exports are the authored surface; the motion is what runs. Copied here rather
	# than read live so there is one place they cross over.
	motion.gravity = gravity
	motion.bounce = bounce
	motion.air_friction = air_friction
	motion.floor_friction = floor_friction
	motion.throw_boost = throw_boost
	motion.max_throw_speed = max_throw_speed
	motion.rest_velocity_threshold = rest_velocity_threshold
	motion.margin = margin
	motion.wall_mounted = wall_mounted
	motion.wall_swing = wall_swing
	motion.wall_swing_max = wall_swing_max
	motion.wall_settle_time = wall_settle_time
	motion.bound_left = bound_left
	motion.bound_right = bound_right
	motion.floor_provider = floor_provider
	motion.top_extent = _top_extent

	_shadow = shadow if is_instance_valid(shadow) else get_parent().get_node_or_null("PlantShadow")
	if _shadow != null:
		_shadow_offset = _shadow.position - position
		_shadow_base_scale = _shadow.scale
	motion.start()
	_last_mouse = _mouse()
	if _area != null:
		_area.input_event.connect(_on_area_input)


## Re-fences the prop after it has already entered the tree. The den sets bounds before
## adding a find, so it needs no such thing — but the menu's desk plant is authored into
## the scene and computed its bounds long before anyone knew how wide the room was.
func set_bounds(left: float, right: float) -> void:
	bound_left = left
	bound_right = right
	motion.bound_left = left
	motion.bound_right = right
	motion.compute_bounds()


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


## The mouse in the same space this prop's `position` is in — its parent's.
##
## Not get_global_mouse_position(), which answers in canvas space. The two agreed
## exactly as long as the den sat at the origin, and stopped agreeing the moment the
## room could be panned: the prop would jump by the pan distance on being grabbed.
func _mouse() -> Vector2:
	var parent := get_parent() as Node2D
	return parent.get_local_mouse_position() if parent != null else get_global_mouse_position()


func _process(delta: float) -> void:
	var mouse := _mouse()
	_mouse_velocity = (mouse - _last_mouse) / maxf(delta, 0.001)
	_last_mouse = mouse

	if _dragging:
		motion.drag_to(mouse + _drag_offset)
		motion.velocity = _mouse_velocity
	else:
		motion.step(delta)

	_update_shadow()


func _update_shadow() -> void:
	if _shadow == null:
		return
	# Pinned to the floor under the prop rather than to the prop, so a find picked up
	# leaves its shadow behind on the ground — and a find standing on a shelf casts
	# onto the shelf instead of onto the floorboards far below it.
	var floor_y := motion.floor_y()
	_shadow.position = Vector2(position.x + _shadow_offset.x, floor_y + _shadow_offset.y)
	var height := clampf((floor_y - position.y) / shadow_lift_range, 0.0, 1.0)
	_shadow.scale = _shadow_base_scale * lerpf(1.0, 0.62, height)
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
	_drag_offset = position - _mouse()
	motion.begin_drag()
	grabbed.emit()


func _end_drag() -> void:
	_dragging = false
	var swing := motion.end_drag(_mouse_velocity)
	if not motion.wall_mounted:
		released.emit()
		return
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


## Pins the prop exactly here and stops it simulating. For hung finds, which have no
## floor to fall to — the den uses it to pull a painting back into the wall band after
## it's been let go somewhere it shouldn't be.
##
## Not for floor finds. This used to be how the drawer placed everything, and because
## it also made `at` the prop's floor, wherever you put a find down became the height
## it fell back to — so a mug placed at head height would drop through the air and stop
## dead in mid-air, forever. Floor finds use drop_at().
func rest_at(at: Vector2) -> void:
	motion.rest_at(at)


## Puts the prop down at `at` and lets go. Where it ends up is the room's business: a
## floor find falls from here to whatever floor_provider says is underneath, so
## dropping one in mid-air lands it on the floor, and dropping it over a shelf lands it
## on the shelf. A hung one simply stays.
func drop_at(at: Vector2) -> void:
	if motion.drop_at(at):
		settled.emit()


## Whether this prop is where it lives, rather than still on its way there. The den asks
## before writing a layout: a position caught mid-flight is a point in thin air, and
## saving it means the next launch loads the find above the floor and drops it all over
## again. A hung find has no flight to be in the middle of.
func is_resting() -> bool:
	return motion.is_resting()
