class_name UiTitlePlaque
extends RefCounted

## 把主菜单那面匾额垫到标题后面，并换成书法字。角色选择 / 百科 / 统计 / 设定
## 这些副界面共用这一套标题观感。
##
## **图取不到就只换字**，标题照旧可见（同主菜单、角色页的口径）。

const TITLE_FONT: FontFile = preload("res://assets/fonts/MaShanZheng-Regular.ttf")


static func apply(label: Label, font_size: int) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.93, 0.90, 0.82, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 0.9))
	label.add_theme_constant_override("outline_size", 8)

	var plaque := UIBackground.load_or_null("title_plaque")
	if plaque == null or label.get_node_or_null("TitlePlaque") != null:
		return
	var image := TextureRect.new()
	image.name = "TitlePlaque"
	image.texture = plaque
	# 匾额只在字后面当底衬：不挡点击，也不参与标题的排版尺寸。
	image.show_behind_parent = true
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var half_width := font_size * 2.1
	var half_height := font_size * 1.0
	image.offset_left = -half_width
	image.offset_top = -half_height
	image.offset_right = half_width
	image.offset_bottom = half_height
	label.add_child(image)
