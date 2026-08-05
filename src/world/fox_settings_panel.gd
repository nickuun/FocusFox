extends Panel
class_name FoxSettingsPanel

## The settings panel builds its own controls in code and exposes them as members
## so the orchestrator (world.gd) can wire and read them.
##
## Layout is a left rail of tabs plus a content pane, both drawn from art in
## assets/settings. Everything is laid out in absolute coordinates at the art's
## native pixel size — PANEL_SIZE is exactly the two background images side by
## side, and the menu's design viewport is 1:1 with those pixels, so nothing here
## gets resampled. Keep new rows on the ROW_H rhythm and they'll line up.
##
## Each tab is a page Control holding its own rows; switching tabs just toggles
## visibility. Rows that carry a number own a value pill: the -/+ buttons nudge
## the row's slider, and the pill text is formatted here from the slider's value,
## so world.gd only ever has to listen to the slider.

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")
const FOX_SCENE: PackedScene = preload("res://src/planetoid/planetoid.tscn")

const RAIL_BG := preload("res://assets/settings/Menu Settings_Side Panel_Background.png")
const CONTENT_BG := preload("res://assets/settings/Menu Controls_Background4.png")
const DIVIDER := preload("res://assets/settings/Menu Settings_Divider.png")
const TAB_BG := preload("res://assets/settings/buttons/Menu Settings_Side Panel_Button.png")
const WOOD_BUTTON := preload("res://assets/settings/buttons/wooden button.png")
const VALUE_PILL := preload("res://assets/settings/number display/value adjustor +-.png")
const SLIDER_EMPTY_TEXTURE := preload("res://assets/settings/slider/Empty Slider.png")
const SLIDER_FULL_TEXTURE := preload("res://assets/settings/slider/Full Slider.png")
const SLIDER_GRABBER_TEXTURE := preload("res://assets/settings/slider/Nodge.png")
const TOGGLE_DISABLED_TEXTURE := preload("res://assets/settings/toggle buttons/Dark Outline Disabled.png")
const TOGGLE_ENABLED_TEXTURE := preload("res://assets/settings/toggle buttons/Dark Outline Enabled.png")
const EXIT_BUTTON_TEXTURE := preload("res://assets/settings/exit/Exit Button.png")

const ICON_TIMER := preload("res://assets/settings/icons/Menu Settings_Side Panel_Clock Icon.png")
const ICON_SOUND := preload("res://assets/settings/icons/Menu Settings_Side Panel_Sound Icon.png")
const ICON_FOX := preload("res://assets/settings/icons/Menu Settings_Side Panel_Fox Icon.png")
const ICON_DATA := preload("res://assets/settings/icons/Menu Settings_Side Panel_Lock Icon.png")

# Sampled from the art so text and dividers sit in the same family as the panels.
const TITLE_COLOR := Color("4a3222")
const LABEL_COLOR := Color("5c4130")
const HINT_COLOR := Color("8a705c")
const WOOD_TEXT := Color("fdf3e3")
const DANGER := Color("b3402f")
const TAB_TEXT := Color("5c4130")
const TAB_TEXT_ON := Color("3f2a1c")

## The two backgrounds side by side, less the overlap. The design viewport matches
## this 1:1. The rail is drawn last and sits a few pixels over the content panel so
## its dark border hides the content art's light left edge — butted flush they leave
## a pale seam down the join.
const RAIL_W := 187.0
const RAIL_OVERLAP := 6.0
const CONTENT_X := RAIL_W - RAIL_OVERLAP
const PANEL_SIZE := Vector2(CONTENT_X + 569.0, 420.0)
const PAD := 22.0
const CONTENT_LEFT := CONTENT_X + PAD
const CONTENT_RIGHT := PANEL_SIZE.x - PAD

# Tab rail. The rail art's baked-in "Focus Fox" header ends around y=64.
const TAB_X := 15.0
const TAB_W := 157.0
const TAB_H := 38.0
const TAB_TOP := 80.0
const TAB_STEP := 48.0

