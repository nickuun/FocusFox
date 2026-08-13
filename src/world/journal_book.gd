extends Control
class_name JournalBook

## The "Fox Journal" — a full-window open book with an edge rail of tabs switching
## between pages. Replaces the flat card layout of the old JournalPanel.
##
## Everything is laid out in absolute design-space pixels, 1:1 with the art, the same
## convention the settings panel uses. The launcher renders this 960×540 space at an
## integer multiple, so these coordinates stay valid at any window scale.
##
## The book plate is bare art — cover, gutter, rings, bookmarks and nothing else. All
## furniture (panels, rules, polaroid, title) is composed on top from separate pieces,
## so each page lays out whatever it needs rather than inheriting one fixed set of wells.

signal close_requested

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

const PLATE := preload("res://assets/journal/journal ui/Main Page/Journal_Today_Page.png")
const TITLE_ART := preload("res://assets/journal/journal ui/Main Page/Fox_Journal-title.png")
const FOX_FRAME := preload("res://assets/journal/journal ui/Main Page/fox_frame.png")
const PANEL_LARGE := preload("res://assets/journal/journal ui/Main Page/day_tab.png")
const PANEL_MEDIUM := preload("res://assets/journal/journal ui/Main Page/medium_tab.png")
const RULE := preload("res://assets/journal/journal ui/Main Page/tilable_line.png")
## Generated rather than drawn — see tools/make_day_cell.py. Deliberately near-neutral
## so the per-state tints below multiply cleanly instead of coming out muddy.
const DAY_CELL := preload("res://assets/journal/journal ui/Main Page/day_cell.png")
const BADGE := preload("res://assets/journal/journal ui/Main Page/badge.png")

const TAB_ART := [
	preload("res://assets/journal/journal ui/Today Log_Tab.png"),
	preload("res://assets/journal/journal ui/Journal_Extra_Tab.png"),
	preload("res://assets/journal/journal ui/Calendar_Tab.png"),
	preload("res://assets/journal/journal ui/Journal_Upgrades_Tab.png"),
	preload("res://assets/journal/journal ui/Achievements_Tab.png"),
]

enum Page { TODAY, LOGBOOK, HISTORY, DEN, ACHIEVEMENTS }

const PAGE_NAMES := ["Today", "Logbook", "History", "Den", "Achievements"]

# --- Palette, sampled from the book art so text sits in it rather than on it ------
const INK := Color(0.30, 0.19, 0.11)
const INK_SOFT := Color(0.30, 0.19, 0.11, 0.70)
const INK_FAINT := Color(0.30, 0.19, 0.11, 0.38)
const PAW := Color("8a5630")
const GREEN := Color("4a8f3c")
const ORANGE := Color("cf7a2e")
const RUST := Color("b6502e")
const BLUE := Color("3f6ea3")
const TRACK := Color(0.72, 0.64, 0.53, 0.55)

# --- Geometry, measured off the plate ---------------------------------------------
## The cream areas of the two pages. Nothing should be drawn outside these — the
## surrounding pixels are cover, gutter shadow and the page-curl.
const LEFT_PAGE := Rect2(112, 47, 340, 433)
const RIGHT_PAGE := Rect2(512, 50, 333, 428)

## Tab rail. The chips poke out of the book's left edge; the active one slides a
## little further out and brightens, which is why no second sprite is needed.
const TAB_X := 66.0
const TAB_Y0 := 80.0
const TAB_PITCH := 57.0
const TAB_OUT := 6.0
const TAB_HOVER_OUT := 2.0

## NinePatch margins for the two panel sprites. Left/right match the slice kit's
## 32px corner; bottom matches its 27px; top is set to clear the baked header so the
## ‹ › arrows and the sub-header pill are never stretched.
const PANEL_LARGE_MARGINS := Vector4(32, 46, 32, 27)   # l, t, r, b
const PANEL_MEDIUM_MARGINS := Vector4(32, 32, 32, 27)

## The ‹ › glyphs baked into the large panel's header, in panel-local coordinates.
## Buttons are placed over them rather than drawn.
const ARROW_LEFT := Rect2(12, 6, 36, 32)
const ARROW_RIGHT := Rect2(264, 6, 36, 32)

const RULE_PITCH := 26.0

const DAY_INITIALS := ["M", "T", "W", "T", "F", "S", "S"]
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTHS := ["", "January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

## How many event rows fit on the left page's rules. A day with more than this is
## rare enough that a summary line beats building pagination for it.
const LOG_ROWS := 12

## Rungs of the den ladder per page. Twelve fits the same ruled area the logbook uses;
## the catalog is nine today, so this is one page with room to grow — and when it isn't,
## stepping the selection past the last rung turns the page on its own.
const DEN_ROWS := 12

## Month grid. 6 rows x 7 columns is the fixed shape month_activity() returns, and
## 312px of left page divides into seven 44.6px columns with the 34px cell centred.
const GRID_COLS := 7
const GRID_ROWS := 6
const GRID_PITCH_Y := 40.0
## Cell tints. The source cell is pale and near-neutral, so these multiply onto it.
const CELL_PLAIN := Color(1, 1, 1)
const CELL_ACTIVE := Color(0.60, 0.81, 0.56)
const CELL_TODAY := Color(0.95, 0.77, 0.40)
const CELL_OUTSIDE := Color(1, 1, 1, 0.28)

## Achievement grid: one AchievementStore group per row, six slots wide, which is
## exactly the shape the 41 definitions fall into.
const BADGE_COLS := 6
const BADGE_PITCH := 52.0
## One tint per group, in GROUPS order. Distinct enough to tell rows apart at a
## glance, all within the book's warm range.
const GROUP_TINTS := [
	Color(0.60, 0.81, 0.56),  # First Steps
	Color(0.88, 0.63, 0.31),  # Session Milestones
	Color(0.47, 0.63, 0.82),  # Time Spent
	Color(0.78, 0.43, 0.31),  # Streaks
	Color(0.88, 0.75, 0.37),  # Fox Friend
	Color(0.67, 0.57, 0.76),  # Making It Yours
	Color(0.65, 0.65, 0.67),  # Secrets
]
const BADGE_LOCKED := Color(0.66, 0.63, 0.60, 0.55)

var _current := Page.TODAY
var _week_offset := 0
var _page_tween: Tween

var _tabs: Array[TextureRect] = []
var _pages: Array[Control] = []

# Today page widgets
var _score_value: Label
var _score_tier: Label
var _greeting: Label
var _goal_rows: Array = []
var _tasks: Label
var _week_title: Label
var _week_paws: Array[PawIcon] = []
var _week_days: Array[Label] = []
var _week_footer: Label
var _find_widgets := {}
var _totals: Array[Label] = []

# Logbook page widgets
var _log_day := ""
var _log_title: Label
var _log_subtitle: Label
var _log_rows: Array = []
var _log_overflow: Label
var _log_empty: Label
var _log_date: Label
var _log_score: Label
var _log_score_tier: Label
var _log_stats: Array[Label] = []
var _log_note: LineEdit
var _log_note_hint: Label
var _log_tasks: Label

# History page widgets
var _hist_year := 0
var _hist_month := 0
var _hist_subtitle: Label
var _hist_cells: Array = []
var _hist_month_label: Label
var _hist_summary: Array[Label] = []
var _hist_best: Label
var _hist_extra: Array[Label] = []

# Den page widgets
var _den_selected := 0
var _den_rows: Array = []
var _den_subtitle: Label
var _den_empty: Label
var _den_find_widgets := {}
var _den_detail_title: Label
var _den_detail_art: TextureRect
var _den_detail_name: Label
var _den_detail_when: Label
var _den_detail_where: Label
var _den_room_text: Label
var _den_tidy_button: Panel
var _den_tidy_hint: Label

# Achievements page widgets
var _ach_order: Array = []      # flat list of ids, grid order
var _ach_group_of := {}         # id -> group index
var _ach_slots: Array = []
var _ach_selected := ""
var _ach_group_label: Label
var _ach_group_progress: Label
var _ach_detail_badge: TextureRect
var _ach_detail_icon: TextureRect
var _ach_detail_mark: Label
var _ach_detail_name: Label
var _ach_detail_desc: Label
var _ach_detail_state: Label
var _ach_count: Label
var _ach_bar_track: Panel
var _ach_bar_fill: Panel
var _ach_secrets: Label

var _stats: StatsStore
var _den: Den


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_show_page(Page.TODAY, false)


func _build() -> void:
	# The plate is a book on a transparent surround, so without this the launcher —
	# stats bar, credits, wooden floor — shows through around the covers. Kept inside
	# the book rather than reusing the settings scrim so the journal icon, which sits
	# above this node, stays lit and clickable as the way back out.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.16, 0.10, 0.07, 0.62)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var plate := TextureRect.new()
	plate.texture = PLATE
	plate.position = Vector2.ZERO
	plate.size = Vector2(960, 540)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)

	_build_tabs()

	for i in PAGE_NAMES.size():
		var page := Control.new()
		page.name = PAGE_NAMES[i]
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Pages squash about the gutter when turning, so the animation reads as the
		# spread's halves folding rather than a box shrinking off-centre.
		page.pivot_offset = Vector2(480, 270)
		add_child(page)
		_pages.append(page)

	_build_today(_pages[Page.TODAY])
	_build_logbook(_pages[Page.LOGBOOK])
	_build_history(_pages[Page.HISTORY])
	_build_achievements(_pages[Page.ACHIEVEMENTS])
	_build_den(_pages[Page.DEN])


