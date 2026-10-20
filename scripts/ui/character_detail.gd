class_name CharacterDetail
extends Control

## 角色详情页（参考杀戮尖塔）：左侧文字资料，右侧立绘，右下启程，左下返回。

const TITLE_FONT: FontFile = preload("res://assets/fonts/MaShanZheng-Regular.ttf")

var _character: PlayerData
## 本局要打的难度。范围为 1..账号已解锁的最高级，开局后不可改。
var _ascension: int = 1
## 本局的种子：开局要用的那串九位数，留空就在开局时随机抽一个。
var _seed_row: Control
var _seed_input: LineEdit
var _ascension_row: Control
var _ascension_label: Label
var _ascension_left: Button
var _ascension_right: Button


func setup(character: PlayerData) -> void:
	_character = character


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	if _character == null:
		_character = PlayerData.new()

	add_child(_make_backdrop())
	add_child(_make_info_block())
	add_child(_make_portrait())
	_seed_row = _make_seed_row()
	add_child(_seed_row)
	_ascension_row = _make_ascension_row()
	add_child(_ascension_row)
	add_child(_make_depart_button())
	add_child(_make_back_button())


## 选人页那张底图接着用，压暗到能读字；读不到就只留纯色兜底。
func _make_backdrop() -> Control:
	var layer := Control.new()
	layer.name = "Backdrop"
	layer.anchors_preset = PRESET_FULL_RECT
	layer.anchor_right = 1.0
	layer.anchor_bottom = 1.0
	layer.mouse_filter = Control.MOUSE_FILTER_STOP

	var base := ColorRect.new()
	base.color = Color(0.06, 0.06, 0.12, 1.0)
	base.anchors_preset = PRESET_FULL_RECT
	base.anchor_right = 1.0
	base.anchor_bottom = 1.0
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(base)

	var tex := UIBackground.load_or_null("character_select")
	if tex != null:
		var image := TextureRect.new()
		image.name = "BackgroundImage"
		image.texture = tex
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.modulate = Color(0.62, 0.62, 0.68, 1.0)
		layer.add_child(image)

		var scrim := ColorRect.new()
		scrim.color = Color(0.02, 0.025, 0.045, 0.52)
		scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(scrim)
	return layer


func _make_info_block() -> VBoxContainer:
	var block := VBoxContainer.new()
	block.anchor_left = 0.0
	block.anchor_top = 0.5
	block.anchor_right = 0.0
	block.anchor_bottom = 0.5
	block.offset_left = 110.0
	block.offset_top = -240.0
	block.offset_right = 830.0
	block.offset_bottom = 240.0
	block.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = _character.character_name
	name_label.add_theme_font_override("font", TITLE_FONT)
	name_label.add_theme_font_size_override("font_size", 56)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 1.0))
	name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	name_label.add_theme_constant_override("outline_size", 8)
	block.add_child(name_label)

	# 名字底下一道流派色横杠，顶替原来那块空 div。
	var accent := _character.accent_color
	var underline := ColorRect.new()
	underline.color = Color(accent.r, accent.g, accent.b, 0.85)
	underline.custom_minimum_size = Vector2(180, 3)
	underline.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(underline)

	_add_info_row(block, "生命", str(_character.base_max_hp))
	_add_info_row(block, "能量", str(_character.base_energy))
	_add_info_row(block, "金币", str(_character.gold))
	_add_info_row(block, "初始遗物", _starting_relic_name())
	_add_info_row(block, "起始卡组", "%d 张" % _character.starting_deck_ids.size())

	return block


## 种子输入行：种子 [ 738291046 ]，摆在难度行正上方、启程按钮头上。
## 填同一串再开一局，地图、敌人、奖励、商店、事件全都一样；留空就开局随机抽一个九位数。
func _make_seed_row() -> Control:
	# 和 _make_ascension_row 一样，这一行也不能漏 add_child（见 _build）。
	var holder := Control.new()
	holder.anchor_left = 1.0
	holder.anchor_top = 1.0
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = -340.0
	holder.offset_top = -240.0
	holder.offset_right = -110.0
	holder.offset_bottom = -188.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.anchors_preset = PRESET_FULL_RECT
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	holder.add_child(row)

	var key_label := Label.new()
	key_label.text = "种子"
	key_label.custom_minimum_size = Vector2(60, 36)
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.70))
	row.add_child(key_label)

	_seed_input = LineEdit.new()
	_seed_input.max_length = 9
	_seed_input.placeholder_text = "留空随机"
	_seed_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_seed_input.custom_minimum_size = Vector2(0, 36)
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_input.add_theme_font_size_override("font_size", 18)
	_seed_input.text_changed.connect(_on_seed_text_changed)
	row.add_child(_seed_input)

	return holder


## LineEdit 没有输入掩码，非数字只能自己滤。滤完和原文一样就什么都不做，
## 否则 set_text 会再把 text_changed 发一次、绕回来没完。
func _on_seed_text_changed(new_text: String) -> void:
	var digits := ""
	for ch in new_text:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits == new_text:
		return
	_seed_input.set_text(digits)
	_seed_input.caret_column = digits.length()


