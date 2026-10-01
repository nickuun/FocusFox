extends Control
class_name HintCallout

## A one-line-of-advice bubble for first-time moments the welcome card is too early to
## explain — the launcher tucking itself away, coming back, surviving its own close
## button. One instance, reused: pop() replaces whatever it was saying.
##
## Placeholder art: this stretches the welcome callout sideways as a nine-patch. The
## tail lives in the left margin, so it survives any width — but not a taller bubble,
## which is why the height stays native and the copy has to fit two lines.

## Emitted once per pop(), however it ends: timed out, clicked, or cut short by
## close(). `clicked` is true only for a click, so callers can treat it as "got it".
signal closed(clicked: bool)

const ART := preload("res://assets/onboarding/welcome/welcome_callout.png")
const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

## The art's 69px canvas has transparent rows under the bubble; the drawn body is the
## top 53. Text is placed inside the body, not the canvas.
const BODY_HEIGHT := 53.0
## Covers the tail (it reaches 5px in, and its outline runs to x=17) plus the corner.
const PATCH_LEFT := 24
const PATCH_RIGHT := 12
const TEXT_INSET := Vector2(22.0, 8.0)
const FADE_IN := 0.18
const FADE_OUT := 0.14
const HOVER_TINT := Color(1.06, 1.06, 1.06)

## What the current bubble is about, so a caller can close only its own.
var purpose := ""

var _art: NinePatchRect
var _label: Label
var _fade: Tween
var _hold_token := 0
var _open := false


func _ready() -> void:
	# Over the journal (80) and its icon (100), under the settings scrim (110).
	z_index = 105
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visible = false
	modulate.a = 0.0
	size = ART.get_size()

	_art = NinePatchRect.new()
	_art.texture = ART
	_art.patch_margin_left = PATCH_LEFT
	_art.patch_margin_right = PATCH_RIGHT
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("4a2a1e"))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	mouse_entered.connect(func() -> void: _art.self_modulate = HOVER_TINT)
	mouse_exited.connect(func() -> void: _art.self_modulate = Color.WHITE)


## Shows `text` at `at` (design-space top-left of the canvas, tail pointing left) for
## `hold` seconds. Await `closed` to find out how it ended.
func pop(what: String, text: String, at: Vector2, width: float, hold: float) -> void:
	if _open:
		_finish(false)
	purpose = what
	_open = true
	position = at
	size = Vector2(width, ART.get_height())
	_art.size = size
	# Width before text, then size again after: a wrapping Label measures new text at
	# its current width, and a narrow one grows to a column of single words that
	# setting the size afterwards can't shrink — centring the copy far below the bubble.
	var text_size := Vector2(width - TEXT_INSET.x - PATCH_RIGHT, BODY_HEIGHT - TEXT_INSET.y * 2.0)
	_label.text = ""
	_label.position = TEXT_INSET
	_label.size = text_size
	_label.text = text
	_label.size = text_size
	_art.self_modulate = Color.WHITE

	if _fade != null and _fade.is_valid():
		_fade.kill()
	visible = true
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_hold_token += 1
	var token := _hold_token
	await get_tree().create_timer(hold).timeout
	if token == _hold_token and _open:
		_finish(false)


func is_open() -> bool:
	return _open


## Cuts the bubble short. Only closes it if it's still saying `what`, so one moment
## can't dismiss another's bubble by accident; "" closes whatever is showing.
func close(what := "") -> void:
	if _open and (what == "" or what == purpose):
		_finish(false)


func _gui_input(event: InputEvent) -> void:
	if _open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_finish(true)


func _finish(clicked: bool) -> void:
	_open = false
	_hold_token += 1
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fade.tween_callback(func() -> void:
		if not _open:
			visible = false)
	closed.emit(clicked)
