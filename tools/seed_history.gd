extends SceneTree

## Dev tool — writes a plausible focus history so the journal, the stats bar and
## the den's drawer have something to show without grinding real sessions first.
##
##   "<godot>" --headless -s tools/seed_history.gd --path .
##
## The existing history is copied to focus_fox_stats.cfg.bak before anything is
## written, so this is undoable: delete the seeded file and rename the backup back.
## Pass --wipe-den to also clear the den layout and start the room empty.
##
## TARGET_FOCUS_MIN decides how much of the den catalog is unlocked, since finds
## unlock on total focus minutes. 440 clears everything in den.gd except the tiny
## clock at 480, which leaves the journal with a real "next find" to count down to.

## 450 clears everything in den.gd up to the warm cushion at 420 and leaves the
## tiny clock at 480 pending, so the journal has a real find to count down to.
const TARGET_FOCUS_MIN := 450
const DAYS_BACK := 27
## Consecutive active days ending today, so the journal's trail isn't broken.
const TRAIL_DAYS := 5
const ACTIVE_CHANCE := 0.4
const EXTRA_SESSION_MIN := Vector2i(20, 45)
const DAY := 86400

const TODAY_TASKS := ["inventory drawer", "den sprites", "journal polish"]


func _init() -> void:
	# Fixed seed so re-running gives the same history rather than a new one.
	seed(20260805)

	var stats := StatsStore.new()
	var backed_up := _backup(StatsStore.PATH)

	var now := int(Time.get_unix_time_from_system())
	var keys := _pick_active_days(now)
	var days := {}
	for key in keys:
		days[key] = {"sessions": 0, "focus": 0.0, "breaks": 0}

	var total_min := 0

	# Every day on the list gets a session of its own first. StatsStore only counts
	# a day as active if it recorded a focus session, so days left with nothing but
	# breaks would silently break the trail and the week strip. The share scales to
	# however many days came out of the draw, so the budget always stretches.
	var share := maxi(10, int(float(TARGET_FOCUS_MIN) / float(keys.size()) * 0.75))
	for key in keys:
		total_min += _add_session(days, key, mini(randi_range(share, share + 10), TARGET_FOCUS_MIN - total_min))

	# Whatever's left of the budget goes on second and third sessions at random,
	# which is what makes the per-day counts uneven the way real use is.
	while total_min < TARGET_FOCUS_MIN:
		var length := mini(randi_range(EXTRA_SESSION_MIN.x, EXTRA_SESSION_MIN.y), TARGET_FOCUS_MIN - total_min)
		total_min += _add_session(days, keys[randi() % keys.size()], length)

	# A break or two on most days, and today's task list so that row isn't blank.
	var breaks := 0
	for key in keys:
		var b := randi_range(0, 2)
		days[key]["breaks"] = b
		breaks += b
	var today := _key(now)
	if days.has(today):
		days[today]["tasks"] = TODAY_TASKS.duplicate()

	stats.days = days
	stats.longest_streak = 7
	stats.current_streak = 3
	stats.last_session_end = now - 2700  # 45 min ago, so the streak grace has lapsed

	stats.save()

	# Literal rather than Den.PATH: den.gd calls the Achievements autoload, and -s
	# scripts run without autoloads, so referencing it here won't compile.
	var den_save := "user://focus_fox_den.cfg"
	if "--wipe-den" in OS.get_cmdline_user_args() or "--wipe-den" in OS.get_cmdline_args():
		if FileAccess.file_exists(den_save):
			DirAccess.remove_absolute(den_save)
			print("  den layout cleared (%s)" % den_save)

	_report(stats, total_min, breaks, backed_up)
	quit()


## Every day that gets any activity: the trail ending today, plus a scattering
## further back.
func _pick_active_days(now: int) -> Array:
	var keys := []
	for i in range(DAYS_BACK, -1, -1):
		if i < TRAIL_DAYS or randf() < ACTIVE_CHANCE:
			keys.append(_key(now - i * DAY))
	# Guarantees the while-loop below always has somewhere to put a session.
	if keys.is_empty():
		keys.append(_key(now))
	return keys


## Records one focus session on `key` and returns the minutes actually added, so
## the caller can keep a running total. Zero-length sessions are skipped, which is
## what stops the budget clamp from adding an empty one at the very end.
func _add_session(days: Dictionary, key: String, minutes: int) -> int:
	if minutes <= 0:
		return 0
	var e: Dictionary = days[key]
	e["sessions"] = int(e["sessions"]) + 1
	e["focus"] = float(e["focus"]) + float(minutes) * 60.0
	return minutes


func _key(ts: int) -> String:
	var d := Time.get_date_dict_from_unix_time(ts)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Keeps a copy of the history from before seeding ever ran. Deliberately refuses
## to overwrite an existing backup: re-running the tool would otherwise replace the
## real history with a previous seed and the original would be gone for good.
func _backup(path: String) -> bool:
	if not FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		return false
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		return false
	var data := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(path + ".bak", FileAccess.WRITE)
	if dst == null:
		return false
	dst.store_buffer(data)
	dst.close()
	return true


func _report(stats: StatsStore, total_min: int, breaks: int, backed_up: bool) -> void:
	print("Seeded focus history -> %s" % ProjectSettings.globalize_path(StatsStore.PATH))
	if backed_up:
		print("  pre-seed history backed up to %s.bak" % StatsStore.PATH)
	else:
		print("  no backup written (a .bak already exists, or there was no history)")
	print("  %d active days, %d sessions, %dh %02dm focused, %d breaks" % [
		stats.days.size(), stats.total_sessions(), total_min / 60, total_min % 60, breaks,
	])
	print("  trail today: %d days, best trail: %d" % [stats.current_trail(), stats.best_trail()])

	# What the den will actually do with this, so it's obvious when a find is held
	# up by a missing sprite rather than by focus time.
	var focus_min := int(stats.total_focus() / 60.0)
	print("  den catalog at %d focus minutes:" % focus_min)
	for item in DenCatalog.ITEMS:
		var at := int(item["unlock_min"])
		var state := "locked (needs %d min)" % at
		if focus_min >= at:
			state = "UNLOCKED" if DenCatalog.has_art(item) else "waiting on art"
		print("    %-10s %-20s %s" % [item["id"], item["name"], state])
