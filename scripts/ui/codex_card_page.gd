class_name CodexCardPage
extends SubPage

## 卡牌总览：全部 / 攻击 / 技能 / 能力 四个页签 + 稀有度·耗能筛选 + 卡牌网格。
## 参考杀戮尖塔：只显示遇见过的卡，没遇见过的画挂锁、名字写 ???

const CARD_SIZE := Vector2(168, 232)
const SLOT_SIZE := 84.0
## 类型行那个小图标槽的边长，跟同一行的耗能球（28x28）对齐。
const TYPE_SLOT_SIZE := 28.0

## 页签对应的卡牌类型，-1 表示「全部」。
const TAB_TYPES := [-1, CardData.CardType.ATTACK, CardData.CardType.SKILL, CardData.CardType.ABILITY]
const TAB_NAMES := ["全部", "攻击", "技能", "能力"]

const TAB_ON := Color(0.85, 0.77, 0.60)
const TAB_ON_TEXT := Color(0.16, 0.11, 0.06)
const TAB_OFF := Color(0.16, 0.16, 0.22)
const MUTED := Color(0.55, 0.54, 0.63)

var _cards: Array[CardData] = []
var _active_tab: int = 0
var _tab_buttons: Array[Button] = []
var _rarity_filter: OptionButton
var _cost_filter: OptionButton
var _upgrade_toggle: CheckBox
var _flow: HFlowContainer
var _rarity_choice: int = -1
var _cost_choices: Array[int] = []
var _cost_choice: Variant = null
var _show_upgraded: bool = false


func setup_page(title: String) -> void:
	setup(title, _fill_page)


func _fill_page(_page: SubPage) -> void:
	_collect_cards()
	add_content(_make_tab_row())
	add_content(_make_filter_row())
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 12)
	_flow.add_theme_constant_override("v_separation", 14)
	add_content(_flow)
	_refresh()


func _collect_cards() -> void:
	_cards.clear()
	for card: CardData in DataManager.card_database.values():
		_cards.append(card)
	_cards.sort_custom(_sort_cards)


func _sort_cards(a: CardData, b: CardData) -> bool:
	if a.rarity != b.rarity:
		return a.rarity > b.rarity
	if a.card_type != b.card_type:
		return a.card_type < b.card_type
	return a.card_name < b.card_name


# --- 页签 ---

func _make_tab_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_tab_buttons.clear()
	for i in TAB_NAMES.size():
		var button := Button.new()
		button.text = TAB_NAMES[i]
		button.custom_minimum_size = Vector2(128, 44)
		button.add_theme_font_size_override("font_size", 19)
		button.pressed.connect(_on_tab_pressed.bind(i))
		row.add_child(button)
		_tab_buttons.append(button)
	return row


func _on_tab_pressed(index: int) -> void:
	if _active_tab == index:
		return
	_active_tab = index
	_refresh()


# --- 筛选 ---

func _make_filter_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	_rarity_filter = OptionButton.new()
	_rarity_filter.custom_minimum_size = Vector2(160, 40)
	_rarity_filter.add_item("全部稀有度")
	for rarity: int in [CardData.CardRarity.BASIC, CardData.CardRarity.COMMON,
			CardData.CardRarity.UNCOMMON, CardData.CardRarity.RARE]:
		_rarity_filter.add_item(_rarity_name(rarity))
	_rarity_filter.item_selected.connect(_on_rarity_selected)
	row.add_child(_rarity_filter)

	_cost_filter = OptionButton.new()
	_cost_filter.custom_minimum_size = Vector2(160, 40)
	_rebuild_cost_filter()
	_cost_filter.item_selected.connect(_on_cost_selected)
	row.add_child(_cost_filter)

	_upgrade_toggle = CheckBox.new()
	_upgrade_toggle.text = "查看升级版"
	_upgrade_toggle.custom_minimum_size = Vector2(160, 40)
	# 引擎默认的两个状态图标是近黑的，压在深底上看不见，换成自己画的。
	CheckIcon.apply(_upgrade_toggle)
	_upgrade_toggle.toggled.connect(_on_upgrade_toggled)
	row.add_child(_upgrade_toggle)

	return row


## 耗能选项按「当前显示的版本」重算：勾了「查看升级版」之后显示的是升级版的费用，
## 选项列表还停在基础版的话，筛选值和格子里的数字就对不上了。
func _rebuild_cost_filter() -> void:
	if _cost_filter == null:
		return
	var previous: Variant = _cost_choice
	_cost_filter.clear()
	_cost_filter.add_item("全部耗能")
	_cost_choices.clear()
	var costs: Array[int] = []
	for card in _cards:
		var value: int = _cost_of(_display_variant(card))
		if value not in costs:
			costs.append(value)
	costs.sort()
	for value in costs:
		_cost_choices.append(value)
		_cost_filter.add_item("耗能 X" if value < 0 else "耗能 %d" % value)
	# 原来的选择还在就留住，不在了就退回「全部耗能」。
	_cost_filter.select(0)
	_cost_choice = null
	for i in _cost_choices.size():
		if previous != null and _cost_choices[i] == int(previous):
			_cost_filter.select(i + 1)
			_cost_choice = _cost_choices[i]
			break


func _on_upgrade_toggled(pressed: bool) -> void:
	_show_upgraded = pressed
	_rebuild_cost_filter()
	_refresh()


func _on_rarity_selected(index: int) -> void:
	_rarity_choice = index - 1
	_refresh()