## 难度选择器：＜ 难度 壹 ＞，和杀戮尖塔一样用左右按钮挑。
## 摆在「启程」正上方、和资料块分开——它是开局的设置，不是角色属性。
## 范围是账号已解锁的那几级，默认停在账号上一次用过的难度。
func _make_ascension_row() -> Control:
	# 这一行不能漏 add_child（见 _build）——控件照样建得出来、测试也拿得到 _ascension_label，
	# 但整行不在树上，界面上一个字都看不到。
	var holder := Control.new()
	holder.anchor_left = 1.0
	holder.anchor_top = 1.0
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = -340.0
	holder.offset_top = -170.0
	holder.offset_right = -110.0
	holder.offset_bottom = -118.0
	# 空白处不该吃掉点击，但那两个箭头按钮照常收得到。
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.anchors_preset = PRESET_FULL_RECT
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	holder.add_child(row)

	_ascension_left = _make_arrow_button("＜")
	_ascension_left.pressed.connect(_on_ascension_step.bind(-1))
	row.add_child(_ascension_left)

	_ascension_label = Label.new()
	_ascension_label.custom_minimum_size = Vector2(100, 36)
	_ascension_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ascension_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ascension_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_ascension_label)

	_ascension_right = _make_arrow_button("＞")
	_ascension_right.pressed.connect(_on_ascension_step.bind(1))
	row.add_child(_ascension_right)

	_ascension = _default_ascension()
	_refresh_ascension_row()
	return holder


func _make_arrow_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(44, 36)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _max_unlocked_ascension() -> int:
	if GameManager.meta_progress == null:
		return 1
	var bal := DataManager.get_balance()
	var cap := bal.max_ascension if bal else 1
	return clampi(GameManager.meta_progress.ascension_level, 1, cap)


## 默认停在账号上一次实际用过的难度，而不是最高级——解锁到 5 但一直在打 3 的人，
## 不该每次开新局都被顶到 5 去。
func _default_ascension() -> int:
	if GameManager.meta_progress == null:
		return 1
	return clampi(GameManager.meta_progress.last_ascension_choice, 1, _max_unlocked_ascension())


func _on_ascension_step(step: int) -> void:
	_ascension = clampi(_ascension + step, 1, _max_unlocked_ascension())
	_refresh_ascension_row()


## 到头的箭头按灰，玩家一眼能看出还能不能往上/往下挑。
func _refresh_ascension_row() -> void:
	if _ascension_label == null:
		return
	_ascension_label.text = AscensionText.label(_ascension)
	_ascension_left.disabled = _ascension <= 1
	_ascension_right.disabled = _ascension >= _max_unlocked_ascension()


func _add_info_row(parent: VBoxContainer, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(140, 0)
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.70))
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 18)
	row.add_child(value_label)

	parent.add_child(row)


func _starting_relic_name() -> String:
	if _character.starting_relic_id.is_empty():
		return "无"
	var relic := DataManager.get_relic(_character.starting_relic_id)
	if relic == null:
		return _character.starting_relic_id
	return relic.relic_name


func _make_portrait() -> Panel:
	var holder := Panel.new()
	holder.anchor_left = 1.0
	holder.anchor_top = 0.5
	holder.anchor_right = 1.0
	holder.anchor_bottom = 0.5
	holder.offset_left = -670.0
	holder.offset_top = -280.0
	holder.offset_right = -110.0
	holder.offset_bottom = 280.0

	var accent := _character.accent_color
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.035, 0.04, 0.065, 0.82)
	frame.border_width_left = 2
	frame.border_width_top = 2
	frame.border_width_right = 2
	frame.border_width_bottom = 2
	frame.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	frame.corner_radius_top_left = 14
	frame.corner_radius_top_right = 14
	frame.corner_radius_bottom_right = 14
	frame.corner_radius_bottom_left = 14
	frame.shadow_color = Color(accent.r, accent.g, accent.b, 0.16)
	frame.shadow_size = 26
	holder.add_theme_stylebox_override("panel", frame)
	return PortraitSlot.fill(holder, _character.portrait, accent)


func _make_depart_button() -> Button:
	var button := Button.new()
	button.text = "启程"
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = -340.0
	button.offset_top = -100.0
	button.offset_right = -110.0
	button.offset_bottom = -40.0
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _button_style(
		_accent(0.22), _accent(0.85)))
	button.add_theme_stylebox_override("hover", _button_style(
		_accent(0.36), _accent(1.0)))
	button.add_theme_stylebox_override("pressed", _button_style(
		_accent(0.50), _accent(1.0)))
	button.add_theme_color_override("font_color", Color(0.97, 0.95, 0.90, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.pressed.connect(_on_depart)
	return button


## 启程键的底色、描边都从本角色流派色来，换角色不用另配一套皮。
func _accent(alpha: float) -> Color:
	var accent := _character.accent_color
	return Color(accent.r, accent.g, accent.b, alpha)


func _make_back_button() -> Button:
	var button := Button.new()
	button.text = "返回"
	button.anchor_left = 0.0
	button.anchor_top = 1.0
	button.anchor_right = 0.0
	button.anchor_bottom = 1.0
	button.offset_left = 110.0
	button.offset_top = -80.0
	button.offset_right = 250.0
	button.offset_bottom = -32.0
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _button_style(
		Color(0.05, 0.05, 0.08, 0.72), Color(0.55, 0.50, 0.35, 0.55)))
	button.add_theme_stylebox_override("hover", _button_style(
		Color(0.12, 0.12, 0.18, 0.88), Color(0.85, 0.70, 0.40, 0.95)))
	button.add_theme_stylebox_override("pressed", _button_style(
		Color(0.16, 0.14, 0.12, 0.95), Color(0.95, 0.80, 0.50, 1.0)))
	button.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.pressed.connect(_on_back)
	return button


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _on_depart() -> void:
	# 没填（或填了 0）就是 0，start_new_run 会当成「随机抽一个」。
	var typed := 0
	if _seed_input != null:
		typed = int(_seed_input.text)
	GameManager.start_new_run(_character, GameManager.pending_new_slot, _ascension, typed)


func _on_back() -> void:
	queue_free()
