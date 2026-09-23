extends Node2D
class_name PlantRig

## A den plant that sways because the engine moves it, not because it was drawn moving.
##
## The third kind of den find, and the cheapest one to make. A ThrowableProp is one
## image. An AnimatedProp is a folder of frames the artist drew one at a time. This is a
## dozen parts drawn ONCE — each leaf, plus the pot — that the game rotates on their own
## phases. Nothing loops, nothing repeats, and the artist never draws a second frame.
##
## The arithmetic is the argument for it. The fiddle-leaf fig is 27 drawings of a whole
## plant and plays one fixed cycle. This plant is 12 drawings and sways forever without
## repeating, because each leaf is on its own period and they drift out of step. The same
## twelve parts also recombine into other plants — see the note on kits below.
##
## --- The rig is generated ----------------------------------------------------
##
## assets/main_menu/environment/plants/<name>/ is OUTPUT. The artist's parts live outside
## the repo, and tools/plant_rig.py locates each one against her assembled reference,
## works out where it hinges, and writes rig.json. Re-run it to change scale or to take a
## new delivery; don't edit the PNGs or the json by hand.
##
## --- Why each leaf hinges where it does --------------------------------------
##
## A leaf sways from where its stem enters the soil. Rotating a leaf about its own centre
## makes it orbit, which reads as broken rather than as wind — the tip should travel
## while the base stays put. plant_rig.py takes each part's drawn pixel nearest the soil
## line as its hinge, so a leaf at the back left pivots at its bottom-right corner and one
## on the right pivots at its bottom-left, without either being typed in.
##
## --- On making kits ----------------------------------------------------------
##
## Nothing here requires the parts to be the ones the artist composed together. A rig is
## a list of parts with offsets, so a second plant can be built from a subset of the same
## delivery at different offsets and read as a different species. That is where this
## approach earns its keep, and it costs the artist nothing further.

## Where the rigs live. See the note above — this is output, not source.
const DIR := "res://assets/main_menu/environment/plants/"

## How far a leaf swings, in degrees, before its own size is taken into account. Small on
## purpose: this is a houseplant in a room, not a palm in a gale. A big leaf moving three
## degrees is already a lot of travel at its tip.
const SWAY_DEGREES := 2.6

## Seconds for one full breath. Each leaf takes a value either side of this so they drift
## apart instead of pulsing together, which is what stops the loop reading as a loop.
const SWAY_PERIOD := 4.2
const PERIOD_SPREAD := 0.45

## Bigger leaves move less. Without this the little ones look pinned while the big ones
## flap; weighting by size is what makes the whole plant read as one thing in one breeze.
const SIZE_DAMPING := 0.5

## How far the sway leans one way. Zero is a plant breathing in still air; pushed off
## centre it reads as a draught from one side.
const SWAY_BIAS := 0.15

signal grabbed
## The moment the mouse lets go, before the prop has finished flying. The den listens for
## this to catch a find dropped back onto its drawer.
signal released
signal settled

## The contact shadow tracking this plant, assigned by the den before it enters the tree.
var shadow: Sprite2D

## The same fling-and-settle physics the other two prop types run. A PlantRig is a plain
## Node2D, so unlike ThrowableProp and AnimatedProp it can hold the motion without any
## inheritance trouble at all — see the class note in prop_motion.gd.
var motion: PropMotion

var _parts: Array[Dictionary] = []
var _time := 0.0
## The pot's drawn size, which is what the find is anchored and sized by — a plant stands
## on its pot, and its leaves are allowed to overhang.
var _pot_size := Vector2(48, 48)
var _shadow_base_scale := Vector2.ONE
var _shadow_offset := Vector2.ZERO
var _dragging := false
var _drag_offset := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO


func _init() -> void:
	motion = PropMotion.new(self)
	motion.settled.connect(func() -> void: settled.emit())


## Loads a rig by name. Returns false if there's nothing there, so the den can skip a
## find whose art hasn't landed yet rather than putting an empty node in the room.
func load_rig(rig_name: String) -> bool:
	var path := DIR + rig_name + "/rig.json"
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("PlantRig: no rig at %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("PlantRig: could not read %s" % path)
		return false
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary) or not data.has("parts"):
		push_warning("PlantRig: %s is not a rig" % path)
		return false

	var pot: Array = data.get("pot_size", [48, 48])
	_pot_size = Vector2(float(pot[0]), float(pot[1]))

	# The pot goes down first so the leaves draw over its rim, which is what makes the
	# plant read as growing out of the soil rather than standing behind the pot. The
	# artist's own file order puts the pot last, since that is the order she painted in.
	var ordered: Array = []
	for entry in data["parts"]:
		if bool(entry.get("pot", false)):
			ordered.append(entry)
	for entry in data["parts"]:
		if not bool(entry.get("pot", false)):
			ordered.append(entry)

	for entry in ordered:
		var texture := load(DIR + rig_name + "/" + str(entry["file"])) as Texture2D
		if texture == null:
			continue
		var offset: Array = entry["offset"]
		var pivot: Array = entry["pivot"]
		var size: Array = entry["size"]

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Anchored at the hinge rather than the middle, so `rotation` swings the leaf from
		# its stem. The offset then puts the hinge where the artist had it.
		sprite.centered = false
		sprite.offset = Vector2(-float(pivot[0]), -float(pivot[1]))
		sprite.position = Vector2(float(offset[0]) + float(pivot[0]), float(offset[1]) + float(pivot[1]))
		add_child(sprite)

		var is_pot := bool(entry.get("pot", false))
		var area := maxf(1.0, float(size[0]) * float(size[1]))
		_parts.append({
			"node": sprite,
			"pot": is_pot,
			# Each leaf gets its own period and starting phase, derived from where it sits
			# rather than randomised, so a plant sways the same way every launch.
			"period": SWAY_PERIOD + fposmod(float(offset[0]) * 0.37 + float(offset[1]) * 0.11, PERIOD_SPREAD * 2.0) - PERIOD_SPREAD,
			"phase": fposmod(float(offset[0]) * 0.7 + float(offset[1]) * 1.3, TAU),
			# Weighted by size, so the big leaves move least. The pot never moves at all.
			"amount": 0.0 if is_pot else deg_to_rad(SWAY_DEGREES) * pow(1.0 / area, SIZE_DAMPING) * 40.0,
			"rest": sprite.rotation,
		})

	return not _parts.is_empty()


