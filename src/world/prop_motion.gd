extends RefCounted
class_name PropMotion

## The fling-and-settle physics a den find runs on, lifted out of the node that draws it.
##
## It exists because a find can be one of two node types and GDScript has no multiple
## inheritance. throwable_prop.gd is a Sprite2D — it has to be, the menu's desk plant is
## an authored Sprite2D in world.tscn with that script attached — while the animated
## finds Kayleigh delivered are AnimatedSprite2D. Both extend Node2D and nothing here
## needs more than that, so the physics moved to a plain object that drives a Node2D
## from the outside, and each node type keeps a thin script that owns only its art.
##
## The alternative was copying 200 lines of gravity and bounce into a second file, where
## the two would drift apart on the first bug fix that only landed in one of them.
##
## The owner supplies its own drawn extent through `top_extent`, which is the one thing
## the two node types genuinely disagree about: a Sprite2D measures its texture, an
## AnimatedSprite2D its current frame.

## Emitted the moment the prop comes to rest. The den saves the layout on this.
signal settled

const REST_SLACK := 1.0

var gravity := 2800.0
var bounce := 0.42
var air_friction := 0.6
var floor_friction := 84.0
var throw_boost := 1.0
var max_throw_speed := 2600.0
var rest_velocity_threshold := 22.0
var margin := 48.0
var wall_mounted := false
var wall_swing := 0.004
var wall_swing_max := 6.0
var wall_settle_time := 0.9
var bound_left := -1.0
var bound_right := -1.0

## `func(x: float, from_y: float) -> float` — the y of the nearest surface below.
var floor_provider := Callable()
## `func() -> float` — how far above `position` the art reaches. See the class note.
var top_extent := Callable()

var velocity := Vector2.ZERO
var resting := false

var _node: Node2D
var _authored_floor := 0.0
var _floor_y := 0.0
var _ceil_y := 0.0
var _min_x := 0.0
var _max_x := 0.0


func _init(node: Node2D) -> void:
	_node = node


## Called once the owner is in the tree, when a viewport and a position exist.
func start() -> void:
	_authored_floor = _node.position.y
	compute_bounds()


func compute_bounds() -> void:
	# The den restores a saved skin before the prop is added to the tree, and a node
	# outside it has no viewport to measure. Nothing is lost by returning early: start()
	# runs this again from _ready, once there is one.
	if not _node.is_inside_tree():
		return
	var view := _node.get_viewport_rect().size
	_floor_y = floor_at(_node.position.x, _node.position.y)
	# Measured to the art's visual top rather than to `position`, because a den find is
	# anchored at its base — left as a bare margin, a tall find would punch its whole
	# height off the top of the room.
	_ceil_y = margin + (float(top_extent.call()) if top_extent.is_valid() else 0.0)
	_min_x = bound_left if bound_left >= 0.0 else margin
	_max_x = bound_right if bound_right >= 0.0 else view.x - margin


## Pass INF for `from_y` to ask for the bare floor with every surface ignored — what
## dragging wants, so a find can travel down past a shelf it happens to pass over.
func floor_at(x: float, from_y: float) -> float:
	if floor_provider.is_valid():
		return float(floor_provider.call(x, from_y))
	return _authored_floor


## Re-reads the floor under the prop right now, rather than waiting for the next step().
## The den calls this the moment a find's depth changes, so the new line is in effect
## before gravity gets a chance to measure against the old one.
func refresh_floor() -> void:
	_floor_y = floor_at(_node.position.x, _node.position.y)


## The floor currently under the prop, for whoever is drawing its shadow.
func floor_y() -> float:
	return _floor_y


func clamp_horizontal() -> void:
	_node.position.x = clampf(_node.position.x, _min_x, _max_x)


## How far down the floor band the cursor may carry a find, regardless of the floor it
## currently stands on. The den sets it to FLOOR_NEAR; left at 0 the prop can only be
## lifted, never pushed nearer, which is how this behaved before the floor had depth.
var drag_floor := 0.0


