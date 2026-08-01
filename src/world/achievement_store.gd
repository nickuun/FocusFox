extends Node

## AchievementStore — central hub for all 36 Focus Fox achievements.
##
## Owns definitions, per-achievement counters, persistence, and the Steam
## abstraction layer. Nothing outside this file ever calls Steam directly;
## swap the _steam_* helpers below when GodotSteam is installed.
##
## Usage from other scripts:
##   Achievements.unlock("tiny_victory")
##   Achievements.on_session_completed(duration_sec, session_id, stats)
##   Achievements.achievement_unlocked.connect(my_toast_handler)

signal achievement_unlocked(id: String, def: Dictionary)

const PATH := "user://focus_fox_achievements.cfg"

# ---------------------------------------------------------------------------
# Definitions
# Each entry: label, description, hidden (secret on Steam), and optional
# threshold used by check_* helpers. "earned" is set at runtime.
# ---------------------------------------------------------------------------
const DEFS: Dictionary = {
	# --- First Steps ---
	"welcome_home_fox":      { "label": "Welcome Home, Fox",       "desc": "Launch Focus Fox for the first time.",                    "hidden": false },
	"ready_to_focus":        { "label": "Ready to Focus",          "desc": "Start your first focus session.",                         "hidden": false },
	"tiny_victory":          { "label": "Tiny Victory",            "desc": "Complete your first focus session.",                      "hidden": false },
	"break_time":            { "label": "Break Time",              "desc": "Start your first short break.",                           "hidden": false },
	"proper_rest":           { "label": "Proper Rest",             "desc": "Start your first long break.",                            "hidden": false },
	"see_you_soon":          { "label": "See You Soon",            "desc": "End a session early.",                                    "hidden": false },

	# --- Session Milestones ---
	"one_paw_forward":       { "label": "One Paw Forward",         "desc": "Complete 3 focus sessions.",                             "hidden": false, "threshold": 3   },
	"finding_your_rhythm":   { "label": "Finding Your Rhythm",     "desc": "Complete 10 focus sessions.",                            "hidden": false, "threshold": 10  },
	"fox_flow":              { "label": "Fox Flow",                 "desc": "Complete 25 focus sessions.",                            "hidden": false, "threshold": 25  },
	"den_discipline":        { "label": "Den Discipline",           "desc": "Complete 50 focus sessions.",                            "hidden": false, "threshold": 50  },
	"deep_work_denizen":     { "label": "Deep Work Denizen",        "desc": "Complete 100 focus sessions.",                           "hidden": false, "threshold": 100 },
	"legend_of_the_little_fox": { "label": "Legend of the Little Fox", "desc": "Complete 250 focus sessions.",                       "hidden": false, "threshold": 250 },

	# --- Time-Based ---
	"five_good_minutes":     { "label": "Five Good Minutes",       "desc": "Complete a focus session of 5 minutes or less.",         "hidden": false },
	"classic_pomodoro":      { "label": "Classic Pomodoro",        "desc": "Complete a 25-minute focus session.",                    "hidden": false },
	"deep_focus":            { "label": "Deep Focus",              "desc": "Complete a focus session of 45 minutes or longer.",      "hidden": false },
	"marathon_nap_supervisor": { "label": "Marathon Nap Supervisor", "desc": "Complete a 90-minute focus session.",                  "hidden": false },
	"an_hour_well_spent":    { "label": "An Hour Well Spent",      "desc": "Reach 1 total hour of focus time.",                      "hidden": false },
	"a_workday_of_fox_time": { "label": "A Workday of Fox Time",   "desc": "Reach 8 total hours of focus time.",                     "hidden": false },

	# --- Streak & Consistency ---
	"back_tomorrow":         { "label": "Back Tomorrow?",          "desc": "Use Focus Fox on 2 different days.",                     "hidden": false, "threshold": 2  },
	"tiny_habit":            { "label": "Tiny Habit",              "desc": "Complete a focus session 3 days in a row.",              "hidden": false, "threshold": 3  },
	"week_of_whiskers":      { "label": "Week of Whiskers",        "desc": "Complete a focus session 7 days in a row.",              "hidden": false, "threshold": 7  },
	"the_fox_remembers":     { "label": "The Fox Remembers",       "desc": "Use Focus Fox on 14 different days total.",              "hidden": false, "threshold": 14 },
	"monthly_den_guest":     { "label": "Monthly Den Guest",       "desc": "Use Focus Fox on 30 different days total.",              "hidden": false, "threshold": 30 },

	# --- Fox Interaction ---
	"boop":                  { "label": "Boop!",                   "desc": "Click the fox for the first time.",                      "hidden": false },
	"certified_fox_friend":  { "label": "Certified Fox Friend",    "desc": "Pet the fox 25 times.",                                  "hidden": false, "threshold": 25 },
	"ball_is_life":          { "label": "Ball Is Life",            "desc": "Make the fox chase the ball once.",                      "hidden": false },
	"fetch_enthusiast":      { "label": "Fetch Enthusiast",        "desc": "Trigger 10 ball chases.",                                "hidden": false, "threshold": 10 },
	"sleepy_little_helper":  { "label": "Sleepy Little Helper",    "desc": "Let the fox sleep through an entire focus session.",     "hidden": false },
	"do_not_disturb":        { "label": "Do Not Disturb",          "desc": "Complete a full focus session without touching the fox.","hidden": false },

	# --- Customisation / Settings ---
	"new_coat":              { "label": "New Coat",                "desc": "Change the fox colour for the first time.",              "hidden": false },
	"fashion_fox":           { "label": "Fashion Fox",             "desc": "Try 3 different fox appearances.",                       "hidden": false, "threshold": 3  },
	"comfy_setup":           { "label": "Comfy Setup",             "desc": "Change any setting.",                                    "hidden": false },
	"bring_fox_home":        { "label": "Bring Fox Home",          "desc": "Use the bring fox home button.",                         "hidden": false },
	"perfect_little_desk":   { "label": "Perfect Little Desk",     "desc": "Unlock 5 den items.",                                    "hidden": false, "threshold": 5  },
	"interior_foxcorator":   { "label": "Interior Foxcorator",     "desc": "Unlock 10 den items.",                                   "hidden": false, "threshold": 10 },

	# --- Secret / Playful ---
	"you_did_enough_today":  { "label": "You Did Enough Today",    "desc": "Complete a session after ending one early the same day.","hidden": true  },
	"night_owl":             { "label": "Night Owl",               "desc": "Complete a session after midnight.",                     "hidden": true  },
	"early_bird":            { "label": "Early Bird",              "desc": "Complete a session before 7am.",                         "hidden": true  },
	"zoomies":               { "label": "Zoomies",                 "desc": "The fox reaches an impressive top speed.",               "hidden": true  },
	"just_checking_in":      { "label": "Just Checking In",        "desc": "Open the app, pet the fox, then close without starting a session.", "hidden": true },
	"still_counts":          { "label": "Still Counts",            "desc": "Complete a very short focus session.",                   "hidden": true  },
}