func _build_tabs() -> void:
	for i in TAB_ART.size():
		var tab := TextureRect.new()
		tab.texture = TAB_ART[i]
		tab.position = Vector2(TAB_X, TAB_Y0 + TAB_PITCH * i)
		tab.size = TAB_ART[i].get_size()
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.tooltip_text = PAGE_NAMES[i]
		tab.gui_input.connect(_on_tab_input.bind(i))
		tab.mouse_entered.connect(_on_tab_hover.bind(i, true))
		tab.mouse_exited.connect(_on_tab_hover.bind(i, false))
		add_child(tab)
		_tabs.append(tab)


func _on_tab_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if index != _current:
			_show_page(index, true)


func _on_tab_hover(index: int, entered: bool) -> void:
	if index == _current:
		return
	_tabs[index].position.x = TAB_X - (TAB_HOVER_OUT if entered else 0.0)


# --- Page switching ----------------------------------------------------------

func _show_page(page: int, animate: bool) -> void:
	# Turning the page away from a half-written note should keep it, not bin it.
	if _current == Page.LOGBOOK and page != Page.LOGBOOK and _log_note != null:
		_save_note()
	_current = page
	for i in _tabs.size():
		var active := i == page
		_tabs[i].position.x = TAB_X - (TAB_OUT if active else 0.0)
		_tabs[i].modulate = Color.WHITE if active else Color(0.88, 0.88, 0.88)
	for i in _pages.size():
		_pages[i].visible = i == page
	_refresh_current()

	if not animate:
		_pages[page].scale = Vector2.ONE
		return

	Audio.play("open", 1.12)
	if _page_tween != null and _page_tween.is_valid():
		_page_tween.kill()
	var target := _pages[page]
	target.scale = Vector2(0.0, 1.0)
	_page_tween = create_tween()
	_page_tween.tween_property(target, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Closing the journal is the other way to leave a half-written note behind, and
## world.gd closes it by flipping `visible` rather than calling anything here.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and _log_note != null:
		_save_note()
		_log_note.release_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# While the day note has focus, Q and E are letters and the arrows move the caret.
	# Escape still gets through, but it drops out of the field first rather than
	# closing the whole journal on the player mid-sentence.
	if _log_note != null and _log_note.has_focus():
		if event.keycode == KEY_ESCAPE:
			_save_note()
			_log_note.release_focus()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE:
			close_requested.emit()
			get_viewport().set_input_as_handled()
		KEY_E, KEY_RIGHT:
			_show_page((_current + 1) % _pages.size(), true)
			get_viewport().set_input_as_handled()
		KEY_Q, KEY_LEFT:
			_show_page((_current + _pages.size() - 1) % _pages.size(), true)
			get_viewport().set_input_as_handled()


# --- Today page --------------------------------------------------------------

func _build_today(page: Control) -> void:
	var l := LEFT_PAGE.position

	var title := TextureRect.new()
	title.texture = TITLE_ART
	title.position = l + Vector2(14, 7)
	title.size = TITLE_ART.get_size()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(title)
	_rule(page, l.x + 14, l.y + 47, LEFT_PAGE.size.x - 28)

	var frame := TextureRect.new()
	frame.texture = FOX_FRAME
	frame.position = l + Vector2(14, 59)
	frame.size = FOX_FRAME.get_size()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(frame)

	# Score, sitting beside the polaroid where the mockup put the headline numbers.
	_lbl(page, "Today's score", l.x + 140, l.y + 65, 186, 20, 15, INK_SOFT)
	_score_value = _lbl(page, "0", l.x + 140, l.y + 86, 186, 42, 38, GREEN)
	_score_tier = _lbl(page, "", l.x + 140, l.y + 128, 186, 22, 15, INK_SOFT)

	_greeting = _lbl(page, "", l.x + 14, l.y + 177, LEFT_PAGE.size.x - 28, 46, 15, INK)
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_lbl(page, "Daily goals", l.x + 14, l.y + 229, 200, 22, 17, INK)
	var bar_y := [255.0, 297.0, 339.0]
	var specs := [["Focus sessions", GREEN], ["Time focused", GREEN], ["Breaks taken", ORANGE]]
	for i in specs.size():
		_goal_rows.append(_goal_row(page, l.x + 14, l.y + bar_y[i], LEFT_PAGE.size.x - 28,
			str(specs[i][0]), specs[i][1]))

	_rule(page, l.x + 14, l.y + 383, LEFT_PAGE.size.x - 28)
	_tasks = _lbl(page, "", l.x + 14, l.y + 391, LEFT_PAGE.size.x - 28, 40, 14, INK_SOFT)
	_tasks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_week_panel(page)
	_find_widgets = _build_find_panel(page,
		Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 212))
	_build_totals_panel(page)


