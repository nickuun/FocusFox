extends RefCounted
class_name StatsStore

## Tracks and persists focus history so the journal + stats bar can show real
## numbers. One entry per calendar day; everything else is derived on demand.

const PATH := "user://focus_fox_stats.cfg"
const DAY := 86400
## How long the user can be idle between sessions before the run is considered
## broken. Resume within this window and back-to-back sessions keep the streak.
const STREAK_GRACE := 1800  # 30 minutes

## The event log is capped so the config file can't grow without bound. At a few
## sessions a day this is years of history; the oldest entries fall off the front.
## The `days` aggregates are never trimmed, so totals and trails stay correct even
## once the detailed rows behind them have aged out.
const MAX_EVENTS := 2000

## Score tiers, as a percentage of the daily goal. Gold is deliberately above 100
## so it means "beat your goal by half again", not merely "met it".
const TIER_BRONZE := 50
const TIER_SILVER := 100
const TIER_GOLD := 150

# "YYYY-MM-DD" -> {"sessions": int, "focus": float (seconds), "breaks": int}
var days := {}
## Per-session rows, oldest first. {ts, kind, seconds, task}
##   ts      unix seconds the session *started* — what the logbook prints
##   kind    "focus" | "short" | "long"
##   seconds how long it ran
##   task    the focus session's label, "" for breaks
## Only populated from the build that introduced it; older days have aggregates
## but no rows, so anything reading this must handle an empty day gracefully.
var events: Array = []
# Longest run of back-to-back sessions (focus or break) in continued use.
var longest_streak := 0
var current_streak := 0
var last_session_end := 0  # unix seconds of the most recent completed session

## Daily targets behind the Today page's progress bars and the day score. Stored
## here rather than in focus_fox.cfg with the other settings so that day_score()
## stays self-contained — the store can answer "how did that day go?" without
## reaching into the launcher.
var goal_sessions := 4
var goal_focus_min := 100


func load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var stored = cfg.get_value("history", "days", {})
	if stored is Dictionary:
		days = stored
	var log_ = cfg.get_value("history", "events", [])
	if log_ is Array:
		events = log_
	longest_streak = int(cfg.get_value("history", "longest_streak", 0))
	current_streak = int(cfg.get_value("history", "current_streak", 0))
	last_session_end = int(cfg.get_value("history", "last_session_end", 0))
	goal_sessions = maxi(1, int(cfg.get_value("goals", "sessions", goal_sessions)))
	goal_focus_min = maxi(1, int(cfg.get_value("goals", "focus_min", goal_focus_min)))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("history", "days", days)
	cfg.set_value("history", "events", events)
	cfg.set_value("history", "longest_streak", longest_streak)
	cfg.set_value("history", "current_streak", current_streak)
	cfg.set_value("history", "last_session_end", last_session_end)
	cfg.set_value("goals", "sessions", goal_sessions)
	cfg.set_value("goals", "focus_min", goal_focus_min)
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
	append_event(started_at, "focus", seconds, trimmed)
	_register_session(started_at)
	save()


## `kind` is the clock's session id ("short" / "long") so the logbook can tell a
## five-minute breather from a long one. Anything that isn't a known break id is
## filed as a short break rather than dropped.
func record_break(seconds: float, started_at: int, kind := "short") -> void:
	var e := _entry(_today_key())
	e["breaks"] = int(e["breaks"]) + 1
	append_event(started_at, "long" if kind == "long" else "short", seconds, "")
	_register_session(started_at)
	save()


## Appends one row to the log and trims the front if it has outgrown the cap.
## Public so the seeding tool can build a history without going through the
## recording path, which would stamp everything with the current time.
func append_event(ts: int, kind: String, seconds: float, task := "") -> void:
	events.append({
		"ts": ts,
		"kind": kind,
		"seconds": maxf(0.0, seconds),
		"task": task,
	})
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)


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
	return day(_today_key())


func today_tasks() -> Array:
	return day(_today_key()).get("tasks", [])


func today_key() -> String:
	return _today_key()


## The aggregate for any day, present or not. Always returns a usable dictionary
## so callers never have to null-check a quiet day.
func day(key: String) -> Dictionary:
	return days.get(key, {"sessions": 0, "focus": 0.0, "breaks": 0, "tasks": []})


## The logbook rows for one day, oldest first. Empty for a day recorded before the
## event log existed — that's indistinguishable here from a day with no sessions,
## so the Logbook page leans on `day()` to tell "nothing happened" apart from
## "nothing was written down".
func day_events(key: String) -> Array:
	var out := []
	for ev in events:
		if _key_from_unix(float(ev.get("ts", 0))) == key:
			out.append(ev)
	out.sort_custom(func(a, b): return int(a.get("ts", 0)) < int(b.get("ts", 0)))
	return out


