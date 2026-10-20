class_name ScreenFeedback
extends RefCounted

## 条件不足时给玩家一句话，说清差在哪，而不是把按钮变灰堵死出路。
## 就地复用同一个 FeedbackLabel——条件不足是能反复点的，每次都 new 一个的话
## 同名节点会被引擎改名堆成一摞，先弹的那几句也还留在屏上。
## 事件页和商店页共用这一份，免得同一个「买不起」在两屏长出两种表现。
##
## rect 是相对屏幕中心的矩形（走 PRESET_CENTER 锚点）。各屏内容排布不一样，
## 位置必须由调用方给：照抄别处的偏移会盖住那一屏自己的东西。
static func show_message(screen: Node, msg: String, rect: Rect2) -> void:
	var label := screen.get_node_or_null("FeedbackLabel") as Label
	if label == null:
		label = Label.new()
		label.name = "FeedbackLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.anchors_preset = Control.PRESET_CENTER
		label.anchor_left = 0.5
		label.anchor_right = 0.5
		label.anchor_top = 0.5
		label.anchor_bottom = 0.5
		label.offset_left = rect.position.x
		label.offset_top = rect.position.y
		label.offset_right = rect.end.x
		label.offset_bottom = rect.end.y
		screen.add_child(label)
	label.text = msg