## Label above, track and fill below, value right-aligned on the label's line.
func _goal_row(page: Control, x: float, y: float, w: float, label: String, colour: Color) -> Dictionary:
	_lbl(page, label, x, y, w - 90, 20, 14, INK_SOFT)
	var value := _lbl(page, "0 / 0", x + w - 110, y, 110, 20, 14, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	var track := Panel.new()
	track.position = Vector2(x, y + 21)
	track.size = Vector2(w, 12)
	track.add_theme_stylebox_override("panel", _flat(TRACK, 6))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(track)
	var fill := Panel.new()
	fill.position = Vector2(x, y + 21)
	fill.size = Vector2(0, 12)
	fill.add_theme_stylebox_override("panel", _flat(colour, 6))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(fill)
	return {"value": value, "fill": fill, "width": w}


func _build_week_panel(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 8),
		PANEL_LARGE.get_size(), PANEL_LARGE, PANEL_LARGE_MARGINS)

	_week_title = _lbl(panel, "This Week", 52, 12, 208, 24, 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_arrow_button(panel, ARROW_LEFT, -1, _step_week)
	_arrow_button(panel, ARROW_RIGHT, 1, _step_week)

	var col := (PANEL_LARGE.get_width() - 24) / 7.0
	for i in 7:
		var cx := 12 + col * (i + 0.5)
		_week_days.append(_lbl(panel, DAY_INITIALS[i], cx - 20, 56, 40, 20, 15, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
		var paw := PawIcon.new()
		paw.paw_color = PAW
		paw.size = Vector2(34, 34)
		paw.position = Vector2(cx - 17, 78)
		paw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(paw)
		_week_paws.append(paw)

	_week_footer = _lbl(panel, "", 12, 126, PANEL_LARGE.get_width() - 24, 40, 14, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_week_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The "what's the fox bringing home next" panel. Built by both the Today page and the
## Den page, so it's one panel described once and filled by _fill_find_panel().
func _build_find_panel(page: Control, at: Vector2) -> Dictionary:
	var panel := _panel(page, at, PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "Next Den Find", 16, 5, 160, 22, 15, INK)
	var text := _lbl(panel, "", 16, 34, PANEL_MEDIUM.get_width() - 32, 20, 14, INK)
	var bar := Panel.new()
	bar.position = Vector2(16, 60)
	bar.size = Vector2(180, 12)
	bar.add_theme_stylebox_override("panel", _flat(TRACK, 6))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bar)
	var fill := Panel.new()
	fill.position = Vector2(16, 60)
	fill.size = Vector2(0, 12)
	fill.add_theme_stylebox_override("panel", _flat(RUST, 6))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	var count := _lbl(panel, "", 204, 56, 94, 20, 13, INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
	return {"text": text, "bar": bar, "fill": fill, "count": count}


func _build_totals_panel(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 320),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "All Time", 16, 5, 160, 22, 15, INK)
	# Three columns rather than the old five: 313px can hold three readable numbers,
	# and the remaining two totals belong on the History page where there's room.
	var labels := ["sessions", "focused", "best trail"]
	var colours := [GREEN, GREEN, RUST]
	var col := (PANEL_MEDIUM.get_width() - 24) / 3.0
	for i in 3:
		var x := 12 + col * i
		_totals.append(_lbl(panel, "0", x, 32, col, 30, 24, colours[i], HORIZONTAL_ALIGNMENT_CENTER))
		_lbl(panel, labels[i], x, 62, col, 20, 13, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)


## An invisible hit area over one of the ‹ › glyphs baked into a panel's header.
func _arrow_button(panel: Control, rect: Rect2, step: int, handler: Callable) -> void:
	var btn := Control.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			handler.call(step))
	panel.add_child(btn)


## A small filled circle, for the break bullet in the logbook.
func _dot(parent: Control, at: Vector2, radius: float, colour: Color) -> Panel:
	var dot := Panel.new()
	dot.position = at
	dot.size = Vector2(radius * 2, radius * 2)
	dot.add_theme_stylebox_override("panel", _flat(colour, int(radius)))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(dot)
	return dot


## Walks the week strip back and forth. Forward stops at the current week and back
## stops at the week holding the first recorded session, so ‹ › never leads into
## empty history.
func _step_week(step: int) -> void:
	var next := _week_offset + step
	if next > 0:
		return
	if step < 0 and _stats != null:
		var first := _stats.first_active_day()
		if first != "":
			var week := _stats.week_activity(next)
			if str(week[6]["key"]) < first:
				return
	_week_offset = next
	Audio.play("open", 1.2)
	_refresh_week()


# --- Logbook page ------------------------------------------------------------
#
# The left page is the fox's record and is never edited: one ruled row per completed
# session, written from the event log. The player already says what a session is for
# — the launcher's "What are you focusing on?" input rides along with the session and
# becomes that row's label — so the log fills itself as a by-product of using the
# timer rather than being another thing to keep up with.
#
# The right page carries the one thing the player writes: a single note per day. It's
# retrospective on purpose, and it can be written on any past day, because catching up
# on a journal is normal and being locked out of yesterday is not.

func _build_logbook(page: Control) -> void:
	var l := LEFT_PAGE.position

	_log_title = _lbl(page, "Logbook", l.x + 14, l.y + 8, LEFT_PAGE.size.x - 28, 34, 26, INK)
	_log_subtitle = _lbl(page, "", l.x + 14, l.y + 40, LEFT_PAGE.size.x - 28, 22, 14, INK_SOFT)
	_rule(page, l.x + 14, l.y + 62, LEFT_PAGE.size.x - 28)

	for i in LOG_ROWS:
		var y := l.y + 72 + RULE_PITCH * i
		_rule(page, l.x + 14, y + 21, LEFT_PAGE.size.x - 28)
		var row := {}
		# Focus rows get a paw; breaks get a small hollow mark, so the two read apart
		# at a glance without needing a second sprite.
		var paw := PawIcon.new()
		paw.paw_color = PAW
		paw.size = Vector2(15, 15)
		paw.position = Vector2(l.x + 16, y + 3)
		paw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(paw)
		row["paw"] = paw
		row["dot"] = _dot(page, Vector2(l.x + 21, y + 8), 5, ORANGE)
		row["time"] = _lbl(page, "", l.x + 38, y + 1, 52, 20, 14, INK_SOFT)
		row["kind"] = _lbl(page, "", l.x + 92, y + 1, 78, 20, 14, INK)
		row["task"] = _lbl(page, "", l.x + 172, y + 1, 154, 20, 14, INK_SOFT)
		row["task"].clip_text = true
		_log_rows.append(row)

	_log_overflow = _lbl(page, "", l.x + 38, l.y + 72 + RULE_PITCH * LOG_ROWS, 280, 22, 13, INK_FAINT)
	_log_empty = _lbl(page, "", l.x + 24, l.y + 150, LEFT_PAGE.size.x - 48, 90, 15, INK_FAINT,
		HORIZONTAL_ALIGNMENT_CENTER)
	_log_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_log_summary(page)
	_build_log_note(page)
	_build_log_tasks(page)


func _build_log_summary(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 8),
		PANEL_LARGE.get_size(), PANEL_LARGE, PANEL_LARGE_MARGINS)
	_log_date = _lbl(panel, "", 52, 12, 208, 24, 17, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_arrow_button(panel, ARROW_LEFT, -1, _step_day)
	_arrow_button(panel, ARROW_RIGHT, 1, _step_day)

	_log_score = _lbl(panel, "0", 16, 54, 96, 44, 36, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl(panel, "score", 16, 96, 96, 20, 13, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_log_score_tier = _lbl(panel, "", 12, 148, PANEL_LARGE.get_width() - 24, 22, 13, INK_SOFT,
		HORIZONTAL_ALIGNMENT_CENTER)

	var labels := ["sessions", "focused", "breaks"]
	for i in 3:
		var y := 54 + 32 * i
		_log_stats.append(_lbl(panel, "0", 124, y, 76, 24, 17, INK, HORIZONTAL_ALIGNMENT_RIGHT))
		_lbl(panel, labels[i], 208, y + 2, 92, 22, 13, INK_SOFT)


func _build_log_note(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 212),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "Day note", 16, 5, 160, 22, 15, INK)

	_log_note = LineEdit.new()
	_log_note.position = Vector2(16, 34)
	_log_note.size = Vector2(PANEL_MEDIUM.get_width() - 32, 26)
	_log_note.placeholder_text = "How did today go?"
	_log_note.max_length = 140
	_log_note.add_theme_font_override("font", FONT)
	_log_note.add_theme_font_size_override("font_size", 14)
	_log_note.add_theme_color_override("font_color", INK)
	_log_note.add_theme_color_override("font_placeholder_color", INK_FAINT)
	_log_note.add_theme_color_override("caret_color", INK)
	# The book is already a painted surface; a boxed input on top of it looks bolted
	# on, so the field is invisible until it has focus and then just underlines.
	_log_note.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_log_note.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_log_note.text_submitted.connect(func(_t: String) -> void:
		_save_note()
		_log_note.release_focus())
	_log_note.focus_exited.connect(_save_note)
	panel.add_child(_log_note)

	_rule(panel, 16, 58, PANEL_MEDIUM.get_width() - 32)
	_log_note_hint = _lbl(panel, "", 16, 64, PANEL_MEDIUM.get_width() - 32, 20, 12, INK_FAINT)


func _build_log_tasks(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 320),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "What you worked on", 16, 5, 220, 22, 15, INK)
	_log_tasks = _lbl(panel, "", 16, 32, PANEL_MEDIUM.get_width() - 32, 52, 13, INK_SOFT)
	_log_tasks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _save_note() -> void:
	if _stats == null or _log_day == "":
		return
	if _stats.day_note(_log_day) == _log_note.text.strip_edges():
		return
	_stats.set_day_note(_log_day, _log_note.text)
	_refresh_note_hint()


## Steps to the previous or next day the journal has anything for, skipping the blank
## stretches in between. Stops rather than wrapping, so the ends of history feel like
## ends.
func _step_day(step: int) -> void:
	if _stats == null:
		return
	_save_note()
	var next := _stats.adjacent_logged_day(_log_day, step)
	if next == "":
		return
	_log_day = next
	Audio.play("open", 1.2)
	_refresh_logbook()


## Opens the logbook on a specific day. Phase 4's month grid calls this so clicking a
## cell in History lands on that day's page.
func open_day(key: String) -> void:
	_log_day = key
	_show_page(Page.LOGBOOK, true)


func _refresh_logbook() -> void:
	if _log_day == "":
		_log_day = _stats.today_key()
	var key := _log_day
	var d := _stats.day(key)
	var evs := _stats.day_events(key)
	var score: Dictionary = _stats.day_score(key)
	var is_today := key == _stats.today_key()

	_log_subtitle.text = _long_date(key)
	_log_date.text = "Today" if is_today else _short_date(key)

	var sessions := int(d.get("sessions", 0))
	var breaks := int(d.get("breaks", 0))

	for i in LOG_ROWS:
		var row: Dictionary = _log_rows[i]
		var has := i < evs.size()
		(row["paw"] as PawIcon).visible = false
		(row["dot"] as Panel).visible = false
		(row["time"] as Label).visible = has
		(row["kind"] as Label).visible = has
		(row["task"] as Label).visible = has
		if not has:
			continue
		var ev: Dictionary = evs[i]
		var focus := str(ev.get("kind", "focus")) == "focus"
		(row["paw"] as PawIcon).visible = focus
		(row["dot"] as Panel).visible = not focus
		(row["time"] as Label).text = _clock_time(int(ev.get("ts", 0)))
		(row["kind"] as Label).text = "%s %s" % [_kind_name(str(ev.get("kind", "focus"))),
			_short_duration(float(ev.get("seconds", 0.0)))]
		(row["kind"] as Label).add_theme_color_override("font_color", INK if focus else ORANGE)
		var task := str(ev.get("task", ""))
		(row["task"] as Label).text = "" if task == "" else "\"%s\"" % task

	var extra := evs.size() - LOG_ROWS
	_log_overflow.text = "" if extra <= 0 else "+%d more %s that day." % [
		extra, "session" if extra == 1 else "sessions"]

	# Two different kinds of nothing. A day recorded before the event log existed has
	# real totals but no rows, and telling the player their history is "blank" when
	# they know they worked would read as the journal having lost it.
	if not evs.is_empty():
		_log_empty.text = ""
	elif sessions > 0 or breaks > 0:
		_log_empty.text = "%d %s and %s focused — recorded before the fox kept a logbook, so there are no times to show." % [
			sessions, "session" if sessions == 1 else "sessions",
			_short_duration(float(d.get("focus", 0.0)))]
	elif is_today:
		_log_empty.text = "Nothing written yet today.\nStart a session and your fox will fill this page in."
	else:
		_log_empty.text = "This page is still blank.\nYour fox was resting."

	_log_score.text = "%d" % int(score["score"])
	_log_score.add_theme_color_override("font_color", _tier_colour(str(score["tier"])))
	_log_score_tier.text = _tier_text(str(score["tier"]), bool(score["needs_rest"]), is_today)
	_log_stats[0].text = "%d" % sessions
	_log_stats[1].text = _short_duration(float(d.get("focus", 0.0)))
	_log_stats[2].text = "%d" % breaks

	_log_note.text = _stats.day_note(key)
	_log_note.placeholder_text = "How did today go?" if is_today else "Anything to add about this day?"
	_refresh_note_hint()

	# Preferred from the events, because those carry a label per session for every day.
	# The day aggregate's `tasks` array is only written for the current day, so relying
	# on it left every past page claiming nothing was worked on while the rows beside
	# it listed the tasks. It's still the fallback for days older than the event log.
	var tasks := []
	for ev in evs:
		var t := str(ev.get("task", ""))
		if t != "" and not tasks.has(t):
			tasks.append(t)
	if tasks.is_empty():
		for t in d.get("tasks", []):
			if not tasks.has(t):
				tasks.append(t)
	_log_tasks.text = "Nothing recorded." if tasks.is_empty() else " · ".join(tasks)


func _refresh_note_hint() -> void:
	var has_prev := _stats.adjacent_logged_day(_log_day, -1) != ""
	var has_next := _stats.adjacent_logged_day(_log_day, 1) != ""
	if _log_note.text.strip_edges() == "":
		_log_note_hint.text = "Click the line to write. Enter saves."
	elif has_prev or has_next:
		# PixelOperator has no ‹ › glyphs — they fall back to a mismatched face.
		_log_note_hint.text = "Saved. Use the arrows to read other days."
	else:
		_log_note_hint.text = "Saved."


# --- History page ------------------------------------------------------------
#
# The month grid takes the whole left page rather than sitting in a panel, because a
# 34px square cell needs the room and a calendar squeezed into a 144px panel body
# stops being readable. The large panel on the right keeps its usual job: its baked
# ‹ › header is the navigator, exactly as it is on the Logbook, so "the arrows in the
# top-right panel step whatever this page is about" holds on every page.
#
# Cells are tinted, not badged. A paw plus a date in 34px comes out as mush, and the
# paw motif already carries the Today page's week strip — here legibility wins.

func _build_history(page: Control) -> void:
	var l := LEFT_PAGE.position

	_lbl(page, "History", l.x + 14, l.y + 8, LEFT_PAGE.size.x - 28, 34, 26, INK)
	_hist_subtitle = _lbl(page, "", l.x + 14, l.y + 40, LEFT_PAGE.size.x - 28, 22, 14, INK_SOFT)
	_rule(page, l.x + 14, l.y + 62, LEFT_PAGE.size.x - 28)

	var col_w := (LEFT_PAGE.size.x - 28) / float(GRID_COLS)
	var grid_x := l.x + 14
	var grid_y := l.y + 100

	for c in GRID_COLS:
		_lbl(page, DAY_INITIALS[c], grid_x + col_w * c, l.y + 74, col_w, 20, 14, INK_FAINT,
			HORIZONTAL_ALIGNMENT_CENTER)

	for i in GRID_ROWS * GRID_COLS:
		var cx := grid_x + col_w * (i % GRID_COLS) + (col_w - DAY_CELL.get_width()) * 0.5
		var cy := grid_y + GRID_PITCH_Y * (i / GRID_COLS)

		var cell := TextureRect.new()
		cell.texture = DAY_CELL
		cell.position = Vector2(cx, cy)
		cell.size = DAY_CELL.get_size()
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		page.add_child(cell)

		var num := _lbl(cell, "", 0, 8, DAY_CELL.get_width(), 20, 14, INK, HORIZONTAL_ALIGNMENT_CENTER)
		cell.gui_input.connect(_on_cell_input.bind(i))
		_hist_cells.append({"cell": cell, "num": num, "key": "", "clickable": false})

	_lbl(page, "Click a day to read its page.", l.x + 14, l.y + 350,
		LEFT_PAGE.size.x - 28, 22, 13, INK_FAINT, HORIZONTAL_ALIGNMENT_CENTER)

	_build_history_summary(page)
	_build_history_extras(page)


func _build_history_summary(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 8),
		PANEL_LARGE.get_size(), PANEL_LARGE, PANEL_LARGE_MARGINS)
	_hist_month_label = _lbl(panel, "", 52, 12, 208, 24, 17, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_arrow_button(panel, ARROW_LEFT, -1, _step_month)
	_arrow_button(panel, ARROW_RIGHT, 1, _step_month)

	var labels := ["sessions", "focused", "days active", "breaks"]
	for i in labels.size():
		var y := 52 + 24 * i
		_hist_summary.append(_lbl(panel, "0", 16, y, 96, 22, 16, INK, HORIZONTAL_ALIGNMENT_RIGHT))
		_lbl(panel, labels[i], 120, y + 1, 120, 22, 13, INK_SOFT)

	_rule(panel, 16, 152, PANEL_LARGE.get_width() - 32)
	_hist_best = _lbl(panel, "", 16, 158, PANEL_LARGE.get_width() - 32, 22, 13, INK_SOFT)


## The two all-time totals that wouldn't fit the Today page's three-column panel.
func _build_history_extras(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 212),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "All Time", 16, 5, 160, 22, 15, INK)
	var labels := ["longest streak", "breaks taken"]
	var colours := [BLUE, INK]
	var col := (PANEL_MEDIUM.get_width() - 24) / 2.0
	for i in 2:
		var x := 12 + col * i
		_hist_extra.append(_lbl(panel, "0", x, 32, col, 30, 22, colours[i], HORIZONTAL_ALIGNMENT_CENTER))
		_lbl(panel, labels[i], x, 62, col, 20, 13, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)

	var trail := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 320),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(trail, "Pawprint trails", 16, 5, 220, 22, 15, INK)
	var trail_labels := ["current", "best ever"]
	var tcol := (PANEL_MEDIUM.get_width() - 24) / 2.0
	for i in 2:
		var x := 12 + tcol * i
		_hist_extra.append(_lbl(trail, "0", x, 32, tcol, 30, 22, RUST, HORIZONTAL_ALIGNMENT_CENTER))
		_lbl(trail, trail_labels[i], x, 62, tcol, 20, 13, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)


