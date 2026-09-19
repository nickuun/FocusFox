extends AnimatedSprite2D
class_name AnimatedProp

## A den find that moves: Kayleigh's fireplaces and plants, each a folder of numbered
## frames under assets/main_menu/environment/animated/.
##
## The animated twin of throwable_prop.gd. Both are the same prop to the player — you
## pick it up, fling it, it settles — and both run that behaviour out of prop_motion.gd
## rather than each owning a copy. The split is a GDScript constraint, not a design: the
## menu's desk plant is an authored Sprite2D in world.tscn, so ThrowableProp is stuck
## extending Sprite2D, and an animated find has to be an AnimatedSprite2D. See the class
## note in prop_motion.gd.
##
## What this file owns beyond the art is skins. A fireplace is one find with ten
## appearances rather than ten finds, so the frames are loaded as ten animations on one
## SpriteFrames and right-click steps between them. A find with a single appearance
## holds exactly one animation, named DEFAULT_SKIN, and ignores the whole mechanism.

## The frames are OUTPUT. The artist's delivery lives outside the repo; tools/den_items.json
## says which folder becomes which find and tools/den_import.py crops, halves and
## renumbers them. Change a size or a frame count there and re-run — editing these PNGs
## by hand means the next import silently throws the edit away.
const DIR := "res://assets/main_menu/environment/animated/"

## What a find with no skins calls its one animation. AnimatedSprite2D needs *some*
## animation name, and "default" is the one SpriteFrames ships with and that we drop.
const DEFAULT_SKIN := "only"

signal grabbed
## The moment the mouse lets go, before the prop has finished flying. The den listens
## for this to catch a find dropped back onto its drawer.
signal released
signal settled
## The player cycled the appearance. The den saves the choice against the find's id.
signal skin_changed(skin: String)

## The contact shadow tracking this prop, assigned by the den before it enters the tree.
var shadow: Sprite2D

var motion: PropMotion

var _skins: PackedStringArray = []
var _skin := 0
var _shadow_base_scale := Vector2.ONE
var _shadow_offset := Vector2.ZERO
var _dragging := false
var _drag_offset := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _mouse_velocity := Vector2.ZERO


func _init() -> void:
	motion = PropMotion.new(self)
	motion.settled.connect(func() -> void: settled.emit())


## Loads every skin's frames onto one SpriteFrames. `skins` is empty for a plain find.
##
## Called by the den before the prop enters the tree, so `size()` and the anchor are
## known in time to build the hitbox against them.
func load_frames(find_id: String, skins: PackedStringArray, fps: float) -> void:
	_skins = skins
	var frames := SpriteFrames.new()
	var names := skins if not skins.is_empty() else PackedStringArray([DEFAULT_SKIN])

	for i in names.size():
		var skin := names[i]
		var folder := "%s%s" % [DIR, find_id]
		if not skins.is_empty():
			folder += "/" + skin
		frames.add_animation(skin)
		frames.set_animation_loop(skin, true)
		frames.set_animation_speed(skin, fps)
		var n := 1
		while true:
			var path := "%s/%03d.png" % [folder, n]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(skin, load(path))
			n += 1
		if frames.get_frame_count(skin) == 0:
			push_warning("AnimatedProp '%s' has no frames at %s" % [find_id, folder])

	if frames.has_animation("default"):
		frames.remove_animation("default")
	sprite_frames = frames
	animation = names[0]


## Switches to a skin by name, for restoring a saved choice. Unknown names are ignored
## rather than clamped — a skin dropped from the manifest shouldn't silently become a
## different one the player never picked.
func set_skin(name: String) -> void:
	var at := _skins.find(name)
	if at >= 0:
		_apply_skin(at)


func current_skin() -> String:
	return _skins[_skin] if _skin < _skins.size() else ""


func has_skins() -> bool:
	return _skins.size() > 1


## The drawn size of the current frame. The den builds the hitbox and the shadow off
## this, the way it uses texture.get_size() for a still find.
##
## Every frame of a skin shares one canvas — den_import.py crops them all to the union
## of the animation — so this is stable while an animation plays. It does change when
## the skin does, which is why _apply_skin re-anchors.
func frame_size() -> Vector2:
	if sprite_frames == null or not sprite_frames.has_animation(animation):
		return Vector2(48, 48)
	if sprite_frames.get_frame_count(animation) == 0:
		return Vector2(48, 48)
	var tex := sprite_frames.get_frame_texture(animation, 0)
	return tex.get_size() if tex != null else Vector2(48, 48)