## How a day measured up against the daily goals.
##
## Focus time is weighted more heavily than session count because it's the harder
## and more honest number — four two-minute sessions shouldn't score like four real
## ones. `score` is uncapped so beating the goal is visible and gold is reachable;
## `goal_pct` is the clamped version, for progress bars.
##
## Breaks deliberately earn nothing. Resting shouldn't become another chore to
## optimise — but a day of solid focus with no breaks at all sets `needs_rest`, so
## the page can say something kind rather than nothing.
func day_score(key: String) -> Dictionary:
	var d := day(key)
	var sessions := int(d.get("sessions", 0))
	var focus_min := float(d.get("focus", 0.0)) / 60.0
	var breaks := int(d.get("breaks", 0))

	var raw := 0.6 * (focus_min / float(goal_focus_min)) + 0.4 * (float(sessions) / float(goal_sessions))
	var score := int(round(raw * 100.0))

	var tier := "none"
	if score >= TIER_GOLD:
		tier = "gold"
	elif score >= TIER_SILVER:
		tier = "silver"
	elif score >= TIER_BRONZE:
		tier = "bronze"

	return {
		"score": score,
		"tier": tier,
		"goal_pct": minf(1.0, raw),
		"sessions": sessions,
		"focus_min": focus_min,
		"breaks": breaks,
		"needs_rest": sessions >= 3 and breaks == 0,
	}


## The earliest day with a recorded session, or "" if nothing has been recorded.
## Bounds the ‹ › navigation on the History and Logbook pages so the player can't
## page back forever through empty months.
func first_active_day() -> String:
	var earliest := ""
	for k in days:
		if _active(k) and (earliest == "" or k < earliest):
			earliest = k
	return earliest


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


## Mon..Sun for one week: [{key, active, future, today, sessions, focus, breaks}, ...]
##
## `week_offset` steps whole weeks — 0 is the current week, -1 last week, and so on,
## so the journal's ‹ › can walk backwards through history.
func week_activity(week_offset := 0) -> Array:
	var now := Time.get_datetime_dict_from_system()
	var since_monday := (int(now.weekday) + 6) % 7
	var monday_ts := Time.get_unix_time_from_system() - since_monday * DAY + week_offset * 7 * DAY
	var today := _today_key()
	var result := []
	for i in 7:
		var day_ts: float = monday_ts + i * DAY
		var key := _key_from_unix(day_ts)
		var d := day(key)
		result.append({
			"key": key,
			"active": _active(key),
			"future": key > today,
			"today": key == today,
			"sessions": int(d.get("sessions", 0)),
			"focus": float(d.get("focus", 0.0)),
			"breaks": int(d.get("breaks", 0)),
		})
	return result


## One calendar month as a flat list of 42 cells (6 rows × 7 columns, Monday first),
## ready to drop straight into a grid. Leading and trailing cells that belong to the
## neighbouring months are included with `in_month == false` rather than left out, so
## the grid never has to reason about alignment — it just walks the array.
func month_activity(year: int, month: int) -> Array:
	var first := {"year": year, "month": month, "day": 1, "hour": 12, "minute": 0, "second": 0}
	var first_ts := Time.get_unix_time_from_datetime_dict(first)
	# weekday is 0=Sunday; shift so Monday is column 0.
	var lead := (int(Time.get_datetime_dict_from_unix_time(int(first_ts)).weekday) + 6) % 7
	var today := _today_key()

	var cells := []
	for i in 42:
		var ts := first_ts + (i - lead) * DAY
		var dd := Time.get_datetime_dict_from_unix_time(int(ts))
		var key := _key_from_dict(dd)
		var d := day(key)
		cells.append({
			"key": key,
			"day": int(dd.day),
			"in_month": int(dd.month) == month and int(dd.year) == year,
			"active": _active(key),
			"future": key > today,
			"today": key == today,
			"sessions": int(d.get("sessions", 0)),
			"focus": float(d.get("focus", 0.0)),
			"breaks": int(d.get("breaks", 0)),
		})
	return cells


## Totals across one month, for the summary strip under the grid.
func month_summary(year: int, month: int) -> Dictionary:
	var sessions := 0
	var focus := 0.0
	var breaks := 0
	var active := 0
	var best_key := ""
	var best_focus := 0.0
	for cell in month_activity(year, month):
		if not bool(cell["in_month"]):
			continue
		sessions += int(cell["sessions"])
		focus += float(cell["focus"])
		breaks += int(cell["breaks"])
		if bool(cell["active"]):
			active += 1
		if float(cell["focus"]) > best_focus:
			best_focus = float(cell["focus"])
			best_key = str(cell["key"])
	return {
		"sessions": sessions,
		"focus": focus,
		"breaks": breaks,
		"active_days": active,
		"best_day": best_key,
		"best_focus": best_focus,
	}


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
