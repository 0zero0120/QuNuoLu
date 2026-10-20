class_name PortraitSlot
extends RefCounted

## 立绘槽：一块地方摆角色立绘，有图就画图，没图写一句占位。
## 角色选择页和角色详情页共用——两处是同一件事，说法也得一致，
## 免得一个写「立绘待接入」、另一个写「暂无立绘」。

const PLACEHOLDER_TEXT := "立绘待接入"
const PLACEHOLDER_COLOR := Color(0.42, 0.42, 0.52, 1.0)


## 往 holder 里塞立绘或占位文字。holder 的定位由调用方负责（各处留白不一样），
## 这里只管填内容。返回 holder，方便直接 add_child。
## accent 是本角色的流派色，传了就垫一层光晕（见 AccentHalo）；默认不传就不叠。
static func fill(holder: Control, portrait: Texture2D,
		accent := Color(0, 0, 0, 0)) -> Control:
	if portrait != null:
		if accent.a > 0.0:
			# 先加的排在前面，也就画在立绘底下。
			var halo := AccentHalo.make_rect(accent)
			halo.anchors_preset = Control.PRESET_FULL_RECT
			halo.anchor_right = 1.0
			halo.anchor_bottom = 1.0
			holder.add_child(halo)
		var rect := TextureRect.new()
		rect.texture = portrait
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.anchors_preset = Control.PRESET_FULL_RECT
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		var label := Label.new()
		label.text = PLACEHOLDER_TEXT
		label.anchors_preset = Control.PRESET_FULL_RECT
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", PLACEHOLDER_COLOR)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(label)
	return holder
