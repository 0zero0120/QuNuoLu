class_name RunHistoryPage
extends SubPage

## 统计内容 → 历史记录：三个筛选下拉 + 一屏一局的翻页 + 对局卡片。
## 参考杀戮尖塔：顶部三个下拉（结果 / 角色 / 难度），一次只看一局，用 ◀ ▶ 翻。
##
## 数据来自 RunHistory（user://run_history.json，最近 50 局），由 GameManager.finish_run() 写入。

const CHIP_SIZE := 44.0
const CHIP_WIDTH := 150.0
const DECK_COLUMNS := 3

const HEADER_COLOR := Color(0.92, 0.86, 0.72)
const VALUE_COLOR := Color(0.92, 0.80, 0.45)
const NAME_COLOR := Color(0.80, 0.79, 0.87)
const MUTED := Color(0.52, 0.50, 0.60)
const WIN_COLOR := Color(0.45, 0.85, 0.45)
const LOSE_COLOR := Color(0.90, 0.45, 0.40)

## 结果下拉的取值，索引 0 是「全部」哨兵。
const RESULT_VALUES := [-1, 1, 0]

var _records: Array[Dictionary] = []
var _index: int = 0

var _result_filter: OptionButton
var _character_filter: OptionButton
var _ascension_filter: OptionButton
var _character_ids: Array[String] = []
var _ascensions: Array[int] = []

var _pager_label: Label
var _prev_button: Button
var _next_button: Button
var _holder: VBoxContainer


func setup_page(title: String) -> void:
	setup(title, _fill_page)


func _fill_page(_page: SubPage) -> void:
	add_content(_make_filter_row())
	add_content(_make_gap(18))
	add_content(_make_pager_row())
	add_content(_make_gap(18))

	_holder = VBoxContainer.new()
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holder.add_theme_constant_override("separation", 10)
	add_content(_holder)

	_apply_filters()


# --- 筛选 ---

func _make_filter_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	_result_filter = OptionButton.new()
	_result_filter.custom_minimum_size = Vector2(160, 40)
	for label: String in ["全部结果", "胜利", "失败"]:
		_result_filter.add_item(label)
	_result_filter.item_selected.connect(_on_filter_changed)
	row.add_child(_result_filter)

	_character_filter = OptionButton.new()
	_character_filter.custom_minimum_size = Vector2(160, 40)
	_character_filter.add_item("所有角色")
	_character_ids.clear()
	for character: PlayerData in DataManager.characters_in_order():
		_character_ids.append(character.character_id)
		_character_filter.add_item(character.character_name)
	_character_filter.item_selected.connect(_on_filter_changed)
	row.add_child(_character_filter)

	_ascension_filter = OptionButton.new()
	_ascension_filter.custom_minimum_size = Vector2(160, 40)
	_ascension_filter.add_item("任意难度")
	_ascensions.clear()
	var seen: Array[int] = []
	for record: Dictionary in GameManager.get_run_history().records:
		var value := int(record.get("ascension", 1))
		if value not in seen:
			seen.append(value)
	seen.sort()
	for value in seen:
		_ascensions.append(value)
		_ascension_filter.add_item(AscensionText.label(value))
	_ascension_filter.item_selected.connect(_on_filter_changed)
	row.add_child(_ascension_filter)

	return row


func _on_filter_changed(_index: int) -> void:
	_apply_filters()


## 后端没有「模式」这个概念，第三个下拉按当局的难度筛（记录的难度是开局快照的）。
func _apply_filters() -> void:
	var result_choice: int = RESULT_VALUES[_result_filter.selected]
	var character_choice := ""
	if _character_filter.selected > 0:
		character_choice = _character_ids[_character_filter.selected - 1]
	var ascension_choice: Variant = null
	if _ascension_filter.selected > 0:
		ascension_choice = _ascensions[_ascension_filter.selected - 1]

	_records.clear()
	for record: Dictionary in GameManager.get_run_history().records:
		if result_choice >= 0 and int(bool(record.get("victory", false))) != result_choice:
			continue
		if not character_choice.is_empty() and str(record.get("character_id", "")) != character_choice:
			continue
		if ascension_choice != null and int(record.get("ascension", 1)) != int(ascension_choice):
			continue
		_records.append(record)

	_index = 0
	_refresh()


# --- 翻页 ---

func _make_pager_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	_prev_button = Button.new()
	_prev_button.text = "◀"
	_prev_button.custom_minimum_size = Vector2(56, 40)
	_prev_button.add_theme_font_size_override("font_size", 18)
	_prev_button.pressed.connect(_on_prev)
	row.add_child(_prev_button)

	_pager_label = Label.new()
	_pager_label.custom_minimum_size = Vector2(160, 0)
	_pager_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pager_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pager_label.add_theme_font_size_override("font_size", 17)
	_pager_label.add_theme_color_override("font_color", NAME_COLOR)
	row.add_child(_pager_label)

	_next_button = Button.new()
	_next_button.text = "▶"
	_next_button.custom_minimum_size = Vector2(56, 40)
	_next_button.add_theme_font_size_override("font_size", 18)
	_next_button.pressed.connect(_on_next)
	row.add_child(_next_button)

	return row


func _on_prev() -> void:
	if _index <= 0:
		return
	_index -= 1
	_refresh()


func _on_next() -> void:
	if _index >= _records.size() - 1:
		return
	_index += 1
	_refresh()


# --- 记录卡 ---

func _refresh() -> void:
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()

	var size := _records.size()
	if size > 0:
		_pager_label.text = "第 %d / %d 局" % [_index + 1, size]
	else:
		_pager_label.text = "第 0 / 0 局"
	_prev_button.disabled = _index <= 0
	_next_button.disabled = size == 0 or _index >= size - 1

	if size == 0:
		_holder.add_child(_make_note(
			"还没有对局记录" if GameManager.get_run_history().is_empty() else "没有符合条件的对局"))
		return

	_holder.add_child(_make_record_card(_records[_index]))


