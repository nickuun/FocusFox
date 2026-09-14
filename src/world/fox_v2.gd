class_name FoxV2
extends AnimatedSprite2D

## The revamped fox: hand-drawn clips, one folder of numbered frames each, living at
## assets/fox/animations/v2/<clip>/001.png…
##
## Nothing here touches the old fox. planetoid.gd still runs the 14x7 sprite sheet and
## still owns the desktop pet; this is a second, parallel fox that the menu can show
## instead. Keeping them side by side is the point — the new set is not finished, and
## the two can be compared in place (see world.gd's V2 review keys).
##
## --- These frames are generated, not delivered --------------------------------
##
## Everything under assets/fox/animations/v2/ is OUTPUT. The artist's delivery lives
## outside the repo and is never edited; tools/fox_clips.json says which delivered frames
## become which clip, and tools/fox_import.py crops, scales and renumbers them. To change
## a clip's framing, timing or size, edit the manifest and re-run — don't touch the PNGs,
## the next run overwrites them.
##
## That is also why every clip here is art_scale 1.0. The set arrived at three different
## sizes (sit and run two-thirds of walk and sleep; the play frames about 4.6x), and
## matching them up is now done once at import rather than compensated for at runtime.
## The import prints a size metric per clip so the match can be checked.
##
## --- The fox is deliberately not 1:1 ------------------------------------------
##
## An earlier plan had every clip redrawn two to three times larger so one art pixel
## would land on one physical pixel, the way the room art does. That is dropped. The fox
## is drawn small and scaled up, so it reads chunkier than the room on purpose.
##
## What the project's nearest filter (default_texture_filter=0) actually needs is not 1:1
## but a *whole* number of physical pixels per source texel. The launcher renders the
## 960x540 design space at 2x, so that number is art_scale * 2 — which is 2 with every
## clip at art_scale 1.0. Anything that changes the window scaling has to revisit this,
## and any art_scale that isn't a multiple of 0.5 will tear.
##
## --- Anchoring ---------------------------------------------------------------
##
## Each clip was exported on its own canvas with its own margins, so the frames do not
## share an origin: played back naively the fox jumps as the clip changes. ANCHOR is the
## fox's footing in each clip's own pixels, taken as the union of every frame in the clip
## so the anchor can't drift as the tail swings or the run leaves the ground — the centre
## of that union horizontally, its bottom edge vertically. Fed to AnimatedSprite2D's
## `offset`, which is applied before `scale`, it puts the node's position exactly under
## the fox's feet whatever the clip's scale is.

const DIR := "res://assets/fox/animations/v2/"

enum Playback {
	LOOP,      ## frames 1..n, repeat
	PINGPONG,  ## frames 1..n then back down; for clips whose ends don't meet
	ONESHOT,   ## frames 1..n once, then hold the last frame and emit clip_finished
}

## Emitted when a ONESHOT clip reaches its end. The caller decides what to play next —
## the old fox does the same thing with `oneshot_finished`, so a pounce can hand back to
## whatever resting state the fox was in.
signal clip_finished(clip: String)

