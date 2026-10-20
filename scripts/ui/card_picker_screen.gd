class_name CardPickerScreen
extends ColorRect

signal card_chosen(card: CardData)
signal pick_cancelled

@onready var title_label: Label = %TitleLabel
@onready var hint_label: Label = %HintLabel
@onready var card_grid: GridContainer = %CardGrid
@onready var close_button: Button = %CloseButton

var _cards: Array[CardData] = []
var _title: String = "选择一张卡牌"
var _cancelable: bool = true


## 宿主 setup 完自己 add_child()，选中的那张从 card_chosen 报回去，宿主负责改数据 + 落盘。
## 和 deck_view 的分工：那个是只读查看、关掉自己；这个是选择器，node_state 与 save_run()
## 都留在宿主手上——选卡器本身不碰存档。
func setup(cards: Array[CardData], title: String, cancelable: bool = true) -> void:
	_cards = cards
	_title = title
	_cancelable = cancelable
	if is_node_ready():
		_populate()


func _ready() -> void:
	close_button.pressed.connect(_on_cancel)
	_populate()


## ESC 关掉自己。走 _input 而不是 _unhandled_input：_input 是输入链第一站，
## 一定跑在全局那个 ESC（暂停菜单）前面，和 deck_view 同一套做法。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel()


func _populate() -> void:
	title_label.text = _title
	close_button.visible = _cancelable
	if _cards.is_empty():
		# 没得选也得关得掉，不能把玩家卡在这一层上。
		hint_label.text = "没有可选的卡牌"
		return
	hint_label.text = "点击一张卡牌"
	var card_scene := load("res://scenes/battle/card.tscn")
	for card_data in _cards:
		var preview: Card = card_scene.instantiate()
		preview.setup(card_data)
		# 这里和 deck_view 相反：牌是要点的，得按「可出牌」那副亮着的样子画。
		preview.set_playable(true)
		preview.card_clicked.connect(_on_card_clicked)
		card_grid.add_child(preview)


func _on_card_clicked(card: Card) -> void:
	card_chosen.emit(card.card_data)
	queue_free()


func _on_cancel() -> void:
	# 不可取消的选择（比如必须拿一件的奖励）吞掉 ESC 和关闭按钮，不给退路。
	if not _cancelable:
		return
	pick_cancelled.emit()
	queue_free()
