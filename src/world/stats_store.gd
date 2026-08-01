extends RefCounted
class_name StatsStore

## Tracks and persists focus history so the journal + stats bar can show real
## numbers. One entry per calendar day; everything else is derived on demand.

const PATH := "user://focus_fox_stats.cfg"
const DAY := 86400
## How long the user can be idle between sessions before the run is considered
## broken. Resume within this window and back-to-back sessions keep the streak.
const STREAK_GRACE := 1800  # 30 minutes

# "YYYY-MM-DD" -> {"sessions": int, "focus": float (seconds), "breaks": int}
var days := {}
# Longest run of back-to-back sessions (focus or break) in continued use.
var longest_streak := 0
var current_streak := 0
var last_session_end := 0  # unix seconds of the most recent completed session


func load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var stored = cfg.get_value("history", "days", {})
	if stored is Dictionary:
		days = stored
	longest_streak = int(cfg.get_value("history", "longest_streak", 0))
	current_streak = int(cfg.get_value("history", "current_streak", 0))
	last_session_end = int(cfg.get_value("history", "last_session_end", 0))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("history", "days", days)
	cfg.set_value("history", "longest_streak", longest_streak)
	cfg.set_value("history", "current_streak", current_streak)
	cfg.set_value("history", "last_session_end", last_session_end)
	cfg.save(PATH)


# --- Recording -------------------------------------------------------------

func record_focus(seconds: float, started_at: int, task := "") -> void:
	var e := _entry(_today_key())
	e["sessions"] = int(e["sessions"]) + 1
	e["focus"] = float(e["focus"]) + maxf(0.0, seconds)
	var trimmed := task.strip_edges()
	if trimmed != "":
		var tasks: Array = e.get("tasks", [])
		tasks.append(trimmed)
		e["tasks"] = tasks
	_register_session(started_at)
	save()


func record_break(started_at: int) -> void:
	var e := _entry(_today_key())
	e["breaks"] = int(e["breaks"]) + 1
	_register_session(started_at)
	save()


## Extends the back-to-back streak if this session began soon after the last one
## ended; otherwise it starts a fresh streak of 1.
func _register_session(started_at: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	if last_session_end > 0 and started_at - last_session_end <= STREAK_GRACE:
		current_streak += 1
	else:
		current_streak = 1
	longest_streak = maxi(longest_streak, current_streak)
	last_session_end = now


# --- Derived views ---------------------------------------------------------

func today() -> Dictionary:
	return days.get(_today_key(), {"sessions": 0, "focus": 0.0, "breaks": 0})


func today_tasks() -> Array:
	return days.get(_today_key(), {}).get("tasks", [])


func total_sessions() -> int:
	var n := 0
	for k in days:
		n += int(days[k].get("sessions", 0))
	return n


func total_focus() -> float:
	var s := 0.0
	for k in days:
		s += float(days[k].get("focus", 0.0))
	return s


func total_breaks() -> int:
	var n := 0
	for k in days:
		n += int(days[k].get("breaks", 0))
	return n


## Total number of distinct calendar days on which any session was recorded.
## Used by AchievementStore for "Back Tomorrow?", "The Fox Remembers", etc.
func total_days_used() -> int:
	var n := 0
	for k in days:
		if _active(k):
			n += 1
	return n


## Consecutive active days ending today (or yesterday, so a fresh day doesn't
## drop the trail before you've focused yet).
func current_trail() -> int:
	var now := Time.get_unix_time_from_system()
	var cur := now
	if not _active(_key_from_unix(cur)):
		cur -= DAY
		if not _active(_key_from_unix(cur)):
			return 0
	var count := 0
	while _active(_key_from_unix(cur)):
		count += 1
		cur -= DAY
	return count


## Longest run of consecutive active days ever recorded.
func best_trail() -> int:
	var idx := {}
	for k in days:
		if _active(k):
			idx[_day_index(k)] = true
	var best := 0
	for i in idx:
		if not idx.has(i - 1):  # start of a run
			var run := 0
			var j: int = i
			while idx.has(j):
				run += 1
				j += 1
			best = maxi(best, run)
	return best


## Mon..Sun for the current week: [{active, future}, ...]
func week_activity() -> Array:
	var now := Time.get_datetime_dict_from_system()
	var since_monday := (int(now.weekday) + 6) % 7
	var monday_ts := Time.get_unix_time_from_system() - since_monday * DAY
	var result := []
	for i in 7:
		var day_ts: float = monday_ts + i * DAY
		result.append({
			"active": _active(_key_from_unix(day_ts)),
			"future": i > since_monday,
		})
	return result


# --- Helpers ---------------------------------------------------------------

func _entry(key: String) -> Dictionary:
	if not days.has(key):
		days[key] = {"sessions": 0, "focus": 0.0, "breaks": 0}
	return days[key]


func _active(key: String) -> bool:
	return days.has(key) and int(days[key].get("sessions", 0)) > 0


func _today_key() -> String:
	return _key_from_dict(Time.get_date_dict_from_system())


func _key_from_unix(ts: float) -> String:
	return _key_from_dict(Time.get_date_dict_from_unix_time(int(ts)))


static func _key_from_dict(d: Dictionary) -> String:
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


static func _day_index(key: String) -> int:
	var parts := key.split("-")
	var d := {
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0,
	}
	return int(Time.get_unix_time_from_datetime_dict(d) / DAY)
