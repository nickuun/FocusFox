extends Panel
class_name FoxSettingsPanel

@onready var close_button: Button = $CloseButton

# Appearance
@onready var scale_slider: HSlider = $ScaleSlider
@onready var opacity_slider: HSlider = $OpacitySlider
@onready var liveliness_slider: HSlider = $LivelinessSlider
@onready var colour_option: OptionButton = $ColourOption

# Behaviour
@onready var click_through_toggle: CheckButton = $ClickThroughToggle
@onready var hover_fade_toggle: CheckButton = $HoverFadeToggle
@onready var taskbar_snap_toggle: CheckButton = $TaskbarSnapToggle
@onready var taskbar_height_slider: HSlider = $TaskbarHeightSlider

# Fox controls
@onready var spawn_fox_button: Button = $SpawnFoxButton
@onready var hide_fox_button: Button = $HideFoxButton
@onready var reset_fox_button: Button = $ResetFoxButton
@onready var reset_all_button: Button = $ResetAllButton
@onready var fox_status_label: Label = $FoxStatusLabel
@onready var hint_label: Label = $HintLabel
