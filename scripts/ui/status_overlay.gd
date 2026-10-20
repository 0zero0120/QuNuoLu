class_name StatusOverlay
extends ColorRect

## 察看状态面板：战斗中按 Space 打开，列出玩家和每个敌人当前挂着的状态。
## 战斗界面上那排小图标只有一个字，这里给的是写全的名字和数值。
## 纯代码搭，没有 .tscn——项目里几个纯代码页（角色详情、卡牌详情）都是这个路子。

const PANEL_WIDTH := 620
## 面板高度按内容算，但不小于下面这个数、也不超过上面那个数：太短会缩成一条窄边，
## 太长会顶出屏幕（超出的部分靠滚动看）。
const PANEL_MIN_HEIGHT := 200.0
const PANEL_MAX_HEIGHT := 520.0
const HEADING_COLOR := Color(0.95, 0.82, 0.45)
const MUTED := Color(0.62, 0.60, 0.70)

var _player: Player
var _enemies: Array[EnemyBase] = []
var _body: VBoxContainer


func setup(player: Player, enemies: Array[EnemyBase]) -> void:
	_player = player
	_enemies = enemies


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	color = Color(0, 0, 0, 0.78)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## ESC 关掉自己。走 _input（输入链第一站）而不是 _unhandled_input：
## 全局的 ESC 是「暂停」，那个排在 _unhandled_input 这一站；在这里先吃掉事件，暂停菜单就不会跟着弹出来。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	# Space 是打开它的键，也让它能关掉自己。
	if event.is_action_pressed("view_status"):
		close()
		get_viewport().set_input_as_handled()


## 点暗底（也就是面板外面）也关。面板自己是 STOP 的，点在面板上不会传到这里。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()


func close() -> void:
	queue_free()


func _build() -> void:
	var center := CenterContainer.new()
	center.anchors_preset = PRESET_FULL_RECT
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 28)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	_body = VBoxContainer.new()
	# 这一句不能省：ScrollContainer 只把**带 EXPAND 标记**的子节点撑到自己的宽度，
	# 少了它正文列会缩成一行文字那么窄，居中标题和自动换行全都对不上。
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	var scroll := _scroll(_body)
	column.add_child(scroll)

	_body.add_child(_heading("当前状态"))
	_body.add_child(_note("生命、格挡和挂在身上的效果。"))

	_body.add_child(_section_header("玩家"))
	for line in _player_lines():
		_body.add_child(_line(line))

	var alive := 0
	for enemy in _enemies:
		if not enemy.is_alive:
			continue
		alive += 1
		_body.add_child(_section_header(_enemy_name(enemy)))
		for line in _enemy_lines(enemy):
			_body.add_child(_line(line))
	if alive == 0:
		_body.add_child(_line("场上没有活着的敌人。"))

	# ScrollContainer 的最小尺寸里**不含**内容，不手动顶一个高度的话，面板会缩成只剩内边距的
	# 一条窄边，正文被滚动视口裁掉——看上去就是个空框。这条只有真窗口才看得出来。
	scroll.custom_minimum_size = Vector2(0, clampf(
		_body.get_combined_minimum_size().y, PANEL_MIN_HEIGHT, PANEL_MAX_HEIGHT))

	# 「关闭」摆在下滑区**外面**：内容长到要滚的时候，它不该跟着一起滚走。
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(0, 38)
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(close)
	column.add_child(close_button)


## 内容多了要能滚，否则敌人一多或者状态一长，面板会顶出屏幕。
func _scroll(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _player_lines() -> Array[String]:
	var lines: Array[String] = [
		"生命 %d / %d" % [_player.current_hp, _player.max_hp],
		"格挡 %d" % _player.current_block,
		"力量 %d　敏捷 %d" % [_player.get_strength(), _player.get_dexterity()],
	]
	lines.append_array(_effect_lines(_player.status_effects))
	return lines


func _enemy_lines(enemy: EnemyBase) -> Array[String]:
	var max_hp: int = enemy.enemy_data.max_hp if enemy.enemy_data else enemy.current_hp
	var lines: Array[String] = [
		"生命 %d / %d" % [enemy.current_hp, max_hp],
		"格挡 %d" % enemy.current_block,
		"力量 %d　敏捷 %d" % [enemy.strength, enemy.dexterity],
	]
	# 机制那一栏排在这几只敌人的血量/格挡之后、状态之前：反伤、复活、蓄力这些是**这只怪**
	# 是什么，不是它这一刻身上挂着什么，得和状态分开摆在前面。
	if enemy.enemy_data != null and not enemy.enemy_data.mechanic_desc.is_empty():
		lines.append("机制：" + enemy.enemy_data.mechanic_desc)
	lines.append_array(_effect_lines(enemy.status_effects))
	return lines


## 力量/敏捷已经单独列过了，这里不再重复，免得同一个数出现两遍。
func _effect_lines(effects: Array[StatusEffect]) -> Array[String]:
	var lines: Array[String] = []
	for effect in effects:
		if effect.type == StatusEffect.Type.STRENGTH or effect.type == StatusEffect.Type.DEXTERITY:
			continue
		var text := "%s %s %d" % [effect.get_icon(), effect.get_display_name(), effect.value]
		if effect.temporary:
			text += "（本回合）"
		lines.append(text)
	if lines.is_empty():
		lines.append("没有其他状态。")
	return lines


func _enemy_name(enemy: EnemyBase) -> String:
	return enemy.enemy_data.display_name if enemy.enemy_data else "敌人"


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	return label


func _line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _note(text: String) -> Label:
	var label := _line(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.10, 0.10, 0.16, 0.98)
	box.border_color = Color(0.30, 0.28, 0.40)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	return box