func _on_cell_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var c: Dictionary = _hist_cells[index]
	if not bool(c["clickable"]):
		return
	open_day(str(c["key"]))


## Steps whole months, stopping at the month holding the first recorded session and at
## the current month. Walking into empty years in either direction is just a way to get
## lost in a book that's meant to be a record of something.
func _step_month(step: int) -> void:
	if _stats == null:
		return
	var y := _hist_year
	var m := _hist_month + step
	if m < 1:
		m = 12
		y -= 1
	elif m > 12:
		m = 1
		y += 1

	var now := Time.get_date_dict_from_system()
	if y > int(now.year) or (y == int(now.year) and m > int(now.month)):
		return
	var first := _stats.first_active_day()
	if first != "":
		var fd := _key_to_dict(first)
		if y < int(fd["year"]) or (y == int(fd["year"]) and m < int(fd["month"])):
			return

	_hist_year = y
	_hist_month = m
	Audio.play("open", 1.2)
	_refresh_history()


func _refresh_history() -> void:
	if _hist_month == 0:
		var now := Time.get_date_dict_from_system()
		_hist_year = int(now.year)
		_hist_month = int(now.month)

	var name_ := "%s %d" % [MONTHS[_hist_month], _hist_year]
	_hist_subtitle.text = name_
	_hist_month_label.text = name_

	var cells := _stats.month_activity(_hist_year, _hist_month)
	for i in _hist_cells.size():
		var c: Dictionary = _hist_cells[i]
		var d: Dictionary = cells[i]
		var cell: TextureRect = c["cell"]
		var num: Label = c["num"]
		var inside := bool(d["in_month"])

		num.text = str(int(d["day"]))
		c["key"] = str(d["key"])
		# Future days can't have a page worth reading, so they aren't clickable and
		# don't advertise a tooltip.
		c["clickable"] = inside and not bool(d["future"])

		if not inside:
			cell.modulate = CELL_OUTSIDE
			num.add_theme_color_override("font_color", INK_FAINT)
			cell.tooltip_text = ""
		elif bool(d["today"]):
			cell.modulate = CELL_TODAY
			num.add_theme_color_override("font_color", INK)
			cell.tooltip_text = "Today — %s" % _cell_tip(d)
		elif bool(d["active"]):
			cell.modulate = CELL_ACTIVE
			num.add_theme_color_override("font_color", INK)
			cell.tooltip_text = _cell_tip(d)
		else:
			cell.modulate = CELL_PLAIN
			num.add_theme_color_override("font_color", INK_FAINT if bool(d["future"]) else INK_SOFT)
			cell.tooltip_text = "" if bool(d["future"]) else "Nothing recorded"
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if bool(c["clickable"]) \
			else Control.CURSOR_ARROW

	var sum := _stats.month_summary(_hist_year, _hist_month)
	_hist_summary[0].text = "%d" % int(sum["sessions"])
	_hist_summary[1].text = _short_duration(float(sum["focus"]))
	_hist_summary[2].text = "%d" % int(sum["active_days"])
	_hist_summary[3].text = "%d" % int(sum["breaks"])
	var best := str(sum["best_day"])
	_hist_best.text = "No sessions this month." if best == "" \
		else "Best day: %s, %s focused." % [_short_date(best), _short_duration(float(sum["best_focus"]))]

	_hist_extra[0].text = "%d" % _stats.longest_streak
	_hist_extra[1].text = "%d" % _stats.total_breaks()
	_hist_extra[2].text = "%d" % _stats.current_trail()
	_hist_extra[3].text = "%d" % _stats.best_trail()


