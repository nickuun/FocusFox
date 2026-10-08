extends ThrowableProp
class_name WoolBasket

## One find with four independently draggable parts. Loose wool uses room physics;
## packed wool rides with the basket and is drawn behind its front lip.
signal contents_grabbed
signal contents_released
signal contents_changed

const COLOURS := ["white", "blue", "red", "green"]
const WOOL := [
	preload("res://assets/main_menu/environment/wool/white-wool.png"),
	preload("res://assets/main_menu/environment/wool/blue-wool.png"),
	preload("res://assets/main_menu/environment/wool/red-wool.png"),
	preload("res://assets/main_menu/environment/wool/green-wool.png"),
]
const FRONT := preload("res://assets/main_menu/environment/wool/basket-front.png")
const SLOTS := [Vector2(-18, -37), Vector2(6, -40), Vector2(-7, -25), Vector2(23, -27)]
const LOOSE_Z := 12 # Den's floor props are at 10; loose wool sits above them.

var _balls: Array[ThrowableProp] = []
var _slots: Array[int] = [0, 1, 2, 3] # -1 means loose in the room
var _front: Sprite2D
var _held_ball := -1
var _saved_contents: Dictionary = {}
var _floors: Array[float] = [367.0, 367.0, 367.0, 367.0]


func _ready() -> void:
	super._ready()
	for i in COLOURS.size():
		var ball := ThrowableProp.new()
		ball.texture = WOOL[i]
		ball.centered = false
		ball.offset = Vector2(-15, -31)
		ball.bounce = 0.22
		ball.floor_provider = _wool_floor.bind(i)
		ball.bound_left = bound_left - position.x
		ball.bound_right = bound_right - position.x
		ball.drag_floor = drag_floor - position.y
		ball.margin = -position.y + 8.0
		var saved: Dictionary = _saved_contents.get(COLOURS[i], {})
		_slots[i] = clampi(int(saved.get("slot", i)), -1, SLOTS.size() - 1)
		_floors[i] = float(saved.get("floor", 367.0))
		ball.position = SLOTS[_slots[i]] if _slots[i] >= 0 else saved.get("position", position + SLOTS[i]) - position
		var area := Area2D.new()
		area.name = "Area2D"
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 14.0
		col.shape = shape
		col.position = Vector2(0, -16)
		area.add_child(col)
		ball.add_child(area)
		_balls.append(ball)
		add_child(ball)
		ball.grabbed.connect(_grab_wool.bind(i))
		ball.released.connect(_release_wool.bind(i))
		ball.settled.connect(func() -> void: contents_changed.emit())
		if _slots[i] >= 0:
			ball.rest_at(SLOTS[_slots[i]])
			ball.set_process(false)
		else:
			# Loose wool lives in the room, so moving the basket never needs to
			# counter-move it or recompute its physics bounds each frame.
			_detach_ball(i)
	_front = Sprite2D.new()
	_front.texture = FRONT
	_front.centered = false
	_front.offset = offset
	add_child(_front)
	_order_wool()


func _detach_ball(i: int) -> void:
	var ball := _balls[i]
	ball.reparent(get_parent(), true)
	ball.motion.margin = 8.0
	ball.motion.drag_floor = drag_floor
	ball.set_bounds(bound_left, bound_right)
	ball._last_mouse = ball._mouse()
	ball._drag_offset = ball.position - ball._last_mouse
	ball.set_process(true)


func _pack_ball(i: int, slot: int) -> void:
	var ball := _balls[i]
	_slots[i] = slot
	if ball.get_parent() != self:
		ball.reparent(self, true)
	ball.set_process(false)
	ball.rest_at(SLOTS[slot])


func _wool_floor(x: float, from_y: float, i: int) -> float:
	if _slots[i] >= 0:
		return SLOTS[_slots[i]].y
	var best := _floors[i]
	if not is_inf(from_y) and get_parent().has_method("floor_for"):
		var surface := float(get_parent().call("floor_for", x,
			from_y, "wool_basket/" + COLOURS[i]))
		if surface < 358.0:
			best = minf(best, surface)
	if not is_inf(from_y):
		for other in _balls.size():
			if other == i or _slots[other] >= 0 or not _balls[other].is_resting():
				continue
			var top := _balls[other].position.y - 27.0
			if absf(x - _balls[other].position.x) < 13.0 and top >= from_y - 14.0:
				best = minf(best, top)
	return best


func _grab_wool(i: int) -> void:
	_held_ball = i
	_slots[i] = -1
	if _balls[i].get_parent() == self:
		_detach_ball(i)
	_floors[i] = clampf(position.y, 358.0, 450.0)
	_balls[i].z_index = LOOSE_Z
	contents_grabbed.emit()
	get_node("/root/Audio").play("grab")


func _release_wool(i: int) -> void:
	var at := _balls[i].position - position
	if at.y + position.y >= 344.0:
		_floors[i] = clampf(at.y + position.y, 358.0, 450.0)
	# A drop over the opening repacks the ball. Pick the nearest slot and swap
	# its occupant to an empty one, so colours can be rearranged without a menu.
	if absf(at.x) <= 42.0 and at.y >= -70.0 and at.y <= -12.0:
		var nearest := 0
		for slot in SLOTS.size():
			if at.distance_squared_to(SLOTS[slot]) < at.distance_squared_to(SLOTS[nearest]):
				nearest = slot
		var occupant := _slots.find(nearest)
		if occupant >= 0:
			for slot in SLOTS.size():
				if not _slots.has(slot):
					_pack_ball(occupant, slot)
					break
		_pack_ball(i, nearest)
	_held_ball = -1
	_order_wool()
	contents_released.emit()
	contents_changed.emit()
	get_node("/root/Audio").play("drop")


func _order_wool() -> void:
	var order := range(_balls.size())
	order.sort_custom(func(a, b): return _slots[a] < _slots[b])
	for i in order:
		_balls[i].z_index = 0 if _slots[i] >= 0 else LOOSE_Z
		if _slots[i] >= 0:
			move_child(_balls[i], -1)
	if is_instance_valid(_front):
		move_child(_front, -1)


func save_contents() -> Dictionary:
	var result := {}
	for i in _balls.size():
		var ball := _balls[i]
		# Never persist a point still in hand or flight; use the last settled state.
		if i == _held_ball or (_slots[i] < 0 and not ball.is_resting()):
			result[COLOURS[i]] = _saved_contents.get(COLOURS[i], {"slot": i})
		else:
			result[COLOURS[i]] = {"slot": _slots[i], "position": ball.position if _slots[i] < 0 else ball.position + position, "floor": _floors[i]}
	_saved_contents = result.duplicate(true)
	return result


func restore_contents(data: Dictionary) -> void:
	_saved_contents = data.duplicate(true)


func tidy_contents() -> void:
	for i in _balls.size():
		_pack_ball(i, i)
	_order_wool()
	contents_changed.emit()


func stop_contents() -> void:
	for ball in _balls:
		ball.set_process(false)
		ball.set_process_input(false)
		ball.get_node("Area2D").input_pickable = false
		if ball.get_parent() != self:
			ball.hide()
			ball.queue_free()


func _exit_tree() -> void:
	# Detached parts are still owned by this find and must leave with it.
	for ball in _balls:
		if is_instance_valid(ball) and ball.get_parent() != self:
			ball.queue_free()