# Speed threshold (screen pixels/sec) that triggers "Zoomies"
const ZOOMIES_SPEED_THRESHOLD := 1400.0

# ---------------------------------------------------------------------------
# Runtime counters — things StatsStore doesn't already track
# ---------------------------------------------------------------------------
var _earned: Dictionary = {}       # id -> true
var _pet_count: int = 0
var _ball_chases: int = 0
var _colour_changes: int = 0
var _appearances_tried: Array = [] # distinct palette keys seen
var _items_unlocked: int = 0
var _any_setting_changed: bool = false

# Per-session transient flags (reset at session start)
var _fox_clicked_this_session: bool = false
var _session_ended_early_today: bool = false
var _petted_without_session: bool = false  # for "Just Checking In"

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load()


# ---------------------------------------------------------------------------
# Public API — called by world.gd, desktop_fox.gd, fox_settings_panel.gd, den.gd
# ---------------------------------------------------------------------------

## Call once on first _ready() in world.gd (only fires on very first ever launch).
func on_first_launch() -> void:
	unlock("welcome_home_fox")


## Call when a session is chosen/started.
## id is "focus", "short", or "long".
func on_session_started(id: String) -> void:
	_fox_clicked_this_session = false
	match id:
		"focus":
			unlock("ready_to_focus")
		"short":
			unlock("break_time")
		"long":
			unlock("proper_rest")