func _cell_tip(d: Dictionary) -> String:
	var sessions := int(d["sessions"])
	if sessions <= 0:
		return "Nothing recorded"
	return "%d %s, %s focused" % [sessions, "session" if sessions == 1 else "sessions",
		_short_duration(float(d["focus"]))]


# --- Achievements page -------------------------------------------------------
#
# All 41 badges are on the page at once, one AchievementStore group per row, because
# an achievements screen you have to scroll or page through stops working as a
# "what's left?" glance. Labels don't fit at 48px, so the badge grid carries only
# colour and state, and the panel on the right is the reader: click or step a badge
# and it explains itself.
#
# Badge art is looked up per achievement and falls back twice — a bespoke icon if one
# exists, otherwise the group-tinted plaque. That means bespoke icons can be dropped in
# one at a time, forever, with no code change.

func _build_achievements(page: Control) -> void:
	var l := LEFT_PAGE.position
	var groups: Array = Achievements.groups()

	_lbl(page, "Achievements", l.x + 14, l.y + 6, LEFT_PAGE.size.x - 28, 34, 26, INK)
	_rule(page, l.x + 14, l.y + 44, LEFT_PAGE.size.x - 28)

	# Centre the 6-wide grid in the page's 312px of usable width.
	var content := BADGE.get_width() + BADGE_PITCH * (BADGE_COLS - 1)
	var grid_x := l.x + 14 + (LEFT_PAGE.size.x - 28 - content) * 0.5
	var grid_y := l.y + 56

	for g in groups.size():
		var ids: Array = groups[g]["ids"]
		for c in BADGE_COLS:
			var slot := Control.new()
			slot.position = Vector2(grid_x + BADGE_PITCH * c, grid_y + BADGE_PITCH * g)
			slot.size = BADGE.get_size()
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			slot.visible = c < ids.size()
			page.add_child(slot)

			var plate := TextureRect.new()
			plate.texture = BADGE
			plate.size = BADGE.get_size()
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(plate)

			# Bespoke art when it exists, drawn inside the plaque's bevel.
			var icon := TextureRect.new()
			icon.position = Vector2(6, 6)
			icon.size = Vector2(36, 36)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_SCALE
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(icon)

			# The generic stand-in: a paw once earned, a question mark for an unearned
			# secret, nothing for something merely not done yet.
			var paw := PawIcon.new()
			paw.paw_color = Color(1, 1, 1, 0.82)
			paw.position = Vector2(13, 13)
			paw.size = Vector2(22, 22)
			paw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(paw)

			var mark := _lbl(slot, "?", 0, 12, BADGE.get_width(), 26, 20, Color(1, 1, 1, 0.7),
				HORIZONTAL_ALIGNMENT_CENTER)

			if c >= ids.size():
				_ach_slots.append({})
				continue

			var id := str(ids[c])
			_ach_order.append(id)
			_ach_group_of[id] = g
			slot.gui_input.connect(_on_badge_input.bind(id))
			_ach_slots.append({
				"slot": slot, "plate": plate, "icon": icon, "paw": paw, "mark": mark, "id": id,
			})

	_build_achievement_detail(page)
	_build_achievement_progress(page)


func _build_achievement_detail(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 8),
		PANEL_LARGE.get_size(), PANEL_LARGE, PANEL_LARGE_MARGINS)
	_ach_group_label = _lbl(panel, "", 52, 12, 208, 24, 17, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_arrow_button(panel, ARROW_LEFT, -1, _step_achievement)
	_arrow_button(panel, ARROW_RIGHT, 1, _step_achievement)

	_ach_detail_badge = TextureRect.new()
	_ach_detail_badge.texture = BADGE
	_ach_detail_badge.position = Vector2(16, 54)
	_ach_detail_badge.size = BADGE.get_size()
	_ach_detail_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_ach_detail_badge)

	_ach_detail_icon = TextureRect.new()
	_ach_detail_icon.position = Vector2(6, 6)
	_ach_detail_icon.size = Vector2(36, 36)
	_ach_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ach_detail_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_ach_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ach_detail_badge.add_child(_ach_detail_icon)

	_ach_detail_mark = _lbl(_ach_detail_badge, "?", 0, 12, BADGE.get_width(), 26, 20,
		Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)

	_ach_detail_name = _lbl(panel, "", 76, 52, 220, 24, 17, INK)
	_ach_detail_desc = _lbl(panel, "", 76, 78, 222, 46, 13, INK_SOFT)
	_ach_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Most descriptions are one line, which left the panel with a band of dead air.
	# The selection's own group is the useful thing to put there.
	_ach_group_progress = _lbl(panel, "", 16, 126, PANEL_LARGE.get_width() - 32, 20, 13, INK_FAINT)
	_rule(panel, 16, 146, PANEL_LARGE.get_width() - 32)
	_ach_detail_state = _lbl(panel, "", 16, 152, PANEL_LARGE.get_width() - 32, 22, 13, INK_SOFT)