## Anchors the art at its base, so `position` is the bottom edge — the same contract
## every still find follows, and what lets finds of different heights share one floor
## line. Rounded because half of an odd number isn't a whole pixel, and this art is
## nearest-filtered.
func anchor_to_base() -> void:
	var size := frame_size()
	centered = false
	offset = Vector2(-roundf(size.x * 0.5), -size.y)


func _ready() -> void:
	anchor_to_base()
	motion.top_extent = _top_extent
	motion.start()
	_last_mouse = _mouse()
	adopt_shadow()
	var area := get_node_or_null("Area2D") as Area2D
	if area != null:
		area.input_event.connect(_on_area_input)
	play()


## Distance from `position` up to the top edge of the art. Base-anchored, so this is the
## full height — see PropMotion.compute_bounds, which keeps a tall find from punching
## its height off the top of the room.
func _top_extent() -> float:
	return -offset.y if not centered else frame_size().y * 0.5


## The mouse in the same space this prop's `position` is in — its parent's. Not
## get_global_mouse_position(), which answers in canvas space: the two stopped agreeing
## the moment the room could be panned.
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


## Takes the measurements of whatever is currently in `shadow`. Called on _ready, and
## again by the den when a skin change swaps the shadow for one sized to the new art —
## without it the replacement would be drawn at the old one's scale.
func adopt_shadow() -> void:
	if shadow == null or not is_instance_valid(shadow):
		return
	_shadow_offset = shadow.position - position
	_shadow_base_scale = shadow.scale


func _update_shadow() -> void:
	if shadow == null or not is_instance_valid(shadow):
		return
	# Pinned to the floor under the prop rather than to the prop, so a find picked up
	# leaves its shadow behind on the ground.
	var floor_y := motion.floor_y()
	shadow.position = Vector2(position.x + _shadow_offset.x, floor_y + _shadow_offset.y)
	var height := clampf((floor_y - position.y) / 220.0, 0.0, 1.0)
	shadow.scale = _shadow_base_scale * lerpf(1.0, 0.62, height)
	shadow.modulate.a = lerpf(0.9, 0.2, height)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and not _dragging:
		_begin_drag()
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and has_skins() and not _dragging:
		# Right-click cycles the appearance. Nothing else in the room uses the right
		# button, so this costs no other interaction.
		_apply_skin((_skin + 1) % _skins.size())
		Audio.play("click")
		skin_changed.emit(current_skin())
		get_viewport().set_input_as_handled()


## Ahead of the GUI on purpose: once a drag is underway the release has to land here
## wherever the cursor is. Letting it fall through would let a panel swallow it and the
## prop would stay stuck to the mouse.
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
	# Settle first: the den saves the resting spot on this signal and may pull the find
	# back into the wall band. The sway is measured from wherever that leaves us.
	settled.emit()
	if is_queued_for_deletion():
		return
	_swing_from(swing)


## Rocks the prop sideways and lets it settle back. Snapped to whole pixels at both ends
## so a hung find never rests half off the grid. A nudge along x rather than a rotation:
## spinning nearest-filtered pixel art resamples it into uneven pixel sizes.
func _swing_from(pixels: float) -> void:
	var rest_x := roundf(position.x)
	position.x = rest_x
	var offset_px := roundf(pixels)
	if is_zero_approx(offset_px):
		return
	position.x = rest_x + offset_px
	var tw := create_tween()
	tw.tween_property(self, "position:x", rest_x, motion.wall_settle_time) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Swapping skin can change the art's size, so the anchor, the hitbox and the shadow all
## have to follow it — otherwise the stove, which is twice the brick fireplace's height,
## would hang in the air off the previous skin's anchor.
func _apply_skin(index: int) -> void:
	_skin = index
	animation = _skins[index]
	play()
	anchor_to_base()
	resize_hitbox()
	motion.compute_bounds()


## Matches the child Area2D's box to the current art. Public because the den builds the
## hitbox when it creates the prop and this keeps the two in one place.
func resize_hitbox() -> void:
	var area := get_node_or_null("Area2D") as Area2D
	if area == null:
		return
	var col := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or not (col.shape is RectangleShape2D):
		return
	var size := frame_size()
	(col.shape as RectangleShape2D).size = size
	# A RectangleShape2D is measured from its middle, so that's the art's corner plus
	# half its size.
	col.position = offset + size * 0.5


# --- Passed through to the motion, so the den can treat both prop types alike --------

func rest_at(at: Vector2) -> void:
	motion.rest_at(at)


func drop_at(at: Vector2) -> void:
	if motion.drop_at(at):
		settled.emit()


func is_resting() -> bool:
	return motion.is_resting()


func set_bounds(left: float, right: float) -> void:
	motion.bound_left = left
	motion.bound_right = right
	motion.compute_bounds()