func _make_record_card(record: Dictionary) -> Control:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 10)

	var character_id := str(record.get("character_id", ""))
	card.add_child(_make_top_row(record, character_id))
	card.add_child(_make_result_label(record))
	card.add_child(_make_text_line("分数：%d" % int(record.get("score", 0)), VALUE_COLOR))

	var relic_ids: Array = record.get("relic_ids", [])
	card.add_child(_make_text_line("遗物 (%d)" % relic_ids.size(), HEADER_COLOR))
	var relic_flow := HFlowContainer.new()
	relic_flow.add_theme_constant_override("h_separation", 12)
	relic_flow.add_theme_constant_override("v_separation", 12)
	card.add_child(relic_flow)
	if relic_ids.is_empty():
		relic_flow.add_child(_make_note("这一局没有遗物"))
	else:
		for relic_id: Variant in relic_ids:
			relic_flow.add_child(_make_relic_chip(str(relic_id)))

	var deck_ids: Array = record.get("deck_card_ids", [])
	var upgraded: Array = record.get("deck_card_upgraded", [])
	card.add_child(_make_text_line("牌组 (%d)" % deck_ids.size(), HEADER_COLOR))
	if deck_ids.is_empty():
		card.add_child(_make_note("这一局没有牌组记录"))
	else:
		var grid := GridContainer.new()
		grid.columns = DECK_COLUMNS
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		card.add_child(grid)
		for i in deck_ids.size():
			var is_upgraded := i < upgraded.size() and bool(upgraded[i])
			grid.add_child(_make_card_chip(str(deck_ids[i]), is_upgraded))

	return card


func _make_top_row(record: Dictionary, character_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var name_label := Label.new()
	name_label.text = str(record.get("character_name", character_id))
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", HEADER_COLOR)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	row.add_child(_make_text_line(AscensionText.label(int(record.get("ascension", 1))), HEADER_COLOR))

	row.add_child(_make_run_selector(character_id))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# 种子补足九位显示：玩家在角色详情页填的就是这一串，照着敲能重开同一局。
	# 0 表示这一局没有种子（更早的记录），显示「—」而不是九个零。
	var seed_value := int(record.get("run_seed", 0))
	var seed_text := "%09d" % seed_value if seed_value > 0 else "—"
	row.add_child(_make_text_line("种子编号：%s" % seed_text, MUTED))

	return row


## 该角色在本轮筛选结果里的几局，选一局直接跳过去。
func _make_run_selector(character_id: String) -> OptionButton:
	var indices: Array[int] = []
	for i in _records.size():
		if str(_records[i].get("character_id", "")) == character_id:
			indices.append(i)

	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(140, 40)
	var selected_pos := 0
	for pos in indices.size():
		# 编号用记录在筛选结果里的位置，跟上面的翻页标签同一套口径——
		# 否则同一个记录会出现「翻页说第 1 局、下拉说第 2 局」。
		selector.add_item("第 %d 局" % (indices[pos] + 1))
		if indices[pos] == _index:
			selected_pos = pos
	selector.select(selected_pos)
	selector.disabled = indices.size() <= 1
	selector.item_selected.connect(func(pos: int) -> void:
		if pos >= 0 and pos < indices.size():
			_index = indices[pos]
			_refresh())
	return selector


func _make_result_label(record: Dictionary) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 19)
	if bool(record.get("victory", false)):
		label.text = "胜利"
		label.add_theme_color_override("font_color", WIN_COLOR)
	else:
		label.text = "在第 %d 层阵亡" % int(record.get("floor", 0))
		label.add_theme_color_override("font_color", LOSE_COLOR)
	return label


# --- 小图标片 ---

func _make_relic_chip(relic_id: String) -> Control:
	var relic := DataManager.get_relic(relic_id)
	var name_text := relic.relic_name if relic else relic_id
	var color: Color = relic.get_color() if relic else MUTED
	# 卡牌小片走的是 card.icon_texture（见 _make_card_chip），那是 null——卡牌插画是
	# 276x140 横幅，塞进方形小槽会成一条细横条。遗物这边才是按 id 取方图标。
	var icon: Texture2D = ArtIcons.load_or_null(relic.get_icon_path()) if relic else null
	return _make_chip(icon, name_text, color, NAME_COLOR)


func _make_card_chip(card_id: String, upgraded: bool) -> Control:
	var card := DataManager.get_card(card_id)
	var name_text := card.card_name if card else card_id
	if upgraded:
		name_text += "+"
	# 和卡面同一套映射：槽边框＝角色归属，首字和名字＝稀有度。
	var border: Color = card.get_character_border_color() if card else MUTED
	var text: Color = card.get_text_color() if card else MUTED
	return _make_chip(card.icon_texture if card else null, name_text, border, text)


## 项目里没有现成的「卡牌小片」控件，复用 CodexIcon 的方形图标槽 + 名字，不再造一个新控件。
## border_color 管图标槽的框，text_color 管首字和名字（卡牌那边两个色不一样，见 make_slot）。
func _make_chip(icon: Texture2D, name_text: String, border_color: Color, text_color: Color) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(CHIP_WIDTH, 0)
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.tooltip_text = name_text

	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var letter := name_text.substr(0, 1) if not name_text.is_empty() else "?"
	slot_row.add_child(CodexIcon.make_slot(icon, letter, border_color, true, CHIP_SIZE, text_color))
	column.add_child(slot_row)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", text_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	return column


# --- 排版小工具 ---

func _make_text_line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _make_gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