func _build_achievement_progress(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 212),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "Found", 16, 5, 160, 22, 15, INK)
	_ach_count = _lbl(panel, "", 16, 32, PANEL_MEDIUM.get_width() - 32, 22, 14, INK)
	_ach_bar_track = Panel.new()
	_ach_bar_track.position = Vector2(16, 58)
	_ach_bar_track.size = Vector2(PANEL_MEDIUM.get_width() - 32, 12)
	_ach_bar_track.add_theme_stylebox_override("panel", _flat(TRACK, 6))
	_ach_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_ach_bar_track)
	_ach_bar_fill = Panel.new()
	_ach_bar_fill.position = _ach_bar_track.position
	_ach_bar_fill.size = Vector2(0, 12)
	_ach_bar_fill.add_theme_stylebox_override("panel", _flat(GREEN, 6))
	_ach_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_ach_bar_fill)

	var secrets := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 320),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(secrets, "Secrets", 16, 5, 160, 22, 15, INK)
	_ach_secrets = _lbl(secrets, "", 16, 32, PANEL_MEDIUM.get_width() - 32, 52, 13, INK_SOFT)
	_ach_secrets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _on_badge_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_ach_selected = id
		Audio.play("open", 1.25)
		_refresh_achievements()


func _step_achievement(step: int) -> void:
	if _ach_order.is_empty():
		return
	var i := _ach_order.find(_ach_selected)
	if i < 0:
		i = 0
	_ach_selected = str(_ach_order[wrapi(i + step, 0, _ach_order.size())])
	Audio.play("open", 1.25)
	_refresh_achievements()


## A bespoke icon for one achievement, or null to fall back to the tinted plaque.
## Two naming conventions are accepted: `<id>.png` for anything added from now on, and
## the label-derived `<Label with spaces as underscores>.png` that the one existing
## icon already uses.
func _achievement_icon(id: String, def: Dictionary) -> Texture2D:
	var by_id := "res://assets/achievements/%s.png" % id
	if ResourceLoader.exists(by_id):
		return load(by_id)
	var by_label := "res://assets/achievements/%s.png" % str(def.get("label", "")).replace(" ", "_")
	if ResourceLoader.exists(by_label):
		return load(by_label)
	return null


func _refresh_achievements() -> void:
	if _ach_selected == "" and not _ach_order.is_empty():
		_ach_selected = str(_ach_order[0])

	for entry in _ach_slots:
		if entry.is_empty():
			continue
		var id: String = entry["id"]
		var def: Dictionary = Achievements.DEFS[id]
		var earned: bool = Achievements.is_earned(id)
		var hidden := bool(def.get("hidden", false))
		var group: int = _ach_group_of[id]

		var plate: TextureRect = entry["plate"]
		plate.modulate = GROUP_TINTS[group] if earned else BADGE_LOCKED

		var icon: Texture2D = _achievement_icon(id, def) if earned else null
		(entry["icon"] as TextureRect).texture = icon
		(entry["icon"] as TextureRect).visible = icon != null
		(entry["paw"] as PawIcon).visible = earned and icon == null
		(entry["mark"] as Label).visible = not earned and hidden

		# A slot pops out slightly when it's the one being read, so the grid and the
		# panel are visibly connected.
		var slot: Control = entry["slot"]
		var chosen := id == _ach_selected
		slot.scale = Vector2(1.08, 1.08) if chosen else Vector2.ONE
		slot.pivot_offset = BADGE.get_size() * 0.5
		slot.tooltip_text = _badge_tooltip(id, def, earned, hidden)

	_refresh_achievement_detail()

	var total: int = Achievements.DEFS.size()
	var found: int = Achievements.earned_count()
	_ach_count.text = "%d of %d found." % [found, total]
	_ach_bar_fill.size.x = _ach_bar_track.size.x * (float(found) / float(maxi(1, total)))

	var secret_total := 0
	var secret_found := 0
	for id in Achievements.DEFS:
		if bool(Achievements.DEFS[id].get("hidden", false)):
			secret_total += 1
			if Achievements.is_earned(id):
				secret_found += 1
	_ach_secrets.text = "%d of %d found. The rest stay hidden until your fox stumbles into them." % [
		secret_found, secret_total]


func _refresh_achievement_detail() -> void:
	if _ach_selected == "" or not Achievements.DEFS.has(_ach_selected):
		return
	var id := _ach_selected
	var def: Dictionary = Achievements.DEFS[id]
	var earned: bool = Achievements.is_earned(id)
	var hidden := bool(def.get("hidden", false))
	var group: int = _ach_group_of[id]

	var group_name := str(Achievements.GROUPS[group]["name"])
	_ach_group_label.text = group_name
	_ach_detail_badge.modulate = GROUP_TINTS[group] if earned else BADGE_LOCKED

	var group_ids: Array = Achievements.GROUPS[group]["ids"]
	var group_found := 0
	for gid in group_ids:
		if Achievements.is_earned(gid):
			group_found += 1
	_ach_group_progress.text = "%s — %d of %d found." % [group_name, group_found, group_ids.size()]

	var icon: Texture2D = _achievement_icon(id, def) if earned else null
	_ach_detail_icon.texture = icon
	_ach_detail_icon.visible = icon != null
	_ach_detail_mark.visible = not earned and hidden

	# An unearned secret keeps its secret. An unearned ordinary one shows what to aim
	# for — that's the difference the `hidden` flag is for.
	if earned or not hidden:
		_ach_detail_name.text = str(def["label"])
		_ach_detail_desc.text = str(def["desc"])
	else:
		_ach_detail_name.text = "Secret"
		_ach_detail_desc.text = "Something your fox hasn't shown you yet."

	_ach_detail_name.add_theme_color_override("font_color", INK if earned else INK_SOFT)
	if earned:
		_ach_detail_state.text = "Earned."
		_ach_detail_state.add_theme_color_override("font_color", GREEN)
	else:
		_ach_detail_state.text = "Not yet earned."
		_ach_detail_state.add_theme_color_override("font_color", INK_FAINT)


func _badge_tooltip(id: String, def: Dictionary, earned: bool, hidden: bool) -> String:
	if earned:
		return str(def["label"])
	if hidden:
		return "Secret"
	return "%s — not yet earned" % str(def["label"])


# --- Den page ----------------------------------------------------------------
#
# The left page is the whole find ladder, earned rungs and unearned alike, because a
# ladder you can only see the climbed part of doesn't tell you there's more to climb.
# The right page reads whichever rung is selected, the same grid-and-reader shape the
# Achievements page uses — and for the same reason: a row 26px tall can carry a name
# and a state and nothing else, so the detail has to live somewhere with room.
#
# Selection drives the page rather than the other way round. The ‹ › in the reader's
# header step through every find in catalog order and the ladder follows, which means
# a catalog past one page needs no paging control of its own.

