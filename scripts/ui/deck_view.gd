class_name DeckView
extends ColorRect

@onready var card_grid: GridContainer = %CardGrid
@onready var close_button: Button = %CloseButton
@onready var title_label: Label = %TitleLabel

var _cards: Array[CardData] = []
var _title: String = "牌组"


## 显式指定要看哪一堆牌。空数组就是空页——不会退回显示整副牌组。
## 这一点很重要：消耗堆空着的时候如果显示成满满一堆牌，玩家会以为里面有东西。
func setup(cards: Array[CardData], title: String = "牌组") -> void:
	_cards = cards
	_title = title
	if is_node_ready():
		_populate()


func _ready() -> void:
	close_button.pressed.connect(_on_close)
	_populate()


## ESC 关掉自己。走 _input 而不是 _unhandled_input：_input 是输入链第一站，
## 与节点在树里的顺序无关，一定跑在全局那个 ESC（GameManager 的暂停菜单）前面。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()


func _populate() -> void:
	title_label.text = "%s (%d 张)" % [_title, _cards.size()]
	if _cards.is_empty():
		var empty := Label.new()
		empty.text = "这里现在没有牌"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
		card_grid.add_child(empty)
		return
	var card_scene := load("res://scenes/battle/card.tscn")
	for card_data in _cards:
		var preview: Card = card_scene.instantiate()
		preview.setup(card_data)
		preview.set_playable(false)
		card_grid.add_child(preview)


func _on_close() -> void:
	queue_free()
