extends Control

## 遗物三选一。两个入口共用这一个界面：
##   · Boss 打完 —— 由 end_state 挂成战斗场景上的浮层。末章的 Boss 选完走 finish_run + VICTORY，
##     前面几章的 Boss 选完翻下一章（advance_chapter）；
##   · 地图宝箱 —— 由 change_screen(RELIC_PICK) 直接当一屏加载，选完 finish_node 回地图。
## 靠 node_state 里的 exit 字段区分三种去向。两个入口都是「必须拿一件」，所以没有「跳过」。

const PICK_COUNT: int = 3

@onready var relic_container: HBoxContainer = %RelicContainer
@onready var hint_label: Label = %HintLabel
@onready var confirm_button: Button = %ConfirmButton

var _offered: Array[RelicData] = []
var _selected: int = -1


func _ready() -> void:
	UIBackground.apply(self, "relic_picker")
	confirm_button.pressed.connect(_on_confirm)
	# 候选抽一次就锁进存档：退出重进看到同一批，不给反复刷。
	var state := GameManager.ensure_node_state(_roll_state)
	_display(state)


func _roll_state() -> Dictionary:
	var is_boss := GameManager.current_encounter_type == MapNodeData.NodeType.BOSS
	# Boss 三选一只发 BOSS 档；宝箱和商店一样是全档随机。
	var rarity: int = int(RelicData.RelicRarity.BOSS) if is_boss else -1
	var exclude_ids := _owned_relic_ids()
	var ids: Array = []
	for _i in range(PICK_COUNT):
		var relic := DataManager.get_random_relic(rarity, exclude_ids)
		if relic == null:
			break
		ids.append(relic.relic_id)
		# 抽出来的也要排除，否则三张里会出现同一件。
		exclude_ids.append(relic.relic_id)
	return {
		"relic_ids": ids,
		"exit": _exit_mode(is_boss),
	}


## 选完这一屏往哪走。三种去向都只有这里能定，_on_confirm 只照着做。
func _exit_mode(is_boss: bool) -> String:
	if not is_boss:
		return "map"
	return "victory" if GameManager.is_final_chapter() else "next_chapter"


func _owned_relic_ids() -> Array[String]:
	var out: Array[String] = []
	for relic: RelicData in GameManager.current_relics:
		out.append(relic.relic_id)
	return out


func _display(state: Dictionary) -> void:
	_offered.clear()
	_selected = -1
	for relic_id: Variant in state.get("relic_ids", []):
		var relic := DataManager.get_relic(str(relic_id))
		if relic == null:
			continue
		_offered.append(relic)
		relic_container.add_child(_make_relic_button(relic, _offered.size() - 1))

	if _offered.is_empty():
		# 遗物都收齐了就会走到这里。空着也得能走下去，不能把玩家卡在这一屏。
		hint_label.text = "没有可选的遗物了"
		confirm_button.disabled = false
	else:
		hint_label.text = "选择一件遗物"
		confirm_button.disabled = true


## 一件候选 = 一张卡：上图标、中名字、下描述。外层仍是 Button，
## 选中靠 _on_relic_pressed 的 modulate 压暗、点击也落在按钮本身。
## 骨架照 submenu_screen.gd 的 _make_card（Button + 内嵌 VBox）——本作「横排卡片」的既有写法。
func _make_relic_button(relic: RelicData, index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 210)
	btn.tooltip_text = relic.description
	btn.pressed.connect(_on_relic_pressed.bind(index, btn))

	var box := VBoxContainer.new()
	box.anchors_preset = Control.PRESET_FULL_RECT
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 16.0
	box.offset_top = 16.0
	box.offset_right = -16.0
	box.offset_bottom = -16.0
	# 不 IGNORE 的话容器会吃掉点击，按钮点不动（submenu_screen 的卡片踩过）。
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	btn.add_child(box)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(CodexIcon.make_relic_slot(relic, 84))
	box.add_child(icon_center)

	box.add_child(_make_card_text(relic.relic_name, 20, relic.get_color()))
	box.add_child(_make_card_text(relic.description, 13, Color(0.75, 0.75, 0.8)))
	return btn


func _make_card_text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_relic_pressed(index: int, btn: Button) -> void:
	_selected = index
	for i in relic_container.get_child_count():
		var child := relic_container.get_child(i) as Button
		if child:
			child.modulate = Color(1, 1, 1) if i == index else Color(0.55, 0.55, 0.6)
	confirm_button.disabled = false
	if index < _offered.size():
		hint_label.text = "已选择：%s" % _offered[index].relic_name


func _on_confirm() -> void:
	if _selected >= 0 and _selected < _offered.size():
		GameManager.add_relic(_offered[_selected])
	match str(GameManager.node_state.get("exit", "map")):
		"victory":
			GameManager.finish_run(true)
			GameManager.change_screen(GameManager.GameScreen.VICTORY)
		"next_chapter":
			GameManager.advance_chapter()
		_:
			GameManager.finish_node()
