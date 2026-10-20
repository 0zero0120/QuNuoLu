class_name SubmenuScreen
extends ColorRect

## 通用子菜单：标题 + 横排羊皮纸卡片 + 左下返回。
## 参考杀戮尖塔，百科大全 / 统计内容 / 设定 共用此组件。
## items 每项为 {"title": String, "desc": String, "on_press": Callable}

const CARD_SIZE := Vector2(240, 320)

const PARCHMENT := Color(0.85, 0.77, 0.60)
const PARCHMENT_HOVER := Color(0.93, 0.86, 0.71)
const PARCHMENT_PRESSED := Color(0.74, 0.66, 0.49)
const BORDER := Color(0.30, 0.22, 0.13)
const INK := Color(0.16, 0.11, 0.06)
const MUTED := Color(0.35, 0.27, 0.17)

var _title: String = ""
var _items: Array = []


func setup(title: String, items: Array) -> void:
	_title = title
	_items = items


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	color = Color(0.06, 0.06, 0.12, 1.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_add_background()
	_build()


## 主菜单那层水墨底图垫在下面，往外压暗一档——卡片本身是浅色羊皮纸，
## 底图再亮就会抢字。取不到图时本页的深色兜底照样铺满。
func _add_background() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Background"
	backdrop.color = color
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	UIBackground.apply(self, "main_menu", 0.55)


func _build() -> void:
	var title_label := Label.new()
	title_label.text = _title
	title_label.anchors_preset = PRESET_CENTER_TOP
	title_label.anchor_left = 0.5
	title_label.anchor_right = 0.5
	title_label.offset_left = -300.0
	title_label.offset_top = 90.0
	title_label.offset_right = 300.0
	title_label.offset_bottom = 150.0
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 40)
	# 匾额比字大一圈，但只当底衬；字号、位置都还由上面这组 offset 说了算。
	UiTitlePlaque.apply(title_label, 48)
	add_child(title_label)

	var row := HBoxContainer.new()
	row.anchor_left = 0.5
	row.anchor_top = 0.5
	row.anchor_right = 0.5
	row.anchor_bottom = 0.5
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	add_child(row)
	for item: Dictionary in _items:
		row.add_child(_make_card(item))

	add_child(_make_back_button())


func _make_card(item: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.add_theme_stylebox_override("normal", _parchment_box(PARCHMENT))
	card.add_theme_stylebox_override("hover", _parchment_box(PARCHMENT_HOVER))
	card.add_theme_stylebox_override("pressed", _parchment_box(PARCHMENT_PRESSED))
	card.add_theme_stylebox_override("focus", _parchment_box(PARCHMENT))

	var box := VBoxContainer.new()
	box.anchors_preset = PRESET_FULL_RECT
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 20.0
	box.offset_top = 28.0
	box.offset_right = -20.0
	box.offset_bottom = -28.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	box.add_child(_make_card_text(String(item.get("title", "")), 26, INK))
	box.add_child(_make_illustration(item.get("illustration") as Texture2D))

	box.add_child(_make_card_text(String(item.get("desc", "")), 14, MUTED))

	var handler: Callable = item.get("on_press", Callable())
	if handler.is_valid():
		card.pressed.connect(handler)
	return card


## 卡片中部的插图位，美术未接入时画一块占位。
func _make_illustration(texture: Texture2D) -> Control:
	var holder := Panel.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(0, 130)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.72, 0.64, 0.48)
	frame.border_color = BORDER
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(4)
	holder.add_theme_stylebox_override("panel", frame)

	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 插图一律裁切填满：事件插画是宽幅横幅，留边等比缩放会缩成一条小画。
		# 内缩 2px 让出下面那圈墨线边框，不然图会把框盖掉。
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.offset_left = 2.0
		rect.offset_top = 2.0
		rect.offset_right = -2.0
		rect.offset_bottom = -2.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		var placeholder := Label.new()
		placeholder.text = "插图待接入"
		placeholder.anchors_preset = PRESET_FULL_RECT
		placeholder.anchor_right = 1.0
		placeholder.anchor_bottom = 1.0
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 13)
		placeholder.add_theme_color_override("font_color", Color(0.48, 0.41, 0.31))
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(placeholder)

	return holder


func _make_card_text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _parchment_box(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = BORDER
	box.set_border_width_all(4)
	box.set_corner_radius_all(8)
	return box


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
	button.pressed.connect(_on_back)
	return button


func _on_back() -> void:
	queue_free()