## Call when the pomodoro timer finishes naturally (session completed).
## Pass the session duration in seconds, the session id, and the StatsStore.
func on_session_completed(duration_sec: float, session_id: String, stats: Object) -> void:
	if session_id != "focus":
		return

	# --- First victory ---
	unlock("tiny_victory")

	# --- Session-count milestones ---
	var total: int = stats.total_sessions()
	for id in ["one_paw_forward", "finding_your_rhythm", "fox_flow",
			   "den_discipline", "deep_work_denizen", "legend_of_the_little_fox"]:
		if total >= int(DEFS[id].get("threshold", 9999)):
			unlock(id)

	# --- Duration-based ---
	if duration_sec <= 300.0:
		unlock("five_good_minutes")
		unlock("still_counts")
	if absf(duration_sec - 1500.0) < 60.0:   # 25 min ± 1 min tolerance
		unlock("classic_pomodoro")
	if duration_sec >= 2700.0:
		unlock("deep_focus")
	if duration_sec >= 5400.0:
		unlock("marathon_nap_supervisor")

	# --- Total focus time ---
	var total_focus: float = stats.total_focus()
	if total_focus >= 3600.0:
		unlock("an_hour_well_spent")
	if total_focus >= 28800.0:
		unlock("a_workday_of_fox_time")

	# --- Streak & consistency ---
	var trail: int = stats.current_trail()
	if trail >= 3:
		unlock("tiny_habit")
	if trail >= 7:
		unlock("week_of_whiskers")
	var days_used: int = stats.total_days_used()
	if days_used >= 2:
		unlock("back_tomorrow")
	if days_used >= 14:
		unlock("the_fox_remembers")
	if days_used >= 30:
		unlock("monthly_den_guest")

	# --- Behaviour during session ---
	if not _fox_clicked_this_session:
		unlock("do_not_disturb")
	if _session_ended_early_today:
		unlock("you_did_enough_today")

	# --- Time of day ---
	var hour: int = Time.get_datetime_dict_from_system().get("hour", 12)
	if hour >= 0 and hour < 5:
		unlock("night_owl")
	if hour < 7:
		unlock("early_bird")

	# Reset early-exit flag for the day only after a completed session
	_session_ended_early_today = false
	_petted_without_session = false
	_save()


## Call when the user hits stop/ends a session early.
func on_session_ended_early() -> void:
	_session_ended_early_today = true
	unlock("see_you_soon")
	_save()


## Call when the fox is clicked/petted (from desktop_fox.gd).
func on_fox_petted() -> void:
	_fox_clicked_this_session = true
	_petted_without_session = true
	_pet_count += 1
	unlock("boop")
	if _pet_count >= int(DEFS["certified_fox_friend"].get("threshold", 25)):
		unlock("certified_fox_friend")
	_save()


## Call each time the fox enters a new pounce (ball chase).
func on_ball_chased() -> void:
	_ball_chases += 1
	unlock("ball_is_life")
	if _ball_chases >= int(DEFS["fetch_enthusiast"].get("threshold", 10)):
		unlock("fetch_enthusiast")
	_save()


## Call every physics frame with the fox's current screen speed (px/s).
func on_fox_speed(speed: float) -> void:
	if speed >= ZOOMIES_SPEED_THRESHOLD:
		unlock("zoomies")


## Call when the fox is in sleep state for the full duration of a focus session.
## world.gd should track whether the fox stayed in "working" activity.
func on_sleepy_session_completed() -> void:
	unlock("sleepy_little_helper")


## Call when a colour/palette is changed.
## Pass the palette key string (e.g. "default", "red").
func on_colour_changed(palette_key: String) -> void:
	_colour_changes += 1
	if not _appearances_tried.has(palette_key):
		_appearances_tried.append(palette_key)
	unlock("new_coat")
	if _appearances_tried.size() >= int(DEFS["fashion_fox"].get("threshold", 3)):
		unlock("fashion_fox")
	unlock("comfy_setup")
	_save()


## Call when any non-colour setting changes (sliders, toggles, session lengths).
func on_setting_changed() -> void:
	unlock("comfy_setup")
	_save()


## Call when the Bring Fox Home button is pressed.
func on_bring_fox_home() -> void:
	unlock("bring_fox_home")
	_save()


## Call from den.gd when a new item is revealed, passing the total unlocked count.
func on_item_unlocked(total: int) -> void:
	_items_unlocked = maxi(_items_unlocked, total)
	if _items_unlocked >= int(DEFS["perfect_little_desk"].get("threshold", 5)):
		unlock("perfect_little_desk")
	if _items_unlocked >= int(DEFS["interior_foxcorator"].get("threshold", 10)):
		unlock("interior_foxcorator")
	_save()


