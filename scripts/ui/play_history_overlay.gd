class_name PlayHistoryOverlay
extends CanvasLayer

## 对局中按 H 打开的本场战报：这一场打出去过的牌全在，能滚。窄条那个只露最新的几条，
## 想看全的就到这儿来。
##
## 只读，不改任何状态：看完按「返回」、ESC、H 关掉，回到打开之前那一刻。
## 打开期间整棵树是暂停的（暂停由 GameManager 开、也由它收）：底下那场战斗就该冻住，
## 不然看战报的时候敌人照样打你、按数字键还能把手牌打出去。

## 压在暂停菜单（100）下面、盖在战斗画面上面。和地图浮层同一层。
const LAYER: int = 90

## 浮层里地方够，不必挤成窄条那样的小字。
const FONT_SIZE: int = 18

## 标题离顶边的距离。全局横条（RunHud）高 56，画在 layer 比本浮层高的画布上盖不住，
## 标题压在那个高度上会被横条糊成一团——所以从横条底下让开再写。
const TOP_MARGIN: float = 72.0

## 「返回」那颗红底，和地图浮层保持一致。
const RETURN_BG := Color(0.55, 0.16, 0.16, 1.0)
const RETURN_BORDER := Color(0.85, 0.42, 0.42, 1.0)

## 列表左边要给「返回」让道。那颗按钮和地图浮层里那颗同一个摆法（map_scene 的 ReturnButton：
## 锚在左侧居中、横向 16~116），地图那边内容是一整块画布，压着不碍事；这边是贴左边排的文字，
## 不让开的话滚到中段按钮就把字糊了。
const LIST_LEFT: float = 140.0

var _records: Array[Dictionary] = []


## 得在进树**之前**把数据塞好：_ready() 里就要照着它建列表。
func setup(records: Array[Dictionary]) -> void:
	_records = records


func _ready() -> void:
	layer = LAYER
	# 整棵树是暂停的，浮层自己得照样收得到输入。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## ESC 和 H 都用来关掉自己。走 _input（输入链第一站）：这里吃掉之后，
## 全局那个 ESC（暂停菜单）根本收不到，不会变成「关掉战报又弹出暂停」。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("view_history"):
		get_viewport().set_input_as_handled()
		close()


## 「返回」按钮、ESC、H 三条路都走这里。
func close() -> void:
	GameManager.close_play_history()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var title := Label.new()
	title.name = "Title"
	title.text = "本场战报 (%d)" % _records.size()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -200.0
	title.offset_top = TOP_MARGIN
	title.offset_right = 200.0
	title.offset_bottom = TOP_MARGIN + 28.0
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.follow_focus = true
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = LIST_LEFT
	scroll.offset_top = TOP_MARGIN + 40.0
	scroll.offset_right = -24.0
	scroll.offset_bottom = -24.0
	add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	# 空列表也照样把浮层摆出来（打死活说清「这一场还没出过牌」），
	# 不然就成了一张黑屏，玩家只会以为按坏了。正常路走不到这儿：GameManager 没东西就不开。
	if _records.is_empty():
		var empty := Label.new()
		empty.text = "这一场还没打出过牌"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
		list.add_child(empty)
	else:
		for record in _records:
			list.add_child(PlayHistory.make_entry(record["card"], record["target_text"], FONT_SIZE, false))

	var back := Button.new()
	back.name = "BackButton"
	back.text = "返回"
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", Color(1, 0.94, 0.94, 1))
	var style := StyleBoxFlat.new()
	style.bg_color = RETURN_BG
	style.border_color = RETURN_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	back.add_theme_stylebox_override("normal", style)
	back.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	back.offset_left = 16.0
	back.offset_top = -24.0
	back.offset_right = 116.0
	back.offset_bottom = 24.0
	back.pressed.connect(close)
	add_child(back)
