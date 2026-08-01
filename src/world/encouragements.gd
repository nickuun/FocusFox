extends RefCounted
class_name Encouragements

## Encouragements — categorised warm messages shown at key moments.
##
## Usage:
##   Encouragements.pick("focus")      # after a focus session completes
##   Encouragements.pick("break")      # after a break completes
##   Encouragements.pick("early_exit") # when the user stops a session early
##   Encouragements.pick("milestone")  # for streak / total-time moments

const MESSAGES := {
	"focus": [
		"❤️ Great job! Every pawprint counts.",
		"🦊 Your fox is proud of today's focus.",
		"✨ Tiny progress is still progress.",
		"🍃 You showed up. That's the hardest part.",
		"🧡 Focus done. Be kind to yourself.",
		"🐾 One pawprint at a time.",
		"🌱 Every step matters.",
		"🎯 Look at you, actually doing the thing.",
		"🌟 Your future self will thank you for this.",
		"🦊 The fox noticed. Well done.",
		"💛 That's one more than yesterday.",
		"🌿 Slow and steady builds the den.",
		"🍂 That session is in the books.",
		"🐾 Footprint by footprint. You're getting there.",
		"🌤️ A little clearer skies. Nice work.",
		"✅ Done. That counts.",
		"🧡 The fox is curling up proud.",
		"💫 You made focus happen. That's not nothing.",
		"🌙 Quiet work is still real work.",
		"🪵 Good work for the fire. Keep going.",
		"🎉 Session complete! The fox approves.",
		"🌸 You did it. Genuinely.",
		"🦊 Focused and finished. That's the whole game.",
		"🌻 Another one in the bag.",
		"💪 Softer than a sprint, steadier than a pause.",
	],
	"break": [
		"☕ Rest is part of the rhythm.",
		"🛏️ Even little foxes need breaks.",
		"🌸 A rested mind does better work.",
		"🍵 Good. You took the break. Now breathe.",
		"🌈 Breaks aren't laziness. They're strategy.",
		"🌬️ Deep breath. You've earned this.",
		"🦊 Your fox stretched too.",
		"💤 Rest is productive. Genuinely.",
		"🌿 The pause is part of the pace.",
		"🐾 Back soon. No rush.",
		"☁️ Soft stop, soft start. You've got this.",
		"🍂 Let it land before you leap again.",
		"🫖 Warm up. You're doing great.",
		"🌙 Even the moon takes a moment.",
		"🕯️ Gentle now. Right back when ready.",
		"🌤️ Step away. The work will wait.",
		"🧁 Break time. You've earned every second.",
		"🦊 The fox is napping too. Good call.",
		"🌿 Rest is not stopping. It's part of going.",
		"💛 Let yourself actually stop for a moment.",
	],
	"early_exit": [
		"🐾 That still counted. Truly.",
		"🦊 The fox isn't disappointed. Neither should you be.",
		"🌱 Stopping is still a choice. A real one.",
		"💛 You tried. That matters more than finishing.",
		"🍃 Sometimes the session is: showing up, then letting go.",
		"🧡 Come back when you're ready. No pressure.",
		"✨ Short focus beats no focus, every time.",
		"☁️ Today's what it is. Tomorrow is fresh.",
		"🌤️ Ease up on yourself. You're doing okay.",
		"🌿 Not every session needs to be perfect.",
		"🐾 The fox will be here when you're back.",
		"💤 Rest if that's what you need. It's allowed.",
		"🌙 It's okay. Start small next time.",
		"🫖 Gentle exit. Good call.",
		"❤️ You showed up. That's the whole thing.",
		"🦊 Even a short sit counts as sitting.",
		"🌸 You can always come back.",
		"🍂 No guilt. Just a pause.",
	],
	"milestone": [
		"🎉 Seven days in a row. The fox is doing a little dance.",
		"🏅 100 sessions. That's a real thing you did.",
		"🌟 A full hour of focus. Look at that.",
		"🦊 The den is growing. So are you.",
		"🐾 Ten sessions! The fox approves.",
		"💫 A whole workday of focus, total. Wow.",
		"🎯 25 sessions. You've found your rhythm.",
		"🌿 Two weeks of showing up. That's habit territory.",
		"🧡 A month of foxing around productively. Incredible.",
		"🏆 250 sessions. Legend of the Little Fox, indeed.",
		"🎊 Three days running. You're building something.",
		"🌻 50 sessions deep. The fox is proud.",
	],
}

# Ring buffer to avoid showing the same message twice in a row.
# Tracks the last 3 shown messages per category.
static var _recent: Dictionary = {}
const _NO_REPEAT_WINDOW := 3

## Returns a random message for the given category, avoiding recent repeats.
static func pick(category: String) -> String:
	var pool: Array = MESSAGES.get(category, MESSAGES["focus"])
	if pool.is_empty():
		return ""

	# Filter out recently shown messages for this category.
	var recent: Array = _recent.get(category, [])
	var available: Array = pool.filter(func(m): return not recent.has(m))
	if available.is_empty():
		available = pool  # all seen — reset and allow any

	var chosen: String = available[randi() % available.size()]

	# Update the ring buffer.
	if not _recent.has(category):
		_recent[category] = []
	_recent[category].append(chosen)
	if _recent[category].size() > _NO_REPEAT_WINDOW:
		_recent[category].pop_front()

	return chosen
