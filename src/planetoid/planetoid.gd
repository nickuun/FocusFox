extends RigidBody2D

## The fox body. Owns the physics, the click feel and the animation state machine, and
## can draw itself in either of two art styles.
##
## --- Two styles, one API -----------------------------------------------------
##
## CLASSIC is the original 32px fox on a 14x7 sprite sheet. DRAWN is the hand-drawn set
## (see FoxV2). Everything outside this file — the desktop pet, the menu room, the
## settings preview — talks to the same methods regardless, so the swap is one property
## and nothing else moves.
##
## The two are NOT the same size. The classic fox draws about a 100px fox inside its
## 160px frame; the drawn fox is roughly 230px for the same body scale. Both have to be
## drawn at a whole number of screen pixels per source texel (the overlay windows do no
## scaling of their own, and the project filters nearest), and the classic sheet is
## already baked at 5x, so there is no scale that makes them match — the drawn fox is
## simply the bigger of the two at a given "Fox size" setting. If that gap wants closing,
## STYLE_BODY_SCALE below is the one number to change.
##
## --- What the drawn set can't do ---------------------------------------------
##
## It has no equivalent of `idle_look`, the occasional glance the classic fox does while
## standing. DRAWN_CLIP maps it to nothing and the ambient timer doesn't run, so the
## drawn fox simply doesn't glance. Everything else the game asks for — idle, trot,
## pounce, sleep — it has.

const FOX_SPRITE_SHEET: Texture2D = preload("res://assets/fox/Fox Sprite Sheet.png")
const PALETTE_SHADER: Shader = preload("res://src/planetoid/fox_palette.gdshader")

const FOX_SPRITE_SIZE := Vector2i(32, 32)

enum Style {
	CLASSIC,  ## the original 32px sprite sheet
	DRAWN,    ## the hand-drawn set in assets/fox/animations/v2
}

# Animations on the 14x7 sheet. row = sheet row, frames = column count used.
# (Row 4 "surprise" and row 6 are intentionally not wired up yet.)
const ANIMS := {
	"idle": {"row": 0, "frames": 5, "fps": 6.0, "loop": true},
	"idle_look": {"row": 1, "frames": 14, "fps": 11.0, "loop": false},
	"trot": {"row": 2, "frames": 8, "fps": 12.0, "loop": true},
	"pounce": {"row": 3, "frames": 11, "fps": 14.0, "loop": false},
	"sleep": {"row": 5, "frames": 6, "fps": 4.0, "loop": true},
}

## Which drawn clip stands in for each animation state. An empty string means the drawn
## set has nothing for it and the fox should hold whatever it was doing.
const DRAWN_CLIP := {
	"idle": "idle",
	"idle_look": "",
	"trot": "walk",
	"pounce": "pounce",
	"sleep": "sleep",
}