# Content rows.
const ROW_H := 40.0
const ROWS_TOP := 96.0
const LABEL_W := 136.0
const SLIDER_X := 352.0
const SLIDER_W := 232.0
const PILL_X := 596.0
const PILL_W := 96.0
const PILL_H := 23.0
const UNIT_X := 700.0
const HAIRLINE_H := 3.0
## The -/+ glyphs sit low in the pill left to their own devices, because the pixel
## font reserves descender room the digits never use. Nudge them back up.
const STEPPER_RISE := 3.0

# Fox preview box on the Fox tab.
const PREVIEW_BOX := Vector2(104.0, 104.0)
## Rendered size the fox is scaled to inside the box, whatever the player's fox size
## is set to. Leaves room for the click pulse to squash without clipping.
const PREVIEW_FOX_PX := 82.0
## Where the fox actually sits inside its sprite frame, measured off the idle row of
## assets/fox/Fox Sprite Sheet.png. It stands on the frame's bottom edge with a lot of
## headroom above, so centring and scaling the *frame* leaves the fox low in the box
## and looking half the size it should. fit_preview() works off the content instead.
const FOX_FRAME_PX := 32.0
const FOX_CONTENT_RECT := Rect2(6.0, 17.0, 20.0, 15.0)

# Exposed controls — world.gd wires and reads these.
var close_button: BaseButton
var scale_slider: HSlider
var opacity_slider: HSlider
var liveliness_slider: HSlider
var colour_option: OptionButton
var sit_height_slider: HSlider
var focus_length_slider: HSlider
var short_length_slider: HSlider
var long_length_slider: HSlider
var mute_toggle: BaseButton
var volume_slider: HSlider
var ambience_slider: HSlider
var spawn_fox_button: BaseButton
var hide_fox_button: BaseButton
var reset_fox_button: BaseButton
var reset_all_button: BaseButton
var reset_data_button: BaseButton
var fox_status_label: Label
## Lives on the Fox tab. World applies the same cosmetics to it as to the menu's
## preview fox, then calls fit_preview() so the box scale keeps up.
var preview_fox: RigidBody2D

var _preview_holder: Node2D

var _host: Control                  # page the builders add to
var _pages: Array[Control] = []
var _tab_highlights: Array[TextureRect] = []
var _tab_labels: Array[Label] = []
var _active_tab := 0


func _ready() -> void:
	# The art is the background; the Panel itself draws nothing.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	size = PANEL_SIZE
	_build()
	_select_tab(0)


func _build() -> void:
	_texture(self, CONTENT_BG, Vector2(CONTENT_X, 0.0))
	_texture(self, RAIL_BG, Vector2.ZERO)

	close_button = TextureButton.new()
	close_button.texture_normal = EXIT_BUTTON_TEXTURE
	close_button.texture_pressed = EXIT_BUTTON_TEXTURE
	close_button.texture_hover = EXIT_BUTTON_TEXTURE
	close_button.position = Vector2(PANEL_SIZE.x - 58.0, 8.0)
	close_button.size = Vector2(50, 50)
	close_button.focus_mode = Control.FOCUS_NONE
	add_child(close_button)

	_build_tab(0, ICON_TIMER, "Timer")
	_build_tab(1, ICON_SOUND, "Sound")
	_build_tab(2, ICON_FOX, "Fox")
	_build_tab(3, ICON_DATA, "Data")

	_build_timer_page()
	_build_sound_page()
	_build_fox_page()
	_build_data_page()


# --- Tab rail --------------------------------------------------------------

func _build_tab(index: int, icon: Texture2D, text: String) -> void:
	var y := TAB_TOP + TAB_STEP * float(index)

	# The light wooden plate only shows on the active tab; the others read as bare rail.
	var highlight := TextureRect.new()
	highlight.texture = TAB_BG
	highlight.position = Vector2(TAB_X, y)
	highlight.size = Vector2(TAB_W, TAB_H)
	highlight.stretch_mode = TextureRect.STRETCH_SCALE
	highlight.visible = false
	add_child(highlight)
	_tab_highlights.append(highlight)

	_texture(self, icon, Vector2(TAB_X + 10.0, y + 1.0))

	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(TAB_X + 54.0, y)
	lbl.size = Vector2(TAB_W - 60.0, TAB_H)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", TAB_TEXT)
	_font_on(lbl, 18)
	add_child(lbl)
	_tab_labels.append(lbl)

	if index < 3:
		var div := _nine_patch(DIVIDER, 8)
		div.position = Vector2(13.0, y + TAB_H + 5.0)
		div.size = Vector2(162, DIVIDER.get_height())
		add_child(div)

	var hit := Button.new()
	hit.flat = true
	hit.position = Vector2(TAB_X, y)
	hit.size = Vector2(TAB_W, TAB_H)
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(_on_tab_pressed.bind(index))
	add_child(hit)


