class_name MapLegend
extends PanelContainer

## 右侧图例面板：把 MapNodeData.NodeType 里每一种节点摆一行「图标 + 名称」。
##
## 图标走**和地图节点同一个取图口**（ArtIcons + get_type_icon_path），所以图例里的小图
## 和地图上那些节点长得一模一样，一眼能对上；取不到才退回 emoji——缺图不是错误状态，
## 口径同 map_ui.gd 里那个节点按钮。
##
## 行是**从 NodeType 现生成的，不另写一份清单**：手写那份会跟 enum 脱钩，
## 以后尾部加了新类型它不会跟着多一行（同 map_node_data.gd 里那条注释的顾虑）。

const TITLE := "图例"
const ICON_SIZE := 48.0


func _ready() -> void:
	var rows := get_node_or_null("Rows") as VBoxContainer
	if rows == null:
		return
	rows.add_child(_make_title())
	for node_type in MapNodeData.NodeType.values():
		rows.add_child(_make_row(node_type))


func _make_title() -> Label:
	var label := Label.new()
	label.text = TITLE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.86, 0.42))
	return label


## 一行两个元素：图标 + 名称，整行水平居中。九种名字都是两个字，居中了才齐整。
func _make_row(node_type: int) -> HBoxContainer:
	var probe := MapNodeData.new()
	probe.node_type = node_type

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	# 每行摊平竖直空间。面板是整根右边栏（y 从 94 到屏底），不摊平的话九行会全堆在顶上、
	# 底下一大片空框。
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var icon := ArtIcons.load_or_null(probe.get_type_icon_path())
	if icon != null:
		var slot := TextureRect.new()
		slot.texture = icon
		# expand_mode 不设的话，TextureRect 的最小尺寸就是贴图本身那 256px，会把这一行撑爆
		# （同族 [[bugfix_texture_expand_mode_blows_anchors]]）。
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		# SHRINK_CENTER 是防 HBoxContainer 按行高把方槽拉成竖条（同族 [[bugfix-label-rect-grows]]）。
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slot)
	else:
		var fallback := Label.new()
		fallback.text = probe.get_type_icon()
		fallback.custom_minimum_size = Vector2(ICON_SIZE, 0.0)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 28)
		fallback.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(fallback)

	var name_label := Label.new()
	# 起个名字，好让回归测试按名取——不然它只能靠「最后一个子节点」这种位置约定去猜哪行是哪行。
	name_label.name = "Name"
	name_label.text = probe.get_type_name()
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))
	row.add_child(name_label)
	return row