const CLIPS := {
	# --- Delivered as their own animations -----------------------------------------

	# The best clip in the set and the one everything else is sized against: a clean
	# 12-frame cycle whose ends meet (0.89x the average frame-to-frame change).
	"walk": {
		"frames": 12, "fps": 12.0, "art_scale": 1.0,
		"playback": Playback.LOOP, "anchor": Vector2(117.5, 177.0),
	},
	# Breathing, curled up. Ends meet (0.91x). Slow — 20 frames at 8fps is a 2.5s breath.
	"sleep": {
		"frames": 20, "fps": 8.0, "art_scale": 1.0,
		"playback": Playback.LOOP, "anchor": Vector2(89.0, 132.0),
	},
	# Sitting idle: a tail sweep with a blink in it. Despite the folder name it is not a
	# stand-to-sit transition — the fox is already seated in frame 1 and still seated in
	# frame 25 — so it is the clip to hold under a resting fox, not one to play into.
	# Ping-pong because its ends don't quite meet (1.24x), and because a tail that sweeps
	# out and back and eyes that close and open are what the pose wants anyway.
	"sit": {
		"frames": 25, "fps": 12.0, "art_scale": 1.0,
		"playback": Playback.PINGPONG, "anchor": Vector2(98.0, 191.0),
	},
	# NOTE: this one does not close — the last frame to the first is a 1.54x jump against
	# the average step, so a plain loop visibly hitches once a cycle. Ping-pong would hide
	# it, but a run played backwards is wrong, so it loops and the hitch stands until the
	# cycle is redrawn. Not wired to anything for that reason.
	"run": {
		"frames": 20, "fps": 18.0, "art_scale": 1.0,
		"playback": Playback.LOOP, "anchor": Vector2(123.0, 191.0),
	},

	# --- Cut out of the delivered "Fox Play 02" ------------------------------------
	#
	# Not separate deliveries: slices of one 151-frame animation of the fox playing with
	# a ball, which happens to contain a standing fox, a creep, a leap and a roll — three
	# of the poses the set was otherwise missing.
	#
	# What makes them placeholders is timing, not size. Being slices of one continuous
	# performance, none of them close into a loop: measured against the average
	# frame-to-frame change, the wrap from last frame to first is a 6.3x jump for idle,
	# 2.5x for stalk and 5.1x for play, where walk manages 0.89x. Ping-pong hides it for
	# the two that can take it. The real fix is clips animated as cycles.

	# The nearest thing to a standing idle in the whole delivery, and the pose the desktop
	# pet holds most of the time. Cut short of where the fox lifts a front paw and starts
	# to step toward the ball — that reads as walking off, not as standing still.
	"idle": {
		"frames": 13, "fps": 12.0, "art_scale": 1.0,
		"playback": Playback.PINGPONG, "anchor": Vector2(115.0, 181.0),
	},
	# A low creeping walk. Ping-pong is not an option — a gait played backwards is a
	# moonwalk — so it loops with its hitch showing, and is not wired to any behaviour.
	"stalk": {
		"frames": 20, "fps": 12.0, "art_scale": 1.0,
		"playback": Playback.LOOP, "anchor": Vector2(116.0, 180.0),
	},
	# The leap. Ends on the frame before the paws land, so whatever plays it is expected
	# to put the fox down itself — the same contract as the old fox's "pounce".
	"pounce": {
		"frames": 8, "fps": 16.0, "art_scale": 1.0,
		"playback": Playback.ONESHOT, "anchor": Vector2(127.5, 182.0),
	},
	# On its back, kicking the ball. NOTE the ball is drawn into these frames: the
	# artist's fox layer carries a grey one, and here the fox is holding it, so it can't
	# be isolated out the way it is in the other three. It will fight the game's own ball.
	"play": {
		"frames": 27, "fps": 12.0, "art_scale": 1.0,
		"playback": Playback.PINGPONG, "anchor": Vector2(141.0, 150.0),
	},
}

## The art is drawn facing left, so flip_h is what points the fox right.
const ART_FACES := -1.0

## Physical pixels per design unit: the launcher renders 960x540 at 2x.
const DESIGN_TO_PHYSICAL := 2.0

## Draw every clip at exactly one art pixel per physical pixel — no scaling whatever.
## That is a node scale of 1/DESIGN_TO_PHYSICAL for any clip, since the scale is what
## turns texels into design units and the window then doubles them.
##
## A review aid, not the destination — the fox is not meant to ship at 1:1 (see above).
## It shows the frames exactly as drawn, with none of the art_scale compensation on top,
## which is how to see what the artist actually delivered and how the two tiers differ.
@export var one_to_one := false:
	set(value):
		one_to_one = value
		if _clip != "":
			_apply_clip_transform(_clip)

## Multiplies the clip's own art_scale. Keep art_scale * display_scale * 2 whole — see
## the filter note above.
@export var display_scale := 1.0:
	set(value):
		display_scale = value
		if _clip != "":
			_apply_clip_transform(_clip)

var _clip := ""
var _pingpong_reversing := false


func _ready() -> void:
	centered = false
	_ensure_frames()
	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)


## Build the frames if they aren't built yet.
##
## Called from everything public rather than only from _ready(), because a caller that
## adds this node and configures it in the same breath gets here first: _ready() has not
## run, sprite_frames is still null, and the clip it asked for silently doesn't exist.
func _ensure_frames() -> void:
	if sprite_frames == null:
		sprite_frames = _build_frames()