## While the cursor holds it. A floor find can be lifted off the floor and also pushed
## down the band toward the camera — that is how its depth is chosen. A hung one follows
## freely and the den clamps it once it's let go.
func drag_to(at: Vector2) -> void:
	_node.position = at
	clamp_horizontal()
	if not wall_mounted:
		# The *bare* floor, ignoring shelves, so carrying something across the bookshelf
		# doesn't stop it dead at shelf height. maxf against drag_floor lets the cursor
		# take it past its own resting line and further down the band.
		var limit := maxf(floor_at(_node.position.x, INF), drag_floor)
		_node.position.y = minf(_node.position.y, limit)


func step(delta: float) -> void:
	if wall_mounted:
		return
	# Asked every frame rather than cached at the drop, so a find that slides off the end
	# of a shelf falls the rest of the way instead of skating out into mid-air.
	_floor_y = floor_at(_node.position.x, _node.position.y)
	if resting:
		# Resting is not permanent, which is the whole point of asking every frame. What a
		# find stands on can be carried off or put back in the drawer.
		if _floor_y <= _node.position.y + REST_SLACK:
			return
		resting = false
	velocity.y += gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, air_friction * 100.0 * delta)
	_node.position += velocity * delta

	if _node.position.x < _min_x:
		_node.position.x = _min_x
		velocity.x = absf(velocity.x) * bounce
	elif _node.position.x > _max_x:
		_node.position.x = _max_x
		velocity.x = -absf(velocity.x) * bounce

	if _node.position.y < _ceil_y:
		_node.position.y = _ceil_y
		velocity.y = absf(velocity.y) * bounce

	if _node.position.y >= _floor_y:
		_node.position.y = _floor_y
		# Friction applies on every touch of the floor, not only once the prop has stopped
		# bouncing. It used to sit inside the branch below, so a hard throw kept its full
		# horizontal speed through every bounce and only began to slow down after it had
		# settled — which is what made finds skate across the room like a puck.
		velocity.x = move_toward(velocity.x, 0.0, floor_friction * 100.0 * delta)
		if absf(velocity.y) <= rest_velocity_threshold:
			velocity.y = 0.0
			if absf(velocity.x) <= rest_velocity_threshold:
				velocity = Vector2.ZERO
				# Snapped where it comes to rest, so the spot the den saves is a whole
				# pixel rather than whatever fraction it stopped on.
				_node.position = _node.position.round()
				resting = true
				settled.emit()
		else:
			velocity.y = -absf(velocity.y) * bounce


func begin_drag() -> void:
	resting = false
	velocity = Vector2.ZERO


## Hands back the sway a hung find should rock through, or 0 for a floor find. The owner
## runs the tween, since only it can create one.
func end_drag(mouse_velocity: Vector2) -> float:
	velocity = (mouse_velocity * throw_boost).limit_length(max_throw_speed)
	resting = false
	if not wall_mounted:
		return 0.0
	# Back on the nail where you left it — no flight, just a rock that damps out. How
	# hard you flicked it decides how far it sways.
	var swing := clampf(velocity.x * wall_swing, -wall_swing_max, wall_swing_max)
	velocity = Vector2.ZERO
	resting = true
	return swing


## Pins the prop here and stops it simulating. For hung finds, which have no floor to
## fall to. Floor finds use drop_at() — see throwable_prop.gd's note on why.
func rest_at(at: Vector2) -> void:
	_node.position = at
	velocity = Vector2.ZERO
	compute_bounds()
	resting = true


## Puts the prop down and lets go. A floor find falls from here to whatever is
## underneath; a hung one simply stays.
func drop_at(at: Vector2) -> bool:
	if wall_mounted:
		rest_at(at)
		return true  # caller emits settled
	_node.position = at
	velocity = Vector2.ZERO
	resting = false
	compute_bounds()
	return false


## Where this prop lives, rather than still on its way there. The den asks before writing
## a layout: a position caught mid-flight is a point in thin air.
func is_resting() -> bool:
	return resting or wall_mounted