func _build_den(page: Control) -> void:
	var l := LEFT_PAGE.position

	_lbl(page, "Den", l.x + 14, l.y + 6, LEFT_PAGE.size.x - 28, 34, 26, INK)
	_den_subtitle = _lbl(page, "", l.x + 14, l.y + 40, LEFT_PAGE.size.x - 28, 22, 14, INK_SOFT)
	_rule(page, l.x + 14, l.y + 62, LEFT_PAGE.size.x - 28)

	for i in DEN_ROWS:
		var y := l.y + 72 + RULE_PITCH * i
		_rule(page, l.x + 14, y + 21, LEFT_PAGE.size.x - 28)

		var row := Control.new()
		row.position = Vector2(l.x + 14, y)
		row.size = Vector2(LEFT_PAGE.size.x - 28, RULE_PITCH - 2)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		page.add_child(row)

		# No icon on the rung, deliberately. A row is 26px tall, and the catalog runs to
		# a 150x200 bookshelf — fitting that into ~20px needs a tenth scale, which on
		# nearest-filtered pixel art is mush. The names are short and the detail panel
		# carries the art at a size it survives.
		_den_rows.append({
			"root": row,
			"mark": _dot(row, Vector2(2, 9), 4, PAW),
			"name": _lbl(row, "", 24, 1, 176, 20, 14, INK),
			"state": _lbl(row, "", 200, 1, 112, 20, 13, INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT),
		})
		row.gui_input.connect(_on_den_row_input.bind(i))

	_den_empty = _lbl(page, "", l.x + 24, l.y + 150, LEFT_PAGE.size.x - 48, 90, 15, INK_FAINT,
		HORIZONTAL_ALIGNMENT_CENTER)
	_den_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_den_detail(page)
	_den_find_widgets = _build_find_panel(page,
		Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 212))
	_build_den_room_panel(page)


func _build_den_detail(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 8),
		PANEL_LARGE.get_size(), PANEL_LARGE, PANEL_LARGE_MARGINS)
	_den_detail_title = _lbl(panel, "", 52, 12, 208, 24, 17, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_arrow_button(panel, ARROW_LEFT, -1, _step_den_find)
	_arrow_button(panel, ARROW_RIGHT, 1, _step_den_find)

	# The art sits in a fixed box and is only ever shrunk by a tidy fraction, never
	# fitted exactly — see _den_art_size().
	_den_detail_art = TextureRect.new()
	_den_detail_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_den_detail_art.stretch_mode = TextureRect.STRETCH_SCALE
	_den_detail_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_den_detail_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_den_detail_art)

	_den_detail_name = _lbl(panel, "", 130, 52, 168, 24, 17, INK)
	_den_detail_when = _lbl(panel, "", 130, 78, 168, 40, 13, INK_SOFT)
	_den_detail_when.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule(panel, 16, 146, PANEL_LARGE.get_width() - 32)
	_den_detail_where = _lbl(panel, "", 16, 152, PANEL_LARGE.get_width() - 32, 22, 13, INK_SOFT)


func _build_den_room_panel(page: Control) -> void:
	var panel := _panel(page, Vector2(RIGHT_PAGE.position.x + 4, RIGHT_PAGE.position.y + 320),
		PANEL_MEDIUM.get_size(), PANEL_MEDIUM, PANEL_MEDIUM_MARGINS)
	_lbl(panel, "The Room", 16, 5, 160, 22, 15, INK)
	_den_room_text = _lbl(panel, "", 16, 34, PANEL_MEDIUM.get_width() - 32, 20, 13, INK_SOFT)

	_den_tidy_button = Panel.new()
	_den_tidy_button.position = Vector2(16, 58)
	_den_tidy_button.size = Vector2(110, 24)
	_den_tidy_button.add_theme_stylebox_override("panel", _flat(PAW, 6))
	_den_tidy_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_den_tidy_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_den_tidy_button.gui_input.connect(_on_tidy_input)
	panel.add_child(_den_tidy_button)
	_lbl(_den_tidy_button, "Tidy up", 0, 2, 110, 20, 14, Color(1, 0.97, 0.92),
		HORIZONTAL_ALIGNMENT_CENTER)
	_den_tidy_hint = _lbl(panel, "", 134, 60, PANEL_MEDIUM.get_width() - 150, 20, 12, INK_FAINT)


## Which slice of the ladder is on screen — the page holding the selection, so
## stepping past the end of one turns to the next.
func _den_page() -> int:
	return _den_selected / DEN_ROWS


func _on_den_row_input(event: InputEvent, row: int) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT \
			or not event.pressed:
		return
	var index := _den_page() * DEN_ROWS + row
	if _den == null or index >= _den.catalog_size():
		return
	_den_selected = index
	Audio.play("open", 1.25)
	_refresh_den()


func _step_den_find(step: int) -> void:
	if _den == null or _den.catalog_size() == 0:
		return
	_den_selected = wrapi(_den_selected + step, 0, _den.catalog_size())
	Audio.play("open", 1.25)
	_refresh_den()


func _on_tidy_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT \
			or not event.pressed:
		return
	if _den == null:
		return
	_den.restore_defaults()
	Audio.play("drop")
	_den_tidy_hint.text = "Everything's back where it started."


## Pixel art shrunk by an arbitrary factor drops rows unevenly, so the detail art picks
## the largest tidy fraction that fits its box — the same rule, and the same ratios, the
## drawer's cells use.
func _den_art_size(tex: Texture2D, box: float) -> Vector2:
	var src := tex.get_size()
	var longest := maxf(src.x, src.y)
	if longest <= 0.0:
		return Vector2(box, box)
	for r in DenInventory.ICON_RATIOS:
		if longest * r <= box:
			return src * r
	return src * (box / longest)


func _refresh_den() -> void:
	if _den == null or _stats == null:
		return
	# Transient confirmation, so any refresh at all clears it.
	_den_tidy_hint.text = ""
	var entries: Array = _den.ladder(_stats.total_focus())
	_den_selected = clampi(_den_selected, 0, maxi(0, entries.size() - 1))

	# Just the count here — how it splits between room and drawer is the Room panel's
	# line, and saying it twice on one spread reads as a mistake.
	var found := _den.found_count()
	_den_subtitle.text = "%d of %d found" % [found, entries.size()]
	_den_empty.text = "" if found > 0 else \
		"Nothing yet. Your fox brings something home for every half hour you focus."

	var start := _den_page() * DEN_ROWS
	for i in _den_rows.size():
		_paint_den_row(_den_rows[i], entries, start + i)

	_refresh_den_detail(entries)
	_fill_find_panel(_den_find_widgets, _stats.total_focus())

	var out := _den.placed_count()
	_den_room_text.text = "%d %s out on display, %d in the drawer." % [
		out, "find" if out == 1 else "finds", maxi(0, found - out)]


func _paint_den_row(row: Dictionary, entries: Array, index: int) -> void:
	var root: Control = row["root"]
	if index >= entries.size():
		root.visible = false
		return
	root.visible = true

	var e: Dictionary = entries[index]
	var earned: bool = e["earned"]

	(row["name"] as Label).text = str(e["name"])
	(row["name"] as Label).add_theme_color_override("font_color", INK if earned else INK_FAINT)
	(row["mark"] as Panel).visible = index == _den_selected

	var state: Label = row["state"]
	if not earned:
		state.text = _threshold_text(int(e["unlock_min"]))
		state.add_theme_color_override("font_color", INK_FAINT)
	elif bool(e["placed"]):
		state.text = "in the room"
		state.add_theme_color_override("font_color", GREEN)
	else:
		state.text = "in the drawer"
		state.add_theme_color_override("font_color", INK_SOFT)
	root.tooltip_text = str(e["name"])


func _refresh_den_detail(entries: Array) -> void:
	if entries.is_empty():
		return
	var e: Dictionary = entries[_den_selected]
	var earned: bool = e["earned"]
	var tex := e["texture"] as Texture2D

	_den_detail_title.text = "Find %d of %d" % [_den_selected + 1, entries.size()]

	# Centred in a 96px box so a 34px clock and a 150x200 bookshelf both sit squarely
	# rather than one hugging a corner.
	_den_detail_art.visible = earned and tex != null
	if _den_detail_art.visible:
		_den_detail_art.texture = tex
		_den_detail_art.size = _den_art_size(tex, 90.0)
		_den_detail_art.position = Vector2(16, 54) + (Vector2(96, 96) - _den_detail_art.size) * 0.5

	_den_detail_name.text = str(e["name"]) if earned else "Not home yet"
	_den_detail_name.add_theme_color_override("font_color", INK if earned else INK_SOFT)

	var at := int(e["unlock_min"])
	if earned:
		_den_detail_when.text = "Came home at %s of focus." % _threshold_text(at)
		_den_detail_where.text = "In the room." if bool(e["placed"]) else "In the drawer."
		_den_detail_where.add_theme_color_override("font_color",
			GREEN if bool(e["placed"]) else INK_SOFT)
	else:
		var remaining := int(e["remaining"])
		_den_detail_when.text = "Arrives at %s of focus." % _threshold_text(at)
		_den_detail_where.text = "%d %s to go." % [
			remaining, "minute" if remaining == 1 else "minutes"]
		_den_detail_where.add_theme_color_override("font_color", INK_FAINT)


