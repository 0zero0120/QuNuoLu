class_name CardUpgradePreview
extends Control

## 升级完成后把「升级前 / 升级后」两张牌并排摆出来。
## 只改数据不给看结果的话，玩家看到的就是一行「已升级」——升了什么、值不值，
## 全靠自己记原来的数字。这里复用战斗里的 Card 场景，显示的就是真实卡面。
##
## 模态只做到「挡住输入」：全屏 Control 吃鼠标，_input 吃点击/ESC。
## 不暂停整棵树，免得休息站/事件页的音频和环境音被一起冻住。

const CARD_SCALE: float = 1.5
const CARD_SIZE := Vector2(180.0, 252.0)

var _before: CardData
var _after: CardData
## 打开这张浮层的鼠标事件（选卡器里那次点击）不能顺手把它关掉，等一帧再武装。
var _armed: bool = false


static func show_for(host: Node, before: CardData, after: CardData) -> void:
	if host == null or after == null:
		return
	var overlay := CardUpgradePreview.new()
	overlay._before = before
	overlay._after = after
	host.add_child(overlay)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	_build()
	await get_tree().process_frame
	_armed = true


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var title := Label.new()
	title.text = "升级成功"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTitlePlaque.apply(title, 44)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 56)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	row.add_child(_make_column("升级前", _before))
	row.add_child(_make_column("升级后", _after))

	var hint := Label.new()
	hint.text = "点击任意处继续"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.82, 0.78, 0.68, 1.0))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 4)
	box.add_child(hint)


func _make_column(caption_text: String, data: CardData) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var caption := Label.new()
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color",
		Color(0.93, 0.86, 0.66, 1.0) if data != null and data.upgraded
		else Color(0.66, 0.64, 0.60, 1.0))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 4)
	col.add_child(caption)

	var wrap := Control.new()
	wrap.custom_minimum_size = CARD_SIZE * CARD_SCALE
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(wrap)

	if data == null:
		return col
	var card_scene := load("res://scenes/battle/card.tscn") as PackedScene
	if card_scene == null:
		return col
	var card := card_scene.instantiate() as Card
	card.setup(data)
	# 卡面是按 180x252 画的，整节点 scale 放大；改字号/改尺寸会破坏卡面版式。
	card.scale = Vector2(CARD_SCALE, CARD_SCALE)
	card.position = Vector2.ZERO
	card.set_playable(true)
	card.card_clicked.connect(func(_card: Card) -> void: _close())
	wrap.add_child(card)
	return col


func _input(event: InputEvent) -> void:
	if not _armed:
		return
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if is_queued_for_deletion():
		return
	queue_free()
