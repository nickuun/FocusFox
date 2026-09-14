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
## --- Why every clip carries its own scale ------------------------------------
##
## The clips came back from the artist at two different sizes. Measured two ways that
## agree — the height of the eye, and the thickness of the dark outline — they fall into
## two tiers:
##
##   outline 3px ("reference"): walk, sleep, and the older sitting-transition set
##   outline 2px (two-thirds):  sit, run
##
## So a fox that sat down and then walked off would visibly grow by half. The fix that
## costs nothing is to undo it on the way in: the small tier gets 1.5x and the reference
## tier 1x, which lands both on the same fox at the same size.
##
## Those look like a fractional scale on hard-edged art, which normally tears under the
## project's nearest filter (default_texture_filter=0). It doesn't here, because the
## launcher renders the 960x540 design space at 2x: what has to come out whole is the
## number of *physical* pixels per source texel, and that is art_scale * 2 — so 3 for the
## small tier and 2 for the reference tier. Both whole. Anything that changes the window
## scaling has to revisit this.
##
## This is a compensation, not a fix, and it buys size but not detail: scaling up adds no
## pixels, so "sit" at 1.5 is the same blocky fox as "sit" at 1.0, just bigger. Against a
## room background that is true 1:1 art, the fox reads coarser than the room it stands in.
##
## Where this is going: every clip redrawn so one art pixel is one physical pixel, which
## is a uniform art_scale of 0.5 (0.5 * 2 = 1) and no scaling at all. The target sizes and
## the checkable spec for them are in context/fox-art-spec.md. The on-screen size does not
## change — the art just gains the pixels it should have had — so nothing else moves when
## the new frames land. Landing them is: drop the frames in, set every art_scale to 0.5,
## re-measure ANCHOR (the canvases change), re-run the import pass.
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
}

const CLIPS := {
	# Sitting idle: a tail sweep with a blink in it. Despite the folder name it is not a
	# stand-to-sit transition — the fox is already seated in frame 1 and still seated in
	# frame 25 — so it is the clip to hold under a resting fox, not one to play into.
	# Ping-pong because its ends don't quite meet (a ~1.24x jump against the average
	# frame-to-frame change), and because a tail that sweeps out and back and eyes that
	# close and open again are what the pose wants anyway.
	"sit": {
		"frames": 25, "fps": 12.0, "art_scale": 1.5,
		"playback": Playback.PINGPONG, "anchor": Vector2(104.5, 132.0),
	},
	# A clean 12-frame cycle; its ends meet (0.89x), so it plain loops.
	"walk": {
		"frames": 12, "fps": 12.0, "art_scale": 1.0,
		"playback": Playback.LOOP, "anchor": Vector2(135.5, 178.0),
	},
	# NOTE: this one does not close — the last frame to the first is a 1.54x jump against
	# the average step, so a plain loop visibly hitches once a cycle. Ping-pong hides it,
	# but a run played backwards is wrong, so it loops and the hitch stands until the
	# cycle is redrawn. Not wired to anything yet for that reason.
	"run": {
		"frames": 20, "fps": 18.0, "art_scale": 1.5,
		"playback": Playback.LOOP, "anchor": Vector2(101.0, 129.0),
	},
	# Breathing, curled up. Ends meet (0.91x). Slow — 20 frames at 8fps is a 2.5s breath.
	"sleep": {
		"frames": 20, "fps": 8.0, "art_scale": 1.0,
		"playback": Playback.LOOP, "anchor": Vector2(97.0, 140.0),
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
## This is what the art is *for*: it shows the frames as drawn, with none of the
## art_scale compensation on top. Until the clips are redrawn at the target size it also
## shows how much smaller than intended they are — the same fox at a third (small tier)
## or a half (reference tier) of the size the room wants. See context/fox-art-spec.md.
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
	sprite_frames = _build_frames()
	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)


## Switch clips. Safe to call with the clip already playing — it's a no-op then, so
## callers don't have to track what's on screen.
func play_clip(clip: String) -> void:
	if not CLIPS.has(clip) or clip == _clip:
		return
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
	var texture := sprite_frames.get_frame_texture(_clip, 0)
	if texture == null:
		return Vector2.ZERO
	return texture.get_size() * scale.abs()


func _apply_clip_transform(clip: String) -> void:
	var spec: Dictionary = CLIPS[clip]
	var art: float = 1.0 / DESIGN_TO_PHYSICAL if one_to_one else float(spec["art_scale"])
	scale = Vector2.ONE * (art * display_scale)
	# Negated because `offset` moves the texture, and we want the anchor to land on the
	# node's origin rather than the frame's top-left corner.
	offset = -(spec["anchor"] as Vector2)


func _on_animation_finished() -> void:
	if _clip == "" or CLIPS[_clip]["playback"] != Playback.PINGPONG:
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
		# Ping-pong turns itself around in animation_finished, which a looping animation
		# never fires, so those clips must be non-looping here.
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
