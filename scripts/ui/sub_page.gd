class_name SubPage
extends ColorRect

## 通用子页：标题 + 可滚动内容区 + 左下返回。
## 调用方通过 setup(title, fill) 传入填充函数，填充函数收到本页实例，
## 用 add_row / add_note 往内容区里排版。

const ROW_HEIGHT := 56

var _title: String = ""
var _fill: Callable = Callable()
var _body: VBoxContainer


func setup(title: String, fill: Callable = Callable()) -> void:
	_title = title
	_fill = fill


func _ready() -> void:
	anchors_preset = PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	color = Color(0.06, 0.06, 0.12, 1.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_add_background()
	_build()


## 底图沿用主菜单那张水墨：这一族页面都是从主菜单翻开的，视觉上得是同一套。
## 内容密，压得比子菜单更暗一档，再垫一块半透明内容框把字托住。
func _add_background() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Background"
	backdrop.color = color
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	UIBackground.apply(self, "main_menu", 0.42)


func _add_content_frame() -> void:
	var frame := Panel.new()
	frame.name = "ContentFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 92.0
	frame.offset_top = 112.0
	frame.offset_right = -92.0
	frame.offset_bottom = -98.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.62)
	style.border_color = Color(0.42, 0.36, 0.24, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)


func _build() -> void:
	var title_label := Label.new()
	title_label.text = _title
	title_label.anchors_preset = PRESET_CENTER_TOP
	title_label.anchor_left = 0.5
	title_label.anchor_right = 0.5
	title_label.offset_left = -300.0
	title_label.offset_top = 40.0
	title_label.offset_right = 300.0
	title_label.offset_bottom = 92.0
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	UiTitlePlaque.apply(title_label, 44)
	add_child(title_label)
	_add_content_frame()

	var margin := MarginContainer.new()
	margin.anchors_preset = PRESET_FULL_RECT
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 110.0
	margin.offset_top = 120.0
	margin.offset_right = -110.0
	margin.offset_bottom = -110.0
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

	add_child(_make_back_button())

	if _fill.is_valid():
		_fill.call(self)


## 往内容区里放任意节点，供 collect 类页面自定义排版。
func add_content(node: Control) -> Control:
	_body.add_child(node)
	return node


func add_row(name_text: String, right_text: String = "") -> Panel:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var hbox := HBoxContainer.new()
	hbox.anchors_preset = PRESET_FULL_RECT
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = 18.0
	hbox.offset_right = -18.0
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	if not right_text.is_empty():
		var right_label := Label.new()
		right_label.text = right_text
		right_label.add_theme_font_size_override("font_size", 14)
		right_label.add_theme_color_override("font_color", Color(0.62, 0.60, 0.70))
		right_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(right_label)

	_body.add_child(row)
	return row


func add_note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 120)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_body.add_child(label)
	return label


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