## "30m" / "3h" / "1h 30m" — thresholds are round numbers, so the common case is a
## whole number of hours and printing "180m" for it reads as a stopwatch.
func _threshold_text(minutes: int) -> String:
	if minutes < 60:
		return "%dm" % minutes
	if minutes % 60 == 0:
		return "%dh" % (minutes / 60)
	return "%dh %dm" % [minutes / 60, minutes % 60]


# --- Refresh -----------------------------------------------------------------

func refresh(stats: StatsStore, den: Den = null) -> void:
	_stats = stats
	_den = den
	_refresh_current()


func _refresh_current() -> void:
	if _stats == null:
		return
	match _current:
		Page.TODAY: _refresh_today()
		Page.LOGBOOK: _refresh_logbook()
		Page.HISTORY: _refresh_history()
		Page.DEN: _refresh_den()
		Page.ACHIEVEMENTS: _refresh_achievements()


func _refresh_today() -> void:
	var total_focus := _stats.total_focus()
	var key := _stats.today_key()
	var today := _stats.day(key)
	var score: Dictionary = _stats.day_score(key)

	_score_value.text = "%d" % int(score["score"])
	_score_value.add_theme_color_override("font_color", _tier_colour(str(score["tier"])))
	_score_tier.text = _tier_text(str(score["tier"]), bool(score["needs_rest"]))

	_greeting.text = "You and your fox have focused for %s together." % _long_duration(total_focus)

	var sessions := int(today.get("sessions", 0))
	var focus_min := int(round(float(today.get("focus", 0.0)) / 60.0))
	var breaks := int(today.get("breaks", 0))
	# Breaks have no configured target — three a day is a gentle suggestion, not a goal.
	_set_goal(_goal_rows[0], sessions, _stats.goal_sessions, "%d / %d")
	_set_goal(_goal_rows[1], focus_min, _stats.goal_focus_min, "%dm / %dm")
	_set_goal(_goal_rows[2], breaks, 3, "%d / %d")

	var tasks := _stats.today_tasks()
	_tasks.text = "" if tasks.is_empty() else "Today's focus: " + " · ".join(tasks.slice(maxi(0, tasks.size() - 4)))

	_refresh_week()
	_fill_find_panel(_find_widgets, total_focus)

	_totals[0].text = "%d" % _stats.total_sessions()
	_totals[1].text = _short_duration(total_focus)
	_totals[2].text = "%d" % _stats.best_trail()


func _set_goal(row: Dictionary, value: int, goal: int, format: String) -> void:
	(row["value"] as Label).text = format % [value, goal]
	var pct := clampf(float(value) / maxf(1.0, float(goal)), 0.0, 1.0)
	(row["fill"] as Panel).size.x = float(row["width"]) * pct


func _refresh_week() -> void:
	if _stats == null:
		return
	var week := _stats.week_activity(_week_offset)
	for i in 7:
		var d: Dictionary = week[i]
		_week_paws[i].active = bool(d["active"])
		_week_days[i].modulate.a = 0.45 if bool(d["future"]) else 1.0
		_week_days[i].add_theme_color_override("font_color", INK if bool(d["today"]) else INK_SOFT)

	if _week_offset == 0:
		_week_title.text = "This Week"
		var trail := _stats.current_trail()
		_week_footer.text = "No trail yet — start a session to leave a pawprint." if trail <= 0 \
			else "%d-day pawprint trail. Keep going!" % trail
	else:
		var ago := -_week_offset
		_week_title.text = "Last Week" if ago == 1 else "%d Weeks Ago" % ago
		var active := 0
		var focus := 0.0
		for d in week:
			if bool(d["active"]):
				active += 1
			focus += float(d["focus"])
		_week_footer.text = "%d active %s · %s focused." % [
			active, "day" if active == 1 else "days", _short_duration(focus)]


func _fill_find_panel(w: Dictionary, total_focus: float) -> void:
	var text: Label = w["text"]
	var bar: Panel = w["bar"]
	var fill: Panel = w["fill"]
	var count: Label = w["count"]
	if _den == null:
		text.text = ""
		fill.size.x = 0
		count.text = ""
		return
	var found := "%d of %d" % [_den.found_count(), _den.catalog_size()]
	var next := _den.next_find(total_focus)
	if next.is_empty():
		text.text = "Your den is full — every find has made it home."
		fill.size.x = bar.size.x
		count.text = found
		return
	var remaining := int(next["remaining"])
	text.text = "%d more %s for %s." % [
		remaining, "minute" if remaining == 1 else "minutes", str(next["name"])]
	var window := maxf(1.0, float(next["window"]))
	fill.size.x = bar.size.x * clampf(float(next["done"]) / window, 0.0, 1.0)
	count.text = found


# --- Builders ----------------------------------------------------------------

## A light panel from one of the two assembled sprites, stretched by nine-patch so
## the painted border and the baked header survive any size.
func _panel(parent: Control, at: Vector2, panel_size: Vector2, tex: Texture2D, margins: Vector4) -> Control:
	var np := NinePatchRect.new()
	np.texture = tex
	np.position = at
	np.size = panel_size
	np.patch_margin_left = int(margins.x)
	np.patch_margin_top = int(margins.y)
	np.patch_margin_right = int(margins.z)
	np.patch_margin_bottom = int(margins.w)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(np)
	return np


## One ruled line, tiled to `width`. Returns its baseline y so callers can sit text
## on the line rather than guess at it.
func _rule(parent: Control, x: float, y: float, width: float) -> float:
	var line := TextureRect.new()
	line.texture = RULE
	line.stretch_mode = TextureRect.STRETCH_TILE
	line.position = Vector2(x, y)
	line.size = Vector2(width, RULE.get_height())
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return y + RULE.get_height()


func _lbl(parent: Control, text: String, x: float, y: float, w: float, h: float,
		fsize: int, colour: Color, halign := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, h)
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", colour)
	lbl.horizontal_alignment = halign
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	return lbl


func _flat(fill: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	return sb


# --- Formatting --------------------------------------------------------------

func _tier_colour(tier: String) -> Color:
	match tier:
		"gold": return Color("d9a12b")
		"silver": return Color("8fa0ab")
		"bronze": return Color("b0703a")
		_: return INK_SOFT


## `is_today` matters for the untiered case only: a day that scored nothing is still
## young if it's today and was simply a quiet one if it isn't.
func _tier_text(tier: String, needs_rest: bool, is_today := true) -> String:
	if needs_rest:
		return "Remember to rest."
	match tier:
		"gold": return "Gold day. Outstanding."
		"silver": return "Silver day. Goal met."
		"bronze": return "Bronze day. Good going."
		_: return "The day is still young." if is_today else "A quiet day."


func _kind_name(kind: String) -> String:
	match kind:
		"short": return "Break"
		"long": return "Long break"
		_: return "Focus"


func _clock_time(ts: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d:%02d" % [t.hour, t.minute]


## "Friday 7 August" — the heading on the written page.
func _long_date(key: String) -> String:
	var d := _key_to_dict(key)
	var weekday := int(Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_dict(d))).weekday)
	return "%s %d %s" % [WEEKDAYS[weekday], int(d["day"]), MONTHS[int(d["month"])]]


## "7 Aug" — the compact form for the panel header, which is only 208px wide.
func _short_date(key: String) -> String:
	var d := _key_to_dict(key)
	return "%d %s" % [int(d["day"]), MONTHS[int(d["month"])].substr(0, 3)]


static func _key_to_dict(key: String) -> Dictionary:
	var parts := key.split("-")
	return {
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0,
	}


func _short_duration(seconds: float) -> String:
	var mins := int(round(seconds / 60.0))
	if mins < 60:
		return "%dm" % mins
	return "%dh %dm" % [mins / 60, mins % 60]


func _long_duration(seconds: float) -> String:
	var mins := int(round(seconds / 60.0))
	if mins < 1:
		return "no time at all yet"
	if mins < 60:
		return "%d %s" % [mins, "minute" if mins == 1 else "minutes"]
	return "%dh %dm" % [mins / 60, mins % 60]
