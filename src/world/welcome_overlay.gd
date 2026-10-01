extends Control
class_name WelcomeOverlay

signal dismissed

const MODAL := preload("res://assets/onboarding/welcome/welcome_modal_full_rough.png")
const CALLOUT := preload("res://assets/onboarding/welcome/welcome_callout.png")
const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

const DESIGN_SIZE := Vector2(960.0, 540.0)
const MODAL_POS := Vector2(218.0, 63.0)
const CTA_RECT := Rect2(337.0, 399.0, 287.0, 62.0)
const CALLOUT_LEFT := Vector2(70.0, 446.0)
const CALLOUT_RIGHT := Vector2(750.0, 446.0)
const CALLOUT_WIDTH := 160.0

var _scrim: ColorRect
var _content: Control
var _fade: Tween


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	z_index = 130
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	_build()


func show_overlay() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	visible = true
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func hide_overlay() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fade.tween_callback(func() -> void: visible = false)


func dismiss() -> void:
	if not visible:
		return
	dismissed.emit()


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Color(0.13, 0.08, 0.06, 0.58)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content = Control.new()
	_content.position = Vector2.ZERO
	_content.size = DESIGN_SIZE
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	var modal := TextureRect.new()
	modal.texture = MODAL
	modal.position = MODAL_POS
	modal.size = MODAL.get_size()
	modal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	modal.stretch_mode = TextureRect.STRETCH_KEEP
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(modal)

	var cta := Button.new()
	cta.position = CTA_RECT.position
	cta.size = CTA_RECT.size
	cta.focus_mode = Control.FOCUS_NONE
	cta.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cta.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	cta.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	cta.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	cta.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cta.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	cta.pressed.connect(dismiss)
	_content.add_child(cta)

	_add_callout(CALLOUT_LEFT, "Customize your\nDen & Fox")
	_add_callout(CALLOUT_RIGHT, "Track Your\nStats")


func _add_callout(pos: Vector2, text: String) -> void:
	# Same nine-patch and text box as HintCallout: the art is 140px wide, which two
	# lines of copy don't fit, and its drawn body is only the top 53 of its 69 rows.
	var wrap := NinePatchRect.new()
	wrap.texture = CALLOUT
	wrap.patch_margin_left = HintCallout.PATCH_LEFT
	wrap.patch_margin_right = HintCallout.PATCH_RIGHT
	wrap.position = pos
	wrap.size = Vector2(CALLOUT_WIDTH, CALLOUT.get_height())
	wrap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(wrap)

	var label := Label.new()
	label.text = text
	label.position = HintCallout.TEXT_INSET
	label.size = Vector2(
		CALLOUT_WIDTH - HintCallout.TEXT_INSET.x - HintCallout.PATCH_RIGHT,
		HintCallout.BODY_HEIGHT - HintCallout.TEXT_INSET.y * 2.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("4a2a1e"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		dismiss()
		get_viewport().set_input_as_handled()