func _on_tab_pressed(index: int) -> void:
	if index == _active_tab:
		return
	Audio.play("click")
	_select_tab(index)


func _select_tab(index: int) -> void:
	_active_tab = index
	for i in _pages.size():
		_pages[i].visible = i == index
	for i in _tab_highlights.size():
		_tab_highlights[i].visible = i == index
		_tab_labels[i].add_theme_color_override("font_color", TAB_TEXT_ON if i == index else TAB_TEXT)


## Reopening the panel should land on the first tab rather than wherever you left off.
func reset_to_first_tab() -> void:
	_select_tab(0)


# --- Pages -----------------------------------------------------------------

func _new_page(icon: Texture2D, title: String, subtitle: String) -> Control:
	var page := Control.new()
	page.name = title
	page.position = Vector2.ZERO
	page.size = PANEL_SIZE
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	_pages.append(page)
	_host = page

	_texture(page, icon, Vector2(CONTENT_LEFT, 24.0))

	var head := Label.new()
	head.text = title
	head.position = Vector2(CONTENT_LEFT + 46.0, 20.0)
	head.size = Vector2(300, 26)
	head.add_theme_color_override("font_color", TITLE_COLOR)
	_font_on(head, 22)
	page.add_child(head)

	var sub := Label.new()
	sub.text = subtitle
	sub.position = Vector2(CONTENT_LEFT + 46.0, 47.0)
	sub.size = Vector2(400, 20)
	sub.add_theme_color_override("font_color", HINT_COLOR)
	_font_on(sub, 15)
	page.add_child(sub)

	var div := _hairline()
	div.position = Vector2(CONTENT_LEFT, 76.0)
	div.size = Vector2(CONTENT_RIGHT - CONTENT_LEFT, HAIRLINE_H)
	page.add_child(div)

	return page


func _build_timer_page() -> void:
	_new_page(ICON_TIMER, "Timer", "Customize your focus and break lengths.")
	focus_length_slider = _slider_row("Focus length", 0, 5.0, 60.0, 5.0, 25.0, "min")
	short_length_slider = _slider_row("Short break", 1, 1.0, 30.0, 1.0, 5.0, "min")
	long_length_slider = _slider_row("Long break", 2, 5.0, 45.0, 5.0, 15.0, "min")


func _build_sound_page() -> void:
	_new_page(ICON_SOUND, "Sound", "Adjust the cozy ambience and audio.")
	mute_toggle = _switch_row("Mute all sound", 0, "Silence all audio and ambience")
	volume_slider = _slider_row("Master volume", 1, 0.0, 1.0, 0.05, 0.8, "", "pct", false)
	ambience_slider = _slider_row("Ambience", 2, 0.0, 1.0, 0.05, 0.45, "", "pct", false)


