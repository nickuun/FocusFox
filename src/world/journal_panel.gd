extends Control
class_name JournalPanel

## Full-window "Fox Journal" overlay. Builds its layout in code and renders the
## numbers handed to it by StatsStore via refresh().

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")

const BG := Color("fbe7c4")
const INK := Color(0.30, 0.19, 0.11)
const INK_SOFT := Color(0.30, 0.19, 0.11, 0.72)
const CARD_BG := Color("fff4db")
const CARD_BORDER := Color("e7c08f")
const INSET_BG := Color("f4dfb6")
const PAW := Color("8a5630")
const GREEN := Color("4a8f3c")
const ORANGE := Color("cf7a2e")
const RUST := Color("b6502e")
const BLUE := Color("3f6ea3")

const DAY_NAMES := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const DEN_FINDS := [
	"a lamp", "a soft rug", "a bookshelf", "a cozy blanket",
	"a potted fern", "a little painting", "a warm cushion", "a tiny clock",
]
## A den find every this many minutes of focus (session length is configurable,
## so we reward time spent, not session count).
const DEN_STEP_MIN := 60

var _subtitle: Label
var _today_tasks_lbl: Label
var _today_sessions: Label
var _today_time: Label
var _today_breaks: Label
var _paws: Array[PawIcon] = []
var _day_labels: Array[Label] = []
var _trail_footer: Label
var _at_sessions: Label
var _at_focus: Label
var _at_best_trail: Label
var _at_longest: Label
var _at_breaks: Label
var _den_text: Label
var _den_bar: ProgressBar
var _den_count: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_lbl(self, "Fox Journal", 0, 14, 960, 52, 44, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle = _lbl(self, "", 0, 70, 960, 26, 20, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_today_tasks_lbl = _lbl(self, "", 0, 96, 960, 20, 14, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)

	_build_today()
	_build_week()
	_build_all_time()
	_build_den()


func _build_today() -> void:
	var card := _card("Today", 24, 116, 250, 152)
	_today_sessions = _stat_row(card, 16, 50, "0", "sessions", GREEN)
	_today_time = _stat_row(card, 16, 88, "0m", "focused", GREEN)
	_today_breaks = _stat_row(card, 16, 126, "0", "breaks", ORANGE)


func _build_week() -> void:
	var card := _card("This Week", 290, 116, 646, 152)
	var inset := Panel.new()
	inset.position = Vector2(16, 40)
	inset.size = Vector2(614, 70)
	inset.add_theme_stylebox_override("panel", _stylebox(INSET_BG, INSET_BG, 0, 12))
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inset)

	var col_w := 614.0 / 7.0
	for i in 7:
		var cx := col_w * (i + 0.5)
		_day_labels.append(_lbl(inset, DAY_NAMES[i], cx - 40, 6, 80, 22, 17, INK, HORIZONTAL_ALIGNMENT_CENTER))
		var paw := PawIcon.new()
		paw.paw_color = PAW
		paw.size = Vector2(40, 40)
		paw.position = Vector2(cx - 20, 28)
		paw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(paw)
		_paws.append(paw)

	_trail_footer = _lbl(card, "", 0, 120, 646, 26, 18, INK, HORIZONTAL_ALIGNMENT_CENTER)


func _build_all_time() -> void:
	var card := _card("All Time", 24, 284, 912, 108)
	var cols := [
		["0", "sessions", GREEN],
		["0m", "total focused", GREEN],
		["0", "best trail", RUST],
		["0m", "longest streak", BLUE],
		["0", "breaks taken", INK],
	]
	var col_w := 912.0 / 5.0
	var labels: Array[Label] = []
	for i in cols.size():
		var x := col_w * i
		var number := _lbl(card, cols[i][0], x, 40, col_w, 38, 32, cols[i][2], HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(card, cols[i][1], x, 80, col_w, 22, 16, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		labels.append(number)
	_at_sessions = labels[0]
	_at_focus = labels[1]
	_at_best_trail = labels[2]
	_at_longest = labels[3]
	_at_breaks = labels[4]


func _build_den() -> void:
	var card := _card("Next Den Find", 24, 400, 912, 108)
	_den_text = _lbl(card, "", 24, 44, 760, 28, 18, INK, HORIZONTAL_ALIGNMENT_LEFT)
	_den_bar = ProgressBar.new()
	_den_bar.position = Vector2(24, 78)
	_den_bar.size = Vector2(620, 22)
	_den_bar.min_value = 0
	_den_bar.max_value = DEN_STEP_MIN
	_den_bar.show_percentage = false
	_den_bar.add_theme_stylebox_override("background", _stylebox(INSET_BG, CARD_BORDER, 1, 11))
	_den_bar.add_theme_stylebox_override("fill", _stylebox(GREEN, GREEN, 0, 11))
	card.add_child(_den_bar)
	_den_count = _lbl(card, 654, 78, 234, 24, 18, INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	_den_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Refreshes every dynamic number from the store.
func refresh(stats: StatsStore) -> void:
	var total_focus := stats.total_focus()
	_subtitle.text = "You and your fox have focused for %s together." % _long_duration(total_focus)

	var today: Dictionary = stats.today()
	_today_sessions.text = "%d" % int(today.get("sessions", 0))
	_set_unit(_today_sessions, _plural(int(today.get("sessions", 0)), "session", "sessions"))
	_today_time.text = _short_duration(float(today.get("focus", 0.0)))
	_today_breaks.text = "%d" % int(today.get("breaks", 0))
	_set_unit(_today_breaks, _plural(int(today.get("breaks", 0)), "break", "breaks"))

	var week := stats.week_activity()
	for i in 7:
		var d: Dictionary = week[i]
		_paws[i].active = bool(d.get("active", false))
		_day_labels[i].modulate.a = 0.45 if bool(d.get("future", false)) else 1.0

	var trail := stats.current_trail()
	if trail <= 0:
		_trail_footer.text = "No trail yet — start a session to leave a pawprint."
	else:
		_trail_footer.text = "%d-day pawprint trail. Keep going!" % trail

	_at_sessions.text = "%d" % stats.total_sessions()
	_at_focus.text = _short_duration(total_focus)
	_at_best_trail.text = "%d" % stats.best_trail()
	_at_longest.text = "%d" % stats.longest_streak
	_at_breaks.text = "%d" % stats.total_breaks()

	var focus_min := int(total_focus / 60.0)
	var in_cycle := focus_min % DEN_STEP_MIN
	var remaining := DEN_STEP_MIN - in_cycle
	var item: String = DEN_FINDS[(focus_min / DEN_STEP_MIN) % DEN_FINDS.size()]
	_den_text.text = "Focus for %d more %s to add %s to your den." % [remaining, _plural(remaining, "minute", "minutes"), item]
	_den_bar.value = in_cycle
	_den_count.text = "%d / %d min" % [in_cycle, DEN_STEP_MIN]

	var tasks := stats.today_tasks()
	if tasks.is_empty():
		_today_tasks_lbl.text = ""
	else:
		var shown: Array = tasks.slice(maxi(0, tasks.size() - 5))
		var line := "Today's focus: " + " · ".join(shown)
		if line.length() > 96:
			line = line.substr(0, 95) + "…"
		_today_tasks_lbl.text = line


# --- Builders --------------------------------------------------------------

func _card(title: String, x: float, y: float, w: float, h: float) -> Panel:
	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size = Vector2(w, h)
	card.add_theme_stylebox_override("panel", _stylebox(CARD_BG, CARD_BORDER, 2, 16))
	add_child(card)
	_lbl(card, title, 16, 8, w - 32, 30, 24, INK, HORIZONTAL_ALIGNMENT_LEFT)
	return card


## A big coloured number with a softer unit label to its right (e.g. "3 sessions").
func _stat_row(parent: Control, x: float, y: float, number: String, unit: String, colour: Color) -> Label:
	var num := _lbl(parent, number, x, y, 90, 34, 30, colour, HORIZONTAL_ALIGNMENT_LEFT)
	var unit_lbl := _lbl(parent, unit, x, y, 200, 34, 17, INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	unit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.set_meta("unit_label", unit_lbl)
	num.set_meta("unit_x", x)
	_reflow_unit(num)
	return num


## Repositions a stat row's unit label to sit just after its number.
func _reflow_unit(num: Label) -> void:
	if not num.has_meta("unit_label"):
		return
	var unit_lbl: Label = num.get_meta("unit_label")
	var base_x: float = num.get_meta("unit_x")
	var num_w := FONT.get_string_size(num.text, HORIZONTAL_ALIGNMENT_LEFT, -1, num.get_theme_font_size("font_size")).x
	unit_lbl.position.x = base_x + num_w + 8
	unit_lbl.position.y = num.position.y


func _set_unit(num: Label, unit: String) -> void:
	if num.has_meta("unit_label"):
		(num.get_meta("unit_label") as Label).text = unit
	_reflow_unit(num)


func _lbl(parent: Control, a, b = null, c = null, d = null, e = null, f = null, g = null, h = null) -> Label:
	# Two call shapes are supported:
	#   _lbl(parent, text, x, y, w, h, size, color, halign)
	#   _lbl(parent, x, y, w, h, size, color, halign)   (no text)
	var text := ""
	var x; var y; var w; var hgt; var fsize; var color; var halign
	if a is String:
		text = a; x = b; y = c; w = d; hgt = e; fsize = f; color = g; halign = h
	else:
		x = a; y = b; w = c; hgt = d; fsize = e; color = f; halign = g
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, hgt)
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", int(fsize))
	lbl.add_theme_color_override("font_color", color)
	if halign != null:
		lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	return lbl


func _stylebox(fill: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb


# --- Formatting ------------------------------------------------------------

func _short_duration(seconds: float) -> String:
	var mins := int(round(seconds / 60.0))
	if mins < 60:
		return "%dm" % mins
	return "%dh %dm" % [mins / 60, mins % 60]


func _long_duration(seconds: float) -> String:
	var mins := int(round(seconds / 60.0))
	if mins < 1:
		return "0m"
	if mins < 60:
		return _plural(mins, "minute", "minutes")
	return "%dh %dm" % [mins / 60, mins % 60]


static func _plural(n: int, one: String, many: String) -> String:
	return one if n == 1 else many
