extends Panel
class_name FoxSettingsPanel

## The settings panel builds its own controls in code and exposes them as members
## so the orchestrator (world.gd) can wire and read them. Keeping the layout here
## (rather than in the scene) makes it easy to add/remove rows.

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

const PANEL_BG := Color("2e1f14")
const PANEL_BORDER := Color("7a5230")
const HEADER := Color(1, 0.84, 0.64, 1)
const LABEL := Color(1, 0.83, 0.64, 0.92)
const HINT := Color(0.82, 0.72, 0.62, 0.78)

const LEFT := 24.0
const RIGHT := 360.0
const CTRL_X := 176.0

# Exposed controls
var close_button: Button
var scale_slider: HSlider
var opacity_slider: HSlider
var liveliness_slider: HSlider
var colour_option: OptionButton
var taskbar_snap_toggle: CheckButton
var taskbar_height_slider: HSlider
var focus_length_slider: HSlider
var short_length_slider: HSlider
var long_length_slider: HSlider
var focus_length_label: Label
var short_length_label: Label
var long_length_label: Label
var spawn_fox_button: Button
var hide_fox_button: Button
var reset_fox_button: Button
var reset_all_button: Button
var fox_status_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_box())
	_build()


func _build() -> void:
	_header("Settings", 14, 30)
	close_button = Button.new()
	close_button.text = "X"
	close_button.position = Vector2(322, 16)
	close_button.size = Vector2(38, 34)
	close_button.focus_mode = Control.FOCUS_NONE
	_font_on(close_button, 22)
	add_child(close_button)

	_header("Appearance", 50)
	_row_label("Fox size", 80)
	scale_slider = _hslider(82, 1.0, 4.0, 1.0, 2.0)
	_row_label("Opacity", 110)
	opacity_slider = _hslider(112, 0.35, 1.0, 0.01, 1.0)
	_row_label("Liveliness", 140)
	liveliness_slider = _hslider(142, 0.2, 2.0, 0.05, 1.0)
	_row_label("Fox colour", 170)
	colour_option = OptionButton.new()
	colour_option.position = Vector2(CTRL_X, 170)
	colour_option.size = Vector2(RIGHT - CTRL_X, 30)
	colour_option.focus_mode = Control.FOCUS_NONE
	_font_on(colour_option, 16)
	add_child(colour_option)

	_header("Behaviour", 206)
	taskbar_snap_toggle = CheckButton.new()
	taskbar_snap_toggle.text = "Rest on the taskbar"
	taskbar_snap_toggle.position = Vector2(LEFT, 234)
	taskbar_snap_toggle.size = Vector2(RIGHT - LEFT, 32)
	taskbar_snap_toggle.focus_mode = Control.FOCUS_NONE
	taskbar_snap_toggle.button_pressed = true
	taskbar_snap_toggle.add_theme_color_override("font_color", LABEL)
	_font_on(taskbar_snap_toggle, 18)
	add_child(taskbar_snap_toggle)
	_row_label("Taskbar height", 272)
	taskbar_height_slider = _hslider(274, -40.0, 120.0, 1.0, 24.0)

	_header("Session lengths", 300)
	focus_length_label = _row_label("Focus", 330)
	focus_length_slider = _hslider(332, 5.0, 60.0, 5.0, 25.0)
	short_length_label = _row_label("Short break", 358)
	short_length_slider = _hslider(360, 1.0, 30.0, 1.0, 5.0)
	long_length_label = _row_label("Long break", 386)
	long_length_slider = _hslider(388, 5.0, 45.0, 5.0, 15.0)

	_header("Your fox", 414)
	fox_status_label = Label.new()
	fox_status_label.text = "Fox: menu preview"
	fox_status_label.position = Vector2(180, 416)
	fox_status_label.size = Vector2(180, 22)
	fox_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fox_status_label.add_theme_color_override("font_color", LABEL)
	_font_on(fox_status_label, 16)
	add_child(fox_status_label)

	spawn_fox_button = _action_button("Spawn", LEFT, 444, 100)
	hide_fox_button = _action_button("Hide", 132, 444, 100)
	reset_fox_button = _action_button("Reset pos", 240, 444, 120)
	reset_all_button = _action_button("Reset all", LEFT, 478, 130)

	var hint := Label.new()
	hint.text = "Lower taskbar height lets the fox sit deeper on the edge."
	hint.position = Vector2(164, 476)
	hint.size = Vector2(196, 40)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", HINT)
	_font_on(hint, 13)
	add_child(hint)


# --- Builders --------------------------------------------------------------

func _header(text: String, y: float, fsize := 20) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(LEFT, y)
	lbl.size = Vector2(RIGHT - LEFT, fsize + 8)
	lbl.add_theme_color_override("font_color", HEADER)
	_font_on(lbl, fsize)
	add_child(lbl)


func _row_label(text: String, y: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(LEFT, y)
	lbl.size = Vector2(CTRL_X - LEFT - 6, 24)
	lbl.add_theme_color_override("font_color", LABEL)
	_font_on(lbl, 16)
	add_child(lbl)
	return lbl


func _hslider(y: float, mn: float, mx: float, step: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.position = Vector2(CTRL_X, y)
	s.size = Vector2(RIGHT - CTRL_X, 22)
	s.focus_mode = Control.FOCUS_NONE
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	add_child(s)
	return s


func _action_button(text: String, x: float, y: float, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, y)
	b.size = Vector2(w, 30)
	b.focus_mode = Control.FOCUS_NONE
	_font_on(b, 17)
	add_child(b)
	return b


func _font_on(c: Control, size: int) -> void:
	c.add_theme_font_override("font", FONT)
	c.add_theme_font_size_override("font_size", size)


func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(2)
	sb.border_color = PANEL_BORDER
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	return sb