func _on_cost_selected(index: int) -> void:
	_cost_choice = null if index == 0 else _cost_choices[index - 1]
	_refresh()


func _rarity_name(rarity: int) -> String:
	match rarity:
		CardData.CardRarity.BASIC: return "基础"
		CardData.CardRarity.COMMON: return "普通"
		CardData.CardRarity.UNCOMMON: return "罕见"
		CardData.CardRarity.RARE: return "稀有"
	return "未知"


func _cost_of(card: CardData) -> int:
	return -1 if card.is_x_cost() else card.cost


# --- 网格 ---

func _refresh() -> void:
	for i in _tab_buttons.size():
		var active := i == _active_tab
		_tab_buttons[i].add_theme_stylebox_override("normal",
			_solid_box(TAB_ON if active else TAB_OFF))
		_tab_buttons[i].add_theme_color_override("font_color",
			TAB_ON_TEXT if active else Color(0.82, 0.81, 0.88))

	for child in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()

	var shown := 0
	for card in _cards:
		if not _matches(card):
			continue
		_flow.add_child(_make_card_entry(card))
		shown += 1

	if shown == 0:
		var empty := Label.new()
		empty.text = "没有符合条件的卡牌"
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", MUTED)
		_flow.add_child(empty)


func _matches(card: CardData) -> bool:
	var tab: int = TAB_TYPES[_active_tab]
	if tab >= 0 and card.card_type != tab:
		return false
	if _rarity_choice >= 0 and card.rarity != _rarity_choice:
		return false
	if _cost_choice != null and _cost_of(_display_variant(card)) != int(_cost_choice):
		return false
	return true


## 勾了「查看升级版」就临时复制一份再升级——绝不能直接 upgrade() 数据库里那一份，
## 否则全体卡的名字会永久多出个「+」。
func _display_variant(card: CardData) -> CardData:
	if not _show_upgraded:
		return card
	var copy := card.duplicate() as CardData
	copy.upgrade()
	return copy


func _make_card_entry(card: CardData) -> Panel:
	var known := _is_known(card)
	var shown := _display_variant(card)
	# 边框＝角色归属、牌名＝稀有度，和战斗里那张牌一套映射。
	# 没遇见过的保持中性：边框不透露属于哪个角色，名字也还是 ???
	var border_color: Color = shown.get_character_border_color() if known else Color(0.34, 0.34, 0.42)
	var text_color: Color = shown.get_text_color() if known else MUTED

	var panel := Panel.new()
	panel.custom_minimum_size = CARD_SIZE
	panel.add_theme_stylebox_override("panel", _card_box(border_color))
	panel.tooltip_text = shown.get_description() if known else "尚未遇见"

	var box := VBoxContainer.new()
	box.anchors_preset = PRESET_FULL_RECT
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 12.0
	box.offset_top = 10.0
	box.offset_right = -12.0
	box.offset_bottom = -10.0
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	box.add_child(_make_cost_row(shown, known, border_color))

	var letter := shown.card_name.substr(0, 1) if known else "?"
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_row.add_child(CodexIcon.make_slot(shown.icon_texture, letter,
		shown.get_color(), known, SLOT_SIZE))
	box.add_child(slot_row)

	var name_label := Label.new()
	name_label.text = shown.card_name if known else "???"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", text_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = shown.get_description() if known else "尚未遇见"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", MUTED)
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc_label)

	return panel


func _make_cost_row(card: CardData, known: bool, border_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var orb := Panel.new()
	orb.custom_minimum_size = Vector2(28, 28)
	var orb_box := StyleBoxFlat.new()
	orb_box.bg_color = Color(0.14, 0.16, 0.30) if known else Color(0.16, 0.16, 0.20)
	orb_box.border_color = border_color
	orb_box.set_border_width_all(2)
	orb_box.set_corner_radius_all(14)
	orb.add_theme_stylebox_override("panel", orb_box)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cost_label := Label.new()
	if not known:
		cost_label.text = "?"
	elif card.is_x_cost():
		cost_label.text = "X"
	else:
		cost_label.text = str(card.cost)
	cost_label.anchors_preset = PRESET_FULL_RECT
	cost_label.anchor_right = 1.0
	cost_label.anchor_bottom = 1.0
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 15)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.add_child(cost_label)
	row.add_child(orb)

	# 类型图标走国风图（同卡面 TypeIcon 一路），缺图才退回符号字；known 与同页卡面槽同一个口径。
	# 槽取 28 跟同一行的耗能球同宽；make_slot 的四边内缩是写死的 6px，槽再小图标就只剩十个像素。
	# SHRINK_CENTER 是防 HBoxContainer 按行高把方槽拉成竖条（同族 [[bugfix-label-rect-grows]]）。
	var type_slot := CodexIcon.make_slot(ArtIcons.load_or_null(card.get_type_icon_path()),
		card.get_type_icon_text(), card.get_color(), known, TYPE_SLOT_SIZE)
	type_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(type_slot)

	var type_label := Label.new()
	if known:
		type_label.text = _type_name(card.card_type)
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", MUTED)
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(type_label)

	return row


func _type_name(type: int) -> String:
	match type:
		CardData.CardType.ATTACK: return "攻击"
		CardData.CardType.SKILL: return "技能"
		CardData.CardType.ABILITY: return "能力"
	return "未知"


func _is_known(card: CardData) -> bool:
	var mp := GameManager.meta_progress
	return mp == null or mp.has_seen_card(card.card_id)


func _solid_box(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(4)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	return box


func _card_box(border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CardData.PANEL_BG
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box