## Extra body scale per style, on top of the player's "Fox size". Both must stay whole
## numbers or the art tears under the project's nearest filter — see the note up top.
const STYLE_BODY_SCALE := {
	Style.CLASSIC: 1.0,
	Style.DRAWN: 1.0,
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

## The drawn fox, built the first time this body is asked to draw one. Left null while
## the classic style is selected — FoxV2 loads every frame of all eight clips up front,
## which is not worth paying for on foxes that will never show it.
var _fox_v2: FoxV2
## Wrapper the click pulse scales. FoxV2 rewrites its own `scale` whenever the clip
## changes, so the pulse cannot live on the sprite itself the way it does for classic.
var _drawn_holder: Node2D

var _style: Style = Style.CLASSIC
var _palette := {"a": Color.WHITE, "b": Color.WHITE, "rainbow": false, "set": false}
var _highlight := {"on": false, "colour": Color.WHITE}


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
	# Ambient charm: while standing idle the fox occasionally glances around. The drawn
	# set has no glance, so it doesn't apply there.
	if _style == Style.DRAWN:
		return
	if _transient == "" and _sprite.animation == "idle":
		_idle_look_timer -= delta
		if _idle_look_timer <= 0.0:
			play_oneshot("idle_look")
			_reset_idle_look_timer()


# --- Style -----------------------------------------------------------------

## Swap which fox is drawn. Safe to call repeatedly and safe to call before _ready().
func set_fox_style(style: Style) -> void:
	if style == _style and (style == Style.CLASSIC or _fox_v2 != null):
		return
	_style = style
	if style == Style.DRAWN:
		_ensure_drawn()
	if _drawn_holder != null:
		_drawn_holder.visible = style == Style.DRAWN
	if is_instance_valid(_sprite):
		_sprite.visible = style == Style.CLASSIC
	# Everything cosmetic lives on whichever node is drawing, so it all has to be put
	# back on the new one.
	_reapply_palette()
	_reapply_highlight()
	set_body_rotation_speed(_body_speed_multiplier)
	_play(_transient if _transient != "" else _base_state)


func get_fox_style() -> Style:
	return _style


## Accepts the string the settings and the save file use, so callers don't need the enum.
func set_fox_style_name(name: String) -> void:
	set_fox_style(Style.DRAWN if name == "drawn" else Style.CLASSIC)


func get_fox_style_name() -> String:
	return "drawn" if _style == Style.DRAWN else "classic"


func _ensure_drawn() -> void:
	if _fox_v2 != null:
		return
	_drawn_holder = Node2D.new()
	_drawn_holder.name = "DrawnFoxHolder"
	_drawn_holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_drawn_holder)

	_fox_v2 = FoxV2.new()
	_fox_v2.name = "DrawnFox"
	_fox_v2.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_drawn_holder.add_child(_fox_v2)
	_fox_v2.clip_finished.connect(_on_drawn_clip_finished)
	# FoxV2 anchors itself at the fox's feet. The body's origin is the fox's middle (the
	# classic sprite is centred there), so drop the holder by half the tallest clip: the
	# feet then sit on the bottom of that box and taller poses grow upwards, which is
	# what a fox standing on the ground should do.
	_fox_v2.play_clip(_drawn_clip_for(_base_state))
	_drawn_holder.position = Vector2(0.0, _fox_v2.nominal_size().y * 0.5)
	_drawn_holder.scale = Vector2.ONE * float(STYLE_BODY_SCALE[Style.DRAWN])


func _drawn_clip_for(anim: String) -> String:
	var clip: String = DRAWN_CLIP.get(anim, "")
	return clip if clip != "" else DRAWN_CLIP.get(_base_state, "idle")


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
	# The drawn set has no clip for some of these (the glance). Asking for one would
	# otherwise leave _transient set on an animation that never finishes, and the fox
	# would stop returning to its base state.
	if _style == Style.DRAWN and DRAWN_CLIP.get(state, "") == "":
		return
	_transient = state
	_play(state)


func set_facing(direction: float) -> void:
	if absf(direction) <= 0.01:
		return
	if _style == Style.DRAWN and _fox_v2 != null:
		# FoxV2 knows which way its art faces, so it does its own flipping.
		_fox_v2.set_facing(direction)
	else:
		_sprite.flip_h = direction < 0.0


func play_pounce(seconds: float) -> void:
	# Time the pounce animation so its final (landing) frame lands with the fox.
	if _style == Style.DRAWN and _fox_v2 != null:
		# Multiplied by the speed scale because liveliness is applied on top, and what
		# has to come out right is the wall-clock duration.
		_fox_v2.retime_clip("pounce", seconds * maxf(0.01, _fox_v2.speed_scale))
	elif _sprite.sprite_frames != null:
		var count := _sprite.sprite_frames.get_frame_count("pounce")
		_sprite.sprite_frames.set_animation_speed("pounce", float(count) / maxf(0.1, seconds))
	play_oneshot("pounce")


func set_palette(target_a: Color, target_b: Color, rainbow := false) -> void:
	_palette = {"a": target_a, "b": target_b, "rainbow": rainbow, "set": true}
	_reapply_palette()


