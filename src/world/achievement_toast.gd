extends CanvasLayer

## AchievementToast — animated slide-in notification for unlocked achievements.
##
## Add this node to the main World scene. It listens to
## Achievements.achievement_unlocked and queues popups so back-to-back unlocks
## don't overlap.

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

const SLIDE_IN_DURATION  := 0.35
const HOLD_DURATION      := 3.0
const SLIDE_OUT_DURATION := 0.4
const PANEL_WIDTH        := 320.0
const PANEL_HEIGHT       := 64.0
const MARGIN             := 16.0

# Queue of {id, def} dicts waiting to be shown.
var _queue: Array = []
var _showing := false

# Live nodes for the current toast.
var _panel: Panel
var _icon_label: Label   # 🦊 emoji stand-in until per-achievement icons are added
var _title_label: Label
var _desc_label: Label
var _tween: Tween


func _ready() -> void:
	layer = 128  # always on top of game UI
	Achievements.achievement_unlocked.connect(_on_achievement_unlocked)
	_build_panel()


# ---------------------------------------------------------------------------
# Signal handler
# ---------------------------------------------------------------------------

func _on_achievement_unlocked(id: String, def: Dictionary) -> void:
	_queue.append({"id": id, "def": def})
	if not _showing:
		_show_next()


# ---------------------------------------------------------------------------
# Display logic
# ---------------------------------------------------------------------------

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var entry: Dictionary = _queue.pop_front()
	_populate(entry["def"])
	_animate_in()


func _populate(def: Dictionary) -> void:
	_title_label.text = def.get("label", "Achievement")
	_desc_label.text  = def.get("desc",  "")
	# Hidden/secret achievements show a generic description until earned.
	if def.get("hidden", false):
		_desc_label.text = def.get("desc", "Secret achievement unlocked!")
	_icon_label.text = "🦊"


func _animate_in() -> void:
	# Start off-screen to the right.
	var screen_size := Vector2(get_viewport().get_visible_rect().size)
	var off_x  := screen_size.x + MARGIN
	var rest_x := screen_size.x - PANEL_WIDTH - MARGIN
	var rest_y := screen_size.y - PANEL_HEIGHT - MARGIN

	_panel.position = Vector2(off_x, rest_y)
	_panel.modulate.a = 1.0
	_panel.visible = true

	if is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "position:x", rest_x, SLIDE_IN_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_DURATION)
	_tween.tween_property(_panel, "modulate:a", 0.0, SLIDE_OUT_DURATION)\
		.set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_toast_done)


func _on_toast_done() -> void:
	_panel.visible = false
	_show_next()


# ---------------------------------------------------------------------------
# Node construction
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.visible = false

	# Style — warm cream panel matching the game's palette.
	var style := StyleBoxFlat.new()
	style.bg_color             = Color("f5e6c8")
	style.border_color         = Color("c8a060")
	style.border_width_left    = 2
	style.border_width_right   = 2
	style.border_width_top     = 2
	style.border_width_bottom  = 2
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Fox emoji icon (left column).
	_icon_label = Label.new()
	_icon_label.position = Vector2(8, 8)
	_icon_label.size     = Vector2(48, PANEL_HEIGHT - 16)
	_icon_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 28)
	_panel.add_child(_icon_label)

	# Achievement name.
	_title_label = Label.new()
	_title_label.position = Vector2(60, 8)
	_title_label.size     = Vector2(PANEL_WIDTH - 68, 24)
	_title_label.add_theme_font_override("font", FONT)
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color("5a3010"))
	_title_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_panel.add_child(_title_label)

	# Description / flavour text.
	_desc_label = Label.new()
	_desc_label.position    = Vector2(60, 32)
	_desc_label.size        = Vector2(PANEL_WIDTH - 68, PANEL_HEIGHT - 40)
	_desc_label.add_theme_font_override("font", FONT)
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color("8a6040"))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_desc_label)

	# Small header label above the title.
	var header := Label.new()
	header.text     = "Achievement unlocked"
	header.position = Vector2(60, 0)
	header.size     = Vector2(PANEL_WIDTH - 68, 14)
	header.add_theme_font_override("font", FONT)
	header.add_theme_font_size_override("font_size", 9)
	header.add_theme_color_override("font_color", Color("b07840"))
	_panel.add_child(header)