## The drawn size of the whole rig, for the den's hitbox and shadow. The pot's width,
## not the leaves' — a plant is grabbed by its pot, and a hitbox spanning every leaf
## would swallow half the room.
func rig_size() -> Vector2:
	return _pot_size


## Puts the rig's origin at the base of its pot, matching every other find's contract
## that `position` is the bottom edge. Called by the den before it places the plant.
func anchor_to_base() -> void:
	for part in _parts:
		var sprite := part["node"] as Sprite2D
		sprite.position -= Vector2(_pot_size.x * 0.5, _pot_size.y)


func _ready() -> void:
	motion.top_extent = _top_extent
	motion.start()
	_last_mouse = _mouse()
	adopt_shadow()
	var area := get_node_or_null("Area2D") as Area2D
	if area != null:
		area.input_event.connect(_on_area_input)


## How far the art reaches above `position`. The leaves, not the pot — this is what keeps
## a tall plant from being thrown up through the ceiling.
func _top_extent() -> float:
	var highest := 0.0
	for part in _parts:
		var sprite := part["node"] as Sprite2D
		highest = minf(highest, sprite.position.y + sprite.offset.y)
	return -highest


## The mouse in the same space this prop's `position` is in — its parent's. Not
## get_global_mouse_position(), which answers in canvas space and stops agreeing the
## moment the room is panned.
func _mouse() -> Vector2:
	var parent := get_parent() as Node2D
	return parent.get_local_mouse_position() if parent != null else get_global_mouse_position()


func _process(delta: float) -> void:
	_time += delta
	for part in _parts:
		if part["pot"]:
			continue
		var sprite := part["node"] as Sprite2D
		var t := _time / float(part["period"]) * TAU + float(part["phase"])
		# Two waves at an irrational ratio, so the sum never quite repeats — one breath
		# plus a slower drift under it. A single sine is recognisably a loop within about
		# ten seconds, which is exactly what this is meant to avoid.
		var wave := sin(t) * 0.75 + sin(t * 0.37) * 0.25
		sprite.rotation = float(part["rest"]) + (wave + SWAY_BIAS) * float(part["amount"])

	var mouse := _mouse()
	_mouse_velocity = (mouse - _last_mouse) / maxf(delta, 0.001)
	_last_mouse = mouse

	if _dragging:
		motion.drag_to(mouse + _drag_offset)
		motion.velocity = _mouse_velocity
	else:
		motion.step(delta)

	_update_shadow()


## Takes the measurements of whatever is currently in `shadow`.
func adopt_shadow() -> void:
	if shadow == null or not is_instance_valid(shadow):
		return
	_shadow_offset = shadow.position - position
	_shadow_base_scale = shadow.scale


func _update_shadow() -> void:
	if shadow == null or not is_instance_valid(shadow):
		return
	# Pinned to the floor under the plant rather than to the plant, so one picked up
	# leaves its shadow behind on the ground.
	var floor_y := motion.floor_y()
	shadow.position = Vector2(position.x + _shadow_offset.x, floor_y + _shadow_offset.y)
	var height := clampf((floor_y - position.y) / 220.0, 0.0, 1.0)
	shadow.scale = _shadow_base_scale * lerpf(1.0, 0.62, height)
	shadow.modulate.a = lerpf(0.9, 0.2, height)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and not _dragging:
		_begin_drag()
		get_viewport().set_input_as_handled()


## Ahead of the GUI on purpose: once a drag is underway the release has to land here
## wherever the cursor is, or letting go over a panel leaves the plant stuck to the mouse.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		motion.end_drag(_mouse_velocity)
		released.emit()


func _begin_drag() -> void:
	_dragging = true
	_drag_offset = position - _mouse()
	motion.begin_drag()
	grabbed.emit()


# --- Passed through to the motion, so the den can treat all three prop types alike ---

func rest_at(at: Vector2) -> void:
	motion.rest_at(at)


func drop_at(at: Vector2) -> void:
	if motion.drop_at(at):
		settled.emit()



## Re-reads the floor under this prop — see PropMotion.refresh_floor.
func refresh_floor() -> void:
	motion.refresh_floor()


func is_resting() -> bool:
	return motion.is_resting()


func set_bounds(left: float, right: float) -> void:
	motion.bound_left = left
	motion.bound_right = right
	motion.compute_bounds()
