extends Control

signal reward_selected(card: CardData)
signal reward_skipped

@export var cards_per_reward: int = 3

var offered_cards: Array[CardData] = []

@onready var card_container: HBoxContainer = %CardContainer
@onready var skip_button: Button = %SkipButton
@onready var gold_label: Label = %GoldLabel
@onready var potion_panel: Panel = %PotionPanel
@onready var potion_hbox: HBoxContainer = %PotionHBox
@onready var potion_name_label: Label = %PotionNameLabel
@onready var potion_desc_label: Label = %PotionDescLabel
@onready var relic_panel: Panel = %RelicPanel
@onready var relic_hbox: HBoxContainer = %RelicHBox
@onready var relic_name_label: Label = %RelicNameLabel
@onready var relic_desc_label: Label = %RelicDescLabel

## 图标槽尺寸。两块面板的高度是按它留的（见 card_reward_screen.tscn 的 offset）。
const REWARD_SLOT_SIZE: float = 64.0

func _ready() -> void:
	UIBackground.apply(self, "card_reward")
	skip_button.text = "跳过 (获得 %d 金币)" % _skip_gold_amount()
	skip_button.pressed.connect(_on_skip)
	# 三张牌抽一次就锁进存档：重进看到同一批奖励，不给重新随机的机会。
	var state := GameManager.ensure_node_state(_roll_state)
	_display_cards(state)
	_display_reward_info(state)

## 抽中的三张牌连着这局的金币和药水一起快照进存档。
## 金币/药水来自 pending_reward——它是战斗结算到这里的唯一一条内存桥，只有首次抽牌时有值；
## 重进时 pending_reward 是空的，改从快照里读，画面才和第一次一模一样。
func _roll_state() -> Dictionary:
	var rolled := DataManager.get_weighted_random_cards(
		cards_per_reward, DataManager.get_balance().card_rarity_weights)
	GameManager.mark_cards_seen(rolled)
	var card_ids: Array = []
	for card: CardData in rolled:
		card_ids.append(card.card_id)
	var reward := GameManager.pending_reward
	var potion := reward.get("potion_drop") as PotionData
	return {
		"card_ids": card_ids,
		"gold_earned": int(reward.get("gold_earned", 0)),
		"potion_id": potion.potion_id if potion else "",
		"relic_id": _roll_elite_relic(),
	}

## 精英必掉一件遗物。在这里发而不是另立一个界面：遗物 id 和金币/药水同一次快照落盘，
## 「重进不重发」的语义自动成立，不用再加标志位——_roll_state 只在首次进界面时跑一次。
func _roll_elite_relic() -> String:
	if GameManager.current_encounter_type != MapNodeData.NodeType.ELITE:
		return ""
	var relic := DataManager.get_random_obtainable_relic()
	if relic == null:
		return ""
	GameManager.add_relic(relic)
	return relic.relic_id

func _display_cards(state: Dictionary) -> void:
	var card_scene := load("res://scenes/battle/card.tscn")
	offered_cards.clear()
	for card_id: Variant in state.get("card_ids", []):
		var card_data := DataManager.get_card(str(card_id))
		if card_data == null:
			continue
		offered_cards.append(card_data)
		var preview := card_scene.instantiate() as Card
		preview.setup(card_data)
		card_container.add_child(preview)
		preview.set_playable(true)
		preview.card_clicked.connect(_on_card_selected)

func _display_reward_info(state: Dictionary) -> void:
	gold_label.text = "获得金币: %d  G" % int(state.get("gold_earned", 0))
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	var potion := DataManager.get_potion(str(state.get("potion_id", "")))
	if potion:
		potion_panel.visible = true
		potion_name_label.text = potion.potion_name
		potion_desc_label.text = potion.description
		# 图标槽插在文字前面（HBox 里移到第 0 位）。药水没有 make_relic_slot 那样的糖函数——
		# 那糖就是「读 RelicData 几个字段」，在这里就地一行比多包一层少一份要维护的映射。
		potion_hbox.add_child(CodexIcon.make_slot(
			ArtIcons.load_or_null(potion.get_icon_path()),
			potion.potion_name.substr(0, 1), potion.get_color(), true, REWARD_SLOT_SIZE))
		potion_hbox.move_child(potion_hbox.get_child(-1), 0)
	var relic := DataManager.get_relic(str(state.get("relic_id", "")))
	if relic:
		relic_panel.visible = true
		relic_name_label.text = relic.relic_name
		relic_desc_label.text = relic.description
		relic_hbox.add_child(CodexIcon.make_relic_slot(relic, REWARD_SLOT_SIZE))
		relic_hbox.move_child(relic_hbox.get_child(-1), 0)

func _on_card_selected(card: Card) -> void:
	GameManager.add_card_to_deck(card.card_data)
	reward_selected.emit(card.card_data)
	GameManager.pending_reward = {}
	# 走 finish_node 而不是自己 change_screen(MAP)：顺手把落点和快照清掉并落盘，
	# 这样「继续游戏」不会把玩家送回一个已经领过奖励的界面。
	GameManager.finish_node()

func _on_skip() -> void:
	GameManager.add_gold(_skip_gold_amount())
	reward_skipped.emit()
	GameManager.pending_reward = {}
	GameManager.finish_node()

func _skip_gold_amount() -> int:
	var bal := DataManager.get_balance()
	return bal.card_reward_skip_gold if bal else 20