func _build_fox_page() -> void:
	var page := _new_page(ICON_FOX, "Fox", "Manage your little companion.")
	scale_slider = _slider_row("Fox size", 0, 1.0, 4.0, 1.0, 2.0)
	opacity_slider = _slider_row("Opacity", 1, 0.35, 1.0, 0.01, 1.0, "", "pct")
	liveliness_slider = _slider_row("Liveliness", 2, 0.2, 2.0, 0.05, 1.0, "", "mult")
	sit_height_slider = _slider_row("Sit height", 3, 0.0, 200.0, 1.0, 48.0, "px")

	_row_label("Fox colour", 4)
	colour_option = OptionButton.new()
	colour_option.position = Vector2(SLIDER_X, _row_y(4) - 3.0)
	colour_option.size = Vector2(SLIDER_W, 30)
	colour_option.focus_mode = Control.FOCUS_NONE
	colour_option.add_theme_color_override("font_color", WOOD_TEXT)
	colour_option.add_theme_color_override("font_hover_color", WOOD_TEXT)
	colour_option.add_theme_color_override("font_pressed_color", WOOD_TEXT)
	colour_option.add_theme_color_override("font_focus_color", WOOD_TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		colour_option.add_theme_stylebox_override(state, _wood_box())
	_font_on(colour_option, 16)
	page.add_child(colour_option)

	# The preview sits to the right of the colour row and the buttons, which is why
	# those two are kept narrower than the slider rows above them.
	_build_preview(page, Vector2(CONTENT_RIGHT - PREVIEW_BOX.x - 14.0, _row_y(4) - 6.0))

	var buttons_y := _row_y(5) + 4.0
	spawn_fox_button = _wood_button("Spawn", CONTENT_LEFT, buttons_y, 112.0)
	hide_fox_button = _wood_button("Bring Fox Home", CONTENT_LEFT + 120.0, buttons_y, 172.0)
	reset_fox_button = _wood_button("Reset Position", CONTENT_LEFT, buttons_y + 38.0, 160.0)

	fox_status_label = Label.new()
	fox_status_label.text = "Fox: menu preview"
	fox_status_label.position = Vector2(CONTENT_LEFT + 170.0, buttons_y + 44.0)
	fox_status_label.size = Vector2(200, 20)
	fox_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fox_status_label.add_theme_color_override("font_color", HINT_COLOR)
	_font_on(fox_status_label, 15)
	page.add_child(fox_status_label)


## A framed live fox showing the player's current colour, size and opacity.
func _build_preview(page: Control, at: Vector2) -> void:
	var frame := Panel.new()
	frame.position = at
	frame.size = PREVIEW_BOX
	frame.add_theme_stylebox_override("panel", _preview_box())
	# The click pulse scales the fox up briefly; clipping keeps it inside the frame.
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(frame)

	# The fox sprite is baked at 5x and apply_cosmetics_to() multiplies that by the
	# player's fox size on top, so it arrives far too big for a 104px box. The holder
	# divides all of that back out and re-centres it — see fit_preview().
	_preview_holder = Node2D.new()
	frame.add_child(_preview_holder)

	preview_fox = FOX_SCENE.instantiate() as RigidBody2D
	preview_fox.freeze = true
	_preview_holder.add_child(preview_fox)
	fit_preview()

	var pet := Button.new()
	pet.flat = true
	pet.position = at
	pet.size = PREVIEW_BOX
	pet.focus_mode = Control.FOCUS_NONE
	pet.tooltip_text = "Boop"
	pet.pressed.connect(_on_preview_pressed)
	page.add_child(pet)


## Rescales and re-centres the preview so the fox fills the box at any fox size
## setting. Call after anything that changes the fox's body scale.
func fit_preview() -> void:
	if not is_instance_valid(preview_fox) or not is_instance_valid(_preview_holder):
		return
	var footprint := 160.0
	if preview_fox.has_method("get_sprite_pixel_size"):
		var measured: Variant = preview_fox.call("get_sprite_pixel_size")
		if measured is Vector2 and (measured as Vector2).x > 0.0:
			footprint = (measured as Vector2).x
	# get_sprite_pixel_size() deliberately excludes the body scale, so fold it in.
	footprint *= maxf(0.01, absf(preview_fox.scale.x))

	var per_frame_px := footprint / FOX_FRAME_PX
	var content_px := maxf(FOX_CONTENT_RECT.size.x, FOX_CONTENT_RECT.size.y) * per_frame_px
	var fit := PREVIEW_FOX_PX / maxf(1.0, content_px)
	_preview_holder.scale = Vector2.ONE * fit
	# The body's origin is the frame's centre, not the fox's, so shift the holder by
	# the gap between the two — otherwise the fox hangs off the bottom of the box.
	var off := (FOX_CONTENT_RECT.get_center() - Vector2.ONE * FOX_FRAME_PX * 0.5) * per_frame_px
	_preview_holder.position = PREVIEW_BOX * 0.5 - off * fit


func _on_preview_pressed() -> void:
	if is_instance_valid(preview_fox):
		preview_fox.call("pulse_click")
	Audio.play("click")


func _preview_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f1dcb8")
	sb.set_border_width_all(2)
	sb.border_color = Color("c8a06a")
	sb.set_corner_radius_all(8)
	return sb


func _build_data_page() -> void:
	var page := _new_page(ICON_DATA, "Data", "Manage your local data and preferences.")

	reset_all_button = _wood_button("Reset Settings", CONTENT_LEFT, ROWS_TOP, 200.0)
	_hint("Restore all settings to default", CONTENT_LEFT, ROWS_TOP + 34.0)

	reset_data_button = _wood_button("Reset Game Data", CONTENT_LEFT, ROWS_TOP + 66.0, 200.0)
	# Red on the wooden button is close to unreadable, so the warning lives in the
	# hint underneath and the button itself just gets a warmer tint.
	reset_data_button.self_modulate = Color(1.12, 0.82, 0.74)
	_hint("This will reset all progress", CONTENT_LEFT, ROWS_TOP + 100.0).add_theme_color_override("font_color", DANGER)

	var note := Label.new()
	note.text = "All data is stored locally on your device.\nYou're in control."
	note.position = Vector2(CONTENT_LEFT, ROWS_TOP + 150.0)
	note.size = Vector2(CONTENT_RIGHT - CONTENT_LEFT, 48)
	note.add_theme_color_override("font_color", HINT_COLOR)
	_font_on(note, 15)
	page.add_child(note)


# --- Row builders ----------------------------------------------------------

func _row_y(index: int) -> float:
	return ROWS_TOP + ROW_H * float(index)


## A label, a slider, and a value pill. `unit` is drawn after the pill ("min", "px");
## `fmt` picks how the number reads. `steppers` adds the pill's -/+ nudge buttons.
func _slider_row(text: String, index: int, mn: float, mx: float, step: float, val: float,
		unit := "", fmt := "int", steppers := true) -> HSlider:
	var y := _row_y(index)
	_row_label(text, index)

	var slider := HSlider.new()
	slider.position = Vector2(SLIDER_X, y)
	slider.size = Vector2(SLIDER_W, 24)
	slider.custom_minimum_size = Vector2(0, 24)
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.value = val
	slider.scrollable = false
	slider.add_theme_stylebox_override("slider", _slider_box(SLIDER_EMPTY_TEXTURE))
	slider.add_theme_stylebox_override("grabber_area", _slider_box(SLIDER_FULL_TEXTURE))
	slider.add_theme_stylebox_override("grabber_area_highlight", _slider_box(SLIDER_FULL_TEXTURE))
	slider.add_theme_icon_override("grabber", SLIDER_GRABBER_TEXTURE)
	slider.add_theme_icon_override("grabber_highlight", SLIDER_GRABBER_TEXTURE)
	slider.add_theme_icon_override("grabber_disabled", SLIDER_GRABBER_TEXTURE)
	_host.add_child(slider)

	var pill := _nine_patch(VALUE_PILL, 10)
	pill.position = Vector2(PILL_X, y + (24.0 - PILL_H) * 0.5)
	pill.size = Vector2(PILL_W, PILL_H)
	_host.add_child(pill)

	var value := Label.new()
	value.position = Vector2(PILL_X + (22.0 if steppers else 0.0), pill.position.y)
	value.size = Vector2(PILL_W - (44.0 if steppers else 0.0), PILL_H)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color", TITLE_COLOR)
	_font_on(value, 16)
	_host.add_child(value)

	if steppers:
		var stepper_y := pill.position.y - STEPPER_RISE
		_stepper("-", PILL_X + 2.0, stepper_y, slider, -step)
		_stepper("+", PILL_X + PILL_W - 24.0, stepper_y, slider, step)

	# The pill is the slider's readout, so it stays in step without world.gd's help.
	slider.value_changed.connect(func(v: float) -> void: value.text = _format_value(v, fmt))
	value.text = _format_value(val, fmt)

	if unit != "":
		var unit_label := Label.new()
		unit_label.text = unit
		unit_label.position = Vector2(UNIT_X, y)
		unit_label.size = Vector2(CONTENT_RIGHT - UNIT_X, 24)
		unit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		unit_label.add_theme_color_override("font_color", HINT_COLOR)
		_font_on(unit_label, 15)
		_host.add_child(unit_label)

	return slider


func _format_value(v: float, fmt: String) -> String:
	match fmt:
		"pct":
			return "%d%%" % int(round(v * 100.0))
		"mult":
			return "%.1f" % v
		_:
			return str(int(round(v)))


func _stepper(text: String, x: float, y: float, slider: HSlider, delta: float) -> void:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.position = Vector2(x, y)
	b.size = Vector2(22, PILL_H)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", LABEL_COLOR)
	b.add_theme_color_override("font_hover_color", TITLE_COLOR)
	b.add_theme_color_override("font_pressed_color", TITLE_COLOR)
	_font_on(b, 18)
	# set_value_no_signal would skip world.gd's listener, so nudge the value for real.
	b.pressed.connect(func() -> void: slider.value = clampf(slider.value + delta, slider.min_value, slider.max_value))
	_host.add_child(b)


## A label, a hint, and the toggle art pinned to the right of the row.
func _switch_row(text: String, index: int, hint := "") -> BaseButton:
	var y := _row_y(index)
	_row_label(text, index)

	if hint != "":
		_hint(hint, SLIDER_X, y + 3.0)

	var t := TextureButton.new()
	t.toggle_mode = true
	t.texture_normal = TOGGLE_DISABLED_TEXTURE
	t.texture_pressed = TOGGLE_ENABLED_TEXTURE
	t.texture_hover = TOGGLE_DISABLED_TEXTURE
	t.position = Vector2(CONTENT_RIGHT - float(TOGGLE_ENABLED_TEXTURE.get_width()), y)
	t.size = Vector2(TOGGLE_ENABLED_TEXTURE.get_width(), TOGGLE_ENABLED_TEXTURE.get_height())
	t.focus_mode = Control.FOCUS_NONE
	_host.add_child(t)
	return t


func _row_label(text: String, index: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(CONTENT_LEFT, _row_y(index))
	lbl.size = Vector2(LABEL_W, 24)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	_font_on(lbl, 17)
	_host.add_child(lbl)
	return lbl


func _hint(text: String, x: float, y: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(CONTENT_RIGHT - x, 20)
	lbl.add_theme_color_override("font_color", HINT_COLOR)
	_font_on(lbl, 15)
	_host.add_child(lbl)
	return lbl


func _wood_button(text: String, x: float, y: float, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, y)
	b.size = Vector2(w, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", WOOD_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", WOOD_TEXT)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, _wood_box())
	_font_on(b, 16)
	_host.add_child(b)
	return b


# --- Art helpers -----------------------------------------------------------

func _texture(parent: Node, texture: Texture2D, at: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = texture
	tr.position = at
	tr.size = texture.get_size()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr


## Pixel art stretched along one axis smears its rounded ends, so anything that
## has to change width (dividers, pills) keeps its caps intact with a 3-slice.
func _nine_patch(texture: Texture2D, cap: int) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = texture
	np.patch_margin_left = cap
	np.patch_margin_right = cap
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


## The divider art is a chunky 11px wooden strip. That reads well at the rail's
## 162px, but stretched the full width of the content pane it dominates the page —
## so section rules take just the darker core rows out of it as a hairline.
func _hairline() -> NinePatchRect:
	var np := _nine_patch(DIVIDER, 8)
	np.region_rect = Rect2(0.0, 5.0, float(DIVIDER.get_width()), HAIRLINE_H)
	return np


func _wood_box() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = WOOD_BUTTON
	sb.texture_margin_left = 12
	sb.texture_margin_right = 12
	sb.texture_margin_top = 6
	sb.texture_margin_bottom = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


func _slider_box(texture: Texture2D) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture
	sb.texture_margin_left = 6
	sb.texture_margin_right = 6
	sb.content_margin_top = texture.get_height()
	sb.content_margin_bottom = 0
	return sb


func _font_on(c: Control, size: int) -> void:
	c.add_theme_font_override("font", FONT)
	c.add_theme_font_size_override("font_size", size)
