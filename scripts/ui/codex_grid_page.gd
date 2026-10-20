class_name CodexGridPage
extends SubPage

## 收集类百科页（遗物收集 / 药水研究所）：按稀有度分组，每组一行标题 + 一行说明 + 图标网格。
## 参考杀戮尖塔：只显示遇见过的条目，没遇见过的画挂锁。
##
## setup_groups(title, groups)，groups 每项为
## {"header": String, "desc": String, "entries": Array}
## entries 每项为 {"name": String, "icon": Texture2D, "color": Color,
##                 "desc": String, "known": bool}

const SLOT_SIZE := 76.0
const HEADER_COLOR := Color(0.92, 0.86, 0.72)
const DESC_COLOR := Color(0.52, 0.50, 0.60)
const NAME_COLOR := Color(0.80, 0.79, 0.87)

var _groups: Array = []


func setup_groups(title: String, groups: Array) -> void:
	_groups = groups
	setup(title, _fill_groups)


func _fill_groups(_page: SubPage) -> void:
	var first := true
	for group: Dictionary in _groups:
		if not first:
			add_content(_make_gap(26))
		first = false
		_add_group(group)


func _add_group(group: Dictionary) -> void:
	var entries: Array = group.get("entries", [])
	var known_count := 0
	for entry: Dictionary in entries:
		if bool(entry.get("known", false)):
			known_count += 1

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)

	var header := Label.new()
	header.text = String(group.get("header", ""))
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	header_row.add_child(header)

	var counter := Label.new()
	counter.text = "%d / %d" % [known_count, entries.size()]
	counter.add_theme_font_size_override("font_size", 15)
	counter.add_theme_color_override("font_color", DESC_COLOR)
	counter.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	header_row.add_child(counter)
	add_content(header_row)

	var desc := Label.new()
	desc.text = String(group.get("desc", ""))
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", DESC_COLOR)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_content(desc)

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "暂无内容"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", DESC_COLOR)
		add_content(empty)
		return

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 18)
	add_content(flow)
	for entry: Dictionary in entries:
		flow.add_child(_make_entry(entry))


func _make_entry(entry: Dictionary) -> Control:
	var known := bool(entry.get("known", false))
	var color: Color = entry.get("color", Color.WHITE)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(SLOT_SIZE, 0)
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.tooltip_text = String(entry.get("desc", "")) if known else "尚未遇见"

	var name_text := String(entry.get("name", ""))
	var letter := name_text.substr(0, 1) if not name_text.is_empty() else "?"
	column.add_child(CodexIcon.make_slot(entry.get("icon") as Texture2D, letter, color, known, SLOT_SIZE))

	var name_label := Label.new()
	name_label.text = name_text if known else "???"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", NAME_COLOR if known else DESC_COLOR)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	return column


func _make_gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
