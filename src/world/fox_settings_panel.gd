extends Panel
class_name FoxSettingsPanel

## The settings panel builds its own controls in code and exposes them as members
## so the orchestrator (world.gd) can wire and read them. The body scrolls, so we
## can keep adding rows without running out of vertical room.

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

const PANEL_BG := Color("2e1f14")
const PANEL_BORDER := Color("7a5230")
const HEADER := Color(1, 0.84, 0.64, 1)
const LABEL := Color(1, 0.83, 0.64, 0.92)
const HINT := Color(0.82, 0.72, 0.62, 0.78)
const DANGER := Color(1, 0.6, 0.5, 1)

const LEFT := 24.0
const RIGHT := 348.0
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
var mute_toggle: CheckButton
var volume_slider: HSlider
var spawn_fox_button: Button
var hide_fox_button: Button
var reset_fox_button: Button
var reset_all_button: Button
var reset_data_button: Button
var fox_status_label: Label

var _host: Control


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_box())
	_build()


func _build() -> void:
	# Fixed title bar (outside the scroll area).
	_host = self
	_header("Settings", 14, 30)
	close_button = Button.new()
	close_button.text = "X"
	close_button.position = Vector2(310, 16)
	close_button.size = Vector2(38, 34)
	close_button.focus_mode = Control.FOCUS_NONE
	_font_on(close_button, 22)
	add_child(close_button)

	# Scrolling body.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 52)
	scroll.size = Vector2(374, 450)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(360, 660)
	scroll.add_child(content)
	_host = content

	_header("Appearance", 8)
	_row_label("Fox size", 38)
	scale_slider = _hslider(40, 1.0, 4.0, 1.0, 2.0)
	_row_label("Opacity", 66)
	opacity_slider = _hslider(68, 0.35, 1.0, 0.01, 1.0)
	_row_label("Liveliness", 94)
	liveliness_slider = _hslider(96, 0.2, 2.0, 0.05, 1.0)
	_row_label("Fox colour", 122)
	colour_option = OptionButton.new()
	colour_option.position = Vector2(CTRL_X, 122)
	colour_option.size = Vector2(RIGHT - CTRL_X, 30)
	colour_option.focus_mode = Control.FOCUS_NONE
	_font_on(colour_option, 16)
	_host.add_child(colour_option)

	_header("Behaviour", 160)
	taskbar_snap_toggle = _toggle("Rest on the taskbar", 190)
	taskbar_snap_toggle.button_pressed = true
	_row_label("Sit depth", 226)
	taskbar_height_slider = _hslider(228, -20.0, 40.0, 1.0, 0.0)

	_header("Session lengths", 258)
	focus_length_label = _row_label("Focus", 288)
	focus_length_slider = _hslider(290, 5.0, 60.0, 5.0, 25.0)
	short_length_label = _row_label("Short break", 316)
	short_length_slider = _hslider(318, 1.0, 30.0, 1.0, 5.0)
	long_length_label = _row_label("Long break", 344)
	long_length_slider = _hslider(346, 5.0, 45.0, 5.0, 15.0)

	_header("Sound", 378)
	mute_toggle = _toggle("Mute all sound", 408)
	_row_label("Volume", 444)
	volume_slider = _hslider(446, 0.0, 1.0, 0.05, 0.8)

	_header("Your fox", 478)
	fox_status_label = Label.new()
	fox_status_label.text = "Fox: menu preview"
	fox_status_label.position = Vector2(180, 480)
	fox_status_label.size = Vector2(168, 22)
	fox_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fox_status_label.add_theme_color_override("font_color", LABEL)
	_font_on(fox_status_label, 16)
	_host.add_child(fox_status_label)
	spawn_fox_button = _action_button("Spawn", LEFT, 508, 100)
	hide_fox_button = _action_button("Hide", 132, 508, 96)
	reset_fox_button = _action_button("Reset pos", 236, 508, 112)
	reset_all_button = _action_button("Reset settings", LEFT, 544, 150)

	_header("Data", 584)
	reset_data_button = _action_button("Reset game data", LEFT, 614, RIGHT - LEFT)
	reset_data_button.add_theme_color_override("font_color", DANGER)


# --- Builders --------------------------------------------------------------

func _header(text: String, y: float, fsize := 20) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(LEFT, y)
	lbl.size = Vector2(RIGHT - LEFT, fsize + 8)
	lbl.add_theme_color_override("font_color", HEADER)
	_font_on(lbl, fsize)
	_host.add_child(lbl)


func _row_label(text: String, y: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(LEFT, y)
	lbl.size = Vector2(CTRL_X - LEFT - 6, 24)
	lbl.add_theme_color_override("font_color", LABEL)
	_font_on(lbl, 16)
	_host.add_child(lbl)
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
	_host.add_child(s)
	return s


func _toggle(text: String, y: float) -> CheckButton:
	var t := CheckButton.new()
	t.text = text
	t.position = Vector2(LEFT, y)
	t.size = Vector2(RIGHT - LEFT, 32)
	t.focus_mode = Control.FOCUS_NONE
	t.add_theme_color_override("font_color", LABEL)
	_font_on(t, 18)
	_host.add_child(t)
	return t


func _action_button(text: String, x: float, y: float, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, y)
	b.size = Vector2(w, 30)
	b.focus_mode = Control.FOCUS_NONE
	_font_on(b, 17)
	_host.add_child(b)
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