## Call from world.gd _notification(NOTIFICATION_WM_CLOSE_REQUEST) when the
## app is closing, to handle "Just Checking In".
func on_app_closing(session_was_started: bool) -> void:
	if _petted_without_session and not session_was_started:
		unlock("just_checking_in")
	_save()


# ---------------------------------------------------------------------------
# Core unlock — idempotent, safe to call any time
# ---------------------------------------------------------------------------

func unlock(id: String) -> void:
	if _earned.get(id, false):
		return
	if not DEFS.has(id):
		push_warning("AchievementStore: unknown achievement id '%s'" % id)
		return
	_earned[id] = true
	_steam_set_achievement(id)
	achievement_unlocked.emit(id, DEFS[id])
	_save()


func is_earned(id: String) -> bool:
	return _earned.get(id, false)


func earned_count() -> int:
	var n := 0
	for id in _earned:
		if _earned[id]:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _earned:
		cfg.set_value("earned", id, _earned[id])
	cfg.set_value("counters", "pet_count", _pet_count)
	cfg.set_value("counters", "ball_chases", _ball_chases)
	cfg.set_value("counters", "colour_changes", _colour_changes)
	cfg.set_value("counters", "appearances_tried", _appearances_tried)
	cfg.set_value("counters", "items_unlocked", _items_unlocked)
	cfg.set_value("counters", "session_ended_early_today", _session_ended_early_today)
	cfg.set_value("counters", "any_setting_changed", _any_setting_changed)
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if cfg.has_section("earned"):
		for id in cfg.get_section_keys("earned"):
			_earned[id] = cfg.get_value("earned", id, false)
	_pet_count = int(cfg.get_value("counters", "pet_count", 0))
	_ball_chases = int(cfg.get_value("counters", "ball_chases", 0))
	_colour_changes = int(cfg.get_value("counters", "colour_changes", 0))
	var ap = cfg.get_value("counters", "appearances_tried", [])
	_appearances_tried = ap if ap is Array else []
	_items_unlocked = int(cfg.get_value("counters", "items_unlocked", 0))
	_session_ended_early_today = bool(cfg.get_value("counters", "session_ended_early_today", false))
	_any_setting_changed = bool(cfg.get_value("counters", "any_setting_changed", false))
	# Sync any already-earned achievements to Steam (handles reinstalls / new devices)
	for id in _earned:
		if _earned[id]:
			_steam_set_achievement(id)


# ---------------------------------------------------------------------------
# Steam abstraction layer
# ---------------------------------------------------------------------------
# These are the ONLY functions that touch the Steam API.
# To wire in GodotSteam:
#   1. Install the GodotSteam plugin (https://godotsteam.com)
#   2. Add steam_appid.txt to your project root
#   3. Replace the bodies of _steam_set_achievement() and _steam_init() below
#   4. Call _steam_init() in _ready(), before _load()
#
# The rest of the achievement system requires zero changes.
# ---------------------------------------------------------------------------

func _steam_init() -> void:
	## Uncomment when GodotSteam is installed:
	# if Engine.has_singleton("Steam"):
	#     var result := Steam.steamInitEx()
	#     if result["status"] != Steam.STEAM_API_INIT_RESULT_OK:
	#         push_warning("Steam init failed: " + str(result))
	pass


func _steam_set_achievement(id: String) -> void:
	## Uncomment when GodotSteam is installed:
	# if Engine.has_singleton("Steam") and Steam.is_steam_running():
	#     Steam.setAchievement(id)
	#     Steam.storeStats()
	pass


func _steam_clear_achievement(id: String) -> void:
	## For development/testing only — clears a Steam achievement.
	## Uncomment when GodotSteam is installed:
	# if Engine.has_singleton("Steam") and Steam.is_steam_running():
	#     Steam.clearAchievement(id)
	#     Steam.storeStats()
	pass


func _steam_reset_all_achievements() -> void:
	## For development/testing only — wipes all Steam achievements.
	## Uncomment when GodotSteam is installed:
	# if Engine.has_singleton("Steam") and Steam.is_steam_running():
	#     Steam.resetAllStats(true)
	#     Steam.storeStats()
	pass
