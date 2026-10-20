class_name TutorialOverlay
extends Control

var _hints: Array[String] = [
	"每回合你有能量，打出卡牌需要消耗左上角显示的能量。",
	"点击一张手牌，再点击敌人，即可对其施放攻击。",
	"防御牌会为你提供格挡，格挡能抵消等量伤害。",
	"敌人头顶会显示它本回合的意图（攻击/防御/强化等）。",
	"安排好后点击右下角「结束回合」，让敌人行动。",
]
var _index: int = 0

var _title_label: Label
var _hint_label: Label
var _prev_button: Button
var _next_button: Button

func _ready() -> void:
	_build_ui()
	_update_display()

func _build_ui() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0

	var dim := ColorRect.new()
	dim.anchors_preset = PRESET_FULL_RECT
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.anchors_preset = PRESET_CENTER_BOTTOM
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -340.0
	panel.offset_top = -210.0
	panel.offset_right = 340.0
	panel.offset_bottom = -40.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = PRESET_FULL_RECT
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 20.0
	vbox.offset_top = 16.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(0, 80)
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_hint_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_prev_button = Button.new()
	_prev_button.text = "上一步"
	_prev_button.custom_minimum_size = Vector2(100, 40)
	_prev_button.pressed.connect(_on_prev)
	btn_row.add_child(_prev_button)

	_next_button = Button.new()
	_next_button.text = "下一步"
	_next_button.custom_minimum_size = Vector2(120, 40)
	_next_button.pressed.connect(_on_next)
	btn_row.add_child(_next_button)

	var skip_button := Button.new()
	skip_button.text = "跳过引导"
	skip_button.custom_minimum_size = Vector2(100, 40)
	skip_button.pressed.connect(_finish)
	btn_row.add_child(skip_button)

func _update_display() -> void:
	_title_label.text = "新手引导 (%d/%d)" % [_index + 1, _hints.size()]
	_hint_label.text = _hints[_index]
	_prev_button.disabled = _index == 0
	_next_button.text = "开始战斗" if _index == _hints.size() - 1 else "下一步"

func _on_prev() -> void:
	if _index > 0:
		_index -= 1
		_update_display()

func _on_next() -> void:
	if _index < _hints.size() - 1:
		_index += 1
		_update_display()
	else:
		_finish()

func _finish() -> void:
	GameManager.meta_progress.tutorial_seen = true
	GameManager.save_meta_progress()
	queue_free()