## The drawn art uses exactly the same two body colours as the sheet (#d67941 / #9d5021),
## so one shader recolours either style with no special casing.
func _reapply_palette() -> void:
	if not _palette["set"]:
		return
	var target := _drawing_node()
	if target == null:
		return
	var material := target.material as ShaderMaterial
	if material == null:
		material = ShaderMaterial.new()
		material.shader = PALETTE_SHADER
		target.material = material
	material.set_shader_parameter("target_a", _palette["a"])
	material.set_shader_parameter("target_b", _palette["b"])
	material.set_shader_parameter("rainbow", 1.0 if _palette["rainbow"] else 0.0)


func _on_anim_finished() -> void:
	if _style == Style.DRAWN:
		return
	_finish_oneshot()


func _on_drawn_clip_finished(_clip: String) -> void:
	_finish_oneshot()


func _finish_oneshot() -> void:
	if _transient == "":
		return
	var finished := _transient
	_transient = ""
	_play(_base_state)
	_reset_idle_look_timer()
	oneshot_finished.emit(finished)


func _play(anim: String) -> void:
	if _style == Style.DRAWN:
		if _fox_v2 == null:
			return
		_fox_v2.play_clip(_drawn_clip_for(anim))
		return
	if _sprite.animation != anim:
		_sprite.animation = anim
	_sprite.play(anim)


func _reset_idle_look_timer() -> void:
	_idle_look_timer = randf_range(idle_look_min, idle_look_max)


## Whichever node is currently drawing the fox. The palette shader and the hover tint
## both apply to this rather than to a fixed sprite.
func _drawing_node() -> CanvasItem:
	if _style == Style.DRAWN:
		return _fox_v2
	return _sprite


# --- Look / feel -----------------------------------------------------------

func set_highlight(highlighted: bool, highlight_modulate: Color) -> void:
	_highlight = {"on": highlighted, "colour": highlight_modulate}
	_reapply_highlight()


func _reapply_highlight() -> void:
	var target := _drawing_node()
	if target != null:
		target.modulate = _highlight["colour"] if _highlight["on"] else _base_modulate


func pulse_click() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()

	# The drawn fox is pulsed through its holder: FoxV2 rewrites its own scale on every
	# clip change and would cancel the tween halfway through.
	var target: Node2D = _drawn_holder if _style == Style.DRAWN else _sprite
	if target == null:
		return
	var base: Vector2 = (
		Vector2.ONE * float(STYLE_BODY_SCALE[Style.DRAWN]) if _style == Style.DRAWN
		else _base_sprite_scale
	)

	target.scale = base
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(target, "scale", base * pulse_squash, pulse_seconds * 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(target, "scale", base * pulse_pop, pulse_seconds * 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(target, "scale", base, pulse_seconds * 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	if _fox_v2 != null:
		# One dial for the whole set, rather than the classic style's per-animation rates:
		# FoxV2's frame rates are part of how each clip reads, so they're scaled, not replaced.
		_fox_v2.speed_scale = _body_speed_multiplier
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
	if _style == Style.DRAWN and _fox_v2 != null:
		# The largest clip, not the current one — otherwise the overlay window would
		# resize itself every time the fox lay down.
		return _fox_v2.nominal_size() * float(STYLE_BODY_SCALE[Style.DRAWN])
	var base := Vector2(FOX_SPRITE_SIZE)
	if _sprite.sprite_frames != null:
		var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
		if texture != null:
			base = texture.get_size()
	return base * _sprite.scale.abs()


func get_pick_radius() -> float:
	var scale_max := maxf(absf(global_scale.x), absf(global_scale.y))
	if _style == Style.DRAWN and _fox_v2 != null:
		# The collision circle is sized for the classic fox, which is much the smaller of
		# the two; using it for the drawn one would leave most of the fox unclickable.
		var drawn := get_sprite_pixel_size()
		return maxf(drawn.x, drawn.y) * 0.5 * scale_max

	if _collision_shape.shape is CircleShape2D:
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