## Switch clips. Safe to call with the clip already playing — it's a no-op then, so
## callers don't have to track what's on screen.
func play_clip(clip: String) -> void:
	if not CLIPS.has(clip) or clip == _clip:
		return
	_ensure_frames()
	_clip = clip
	_pingpong_reversing = false
	_apply_clip_transform(clip)
	animation = clip
	frame = 0
	play(clip)


func current_clip() -> String:
	return _clip


func clip_names() -> Array:
	return CLIPS.keys()


func set_facing(direction: float) -> void:
	if absf(direction) > 0.01:
		flip_h = (direction < 0.0) != (ART_FACES < 0.0)


## The clip's drawn size on screen, in this node's parent's units. Callers size hit
## targets and windows off this rather than off the frame, which is mostly margin.
func drawn_size() -> Vector2:
	if _clip == "":
		return Vector2.ZERO
	_ensure_frames()
	var texture := sprite_frames.get_frame_texture(_clip, 0)
	if texture == null:
		return Vector2.ZERO
	return texture.get_size() * scale.abs()


## The largest any clip gets, which is what a window or a hit box should be sized to.
##
## Deliberately not drawn_size(): the clips differ in frame size (sleep is 178x134, play
## is 282x150), so sizing anything off the *current* clip makes the overlay window resize
## every time the fox lies down. This is stable for the life of the set.
func nominal_size() -> Vector2:
	_ensure_frames()
	var biggest := Vector2.ZERO
	for clip in CLIPS:
		var texture := sprite_frames.get_frame_texture(clip, 0)
		if texture == null:
			continue
		var spec: Dictionary = CLIPS[clip]
		var art: float = 1.0 / DESIGN_TO_PHYSICAL if one_to_one else float(spec["art_scale"])
		var size := texture.get_size() * (art * display_scale)
		biggest = Vector2(maxf(biggest.x, size.x), maxf(biggest.y, size.y))
	return biggest


## Stretch or squeeze one clip to last `seconds`, for a move that has to land in time
## with something else — the pounce, whose last frame has to arrive as the fox does.
## Survives set_liveliness(), which scales playback on top of this rather than replacing it.
func retime_clip(clip: String, seconds: float) -> void:
	_ensure_frames()
	if not CLIPS.has(clip) or sprite_frames == null:
		return
	var count := sprite_frames.get_frame_count(clip)
	if count <= 0:
		return
	sprite_frames.set_animation_speed(clip, float(count) / maxf(0.1, seconds))


## Undo a retime, putting the clip back to the frame rate the table gives it.
func reset_clip_timing(clip: String) -> void:
	_ensure_frames()
	if CLIPS.has(clip) and sprite_frames != null:
		sprite_frames.set_animation_speed(clip, float(CLIPS[clip]["fps"]))


func _apply_clip_transform(clip: String) -> void:
	var spec: Dictionary = CLIPS[clip]
	var art: float = 1.0 / DESIGN_TO_PHYSICAL if one_to_one else float(spec["art_scale"])
	scale = Vector2.ONE * (art * display_scale)
	# Negated because `offset` moves the texture, and we want the anchor to land on the
	# node's origin rather than the frame's top-left corner.
	offset = -(spec["anchor"] as Vector2)


func _on_animation_finished() -> void:
	if _clip == "":
		return
	if CLIPS[_clip]["playback"] == Playback.ONESHOT:
		clip_finished.emit(_clip)
		return
	if CLIPS[_clip]["playback"] != Playback.PINGPONG:
		return
	# A reversed playback emits animation_finished at the near end too, so the flag is
	# what tells the two ends of the swing apart.
	_pingpong_reversing = not _pingpong_reversing
	if _pingpong_reversing:
		play_backwards(_clip)
	else:
		play(_clip)


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	for clip in CLIPS:
		var spec: Dictionary = CLIPS[clip]
		frames.add_animation(clip)
		# Ping-pong turns itself around in animation_finished, and a one-shot reports there
		# that it's done. A looping animation never fires it, so only LOOP loops here.
		frames.set_animation_loop(clip, spec["playback"] == Playback.LOOP)
		frames.set_animation_speed(clip, spec["fps"])
		for i in range(1, int(spec["frames"]) + 1):
			var path := "%s%s/%03d.png" % [DIR, clip, i]
			if not ResourceLoader.exists(path):
				push_warning("FoxV2 frame missing: %s" % path)
				continue
			frames.add_frame(clip, load(path))
	if frames.has_animation("default"):
		frames.remove_animation("default")
	return frames
