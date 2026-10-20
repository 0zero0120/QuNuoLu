class_name PlayHistory
extends Control

## 本场战斗打出去的全部牌，最新的在最前。战报浮层（按 H）看的就是它。
## 存的是当时算好的文字、不是节点：牌打出去之后敌人可能已经死了、节点已经释放，
## 拿着节点引用到后来再取，读的就是已释放实例了。
var records: Array[Dictionary] = []

## 战报是直接压在章节底图上的，没有自己的底板。三张底图是白纸水墨，白字不描边读不出来。
## 和 floating_number.tscn 用同一组值（那里也是飘在背景上的字）。
const OUTLINE_COLOR := Color(0, 0, 0, 1)
const OUTLINE_SIZE: int = 6

@onready var entries_vbox: VBoxContainer = $Scroll/Entries


func _ready() -> void:
	EventBus.card_played.connect(_on_card_played)


func _on_card_played(card: CardData, target: Variant) -> void:
	var target_text := target_name(target)
	records.push_front({"card": card, "target_text": target_text})
	var entry := make_entry(card, target_text)
	entries_vbox.add_child(entry)
	entries_vbox.move_child(entry, 0)


## 一行「牌名 → 目标」。窄条和战报浮层共用这一份，免得两边各写一套、日后改一处漏一处。
## 窄条只有一条缝宽，居中最省事；浮层铺满整屏，居中会让每行的左边缘参差不齐，得左对齐。
static func make_entry(card: CardData, target_text: String, font_size: int = 11, centered: bool = true) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_color_override("font_color", card.get_text_color())
	name_lbl.add_theme_font_size_override("font_size", font_size)
	name_lbl.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	name_lbl.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	var arrow := Label.new()
	arrow.text = " → "
	arrow.add_theme_font_size_override("font_size", font_size)
	arrow.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	arrow.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(arrow)

	var target_lbl := Label.new()
	target_lbl.text = target_text
	target_lbl.add_theme_font_size_override("font_size", font_size)
	target_lbl.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	target_lbl.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	target_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(target_lbl)

	return hbox


static func target_name(target: Variant) -> String:
	if target == null:
		return "—"
	if target is EnemyBase:
		if target.enemy_data:
			return target.enemy_data.display_name
		return "敌人"
	if target is Player:
		return "自己"
	if target is Array:
		return "全体"
	return "—"


func clear_history() -> void:
	records.clear()
	for child in entries_vbox.get_children():
		child.queue_free()
