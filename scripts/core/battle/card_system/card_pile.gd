class_name CardPile
extends Node

signal deck_empty
signal pile_changed

var draw_pile: Array[CardData] = []
var hand: Array[Card] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []

@export var max_hand_size: int = 10

func initialize(deck: Array[CardData]) -> void:
	draw_pile.clear()
	for card in deck:
		draw_pile.append(card.duplicate())
	shuffle_draw_pile()
	discard_pile.clear()
	exhaust_pile.clear()
	hand.clear()
	# 洗完牌就得报一次：三个牌堆计数只认 pile_changed，不发这一下，
	# 界面会一直停在战斗场景里写死的「抽牌堆: 0」，直到玩家打出第一张牌才跳变。
	pile_changed.emit()

func shuffle_draw_pile() -> void:
	GameManager.rand_shuffle(draw_pile)

func _reshuffle_discard_into_draw() -> void:
	if discard_pile.is_empty():
		return
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	shuffle_draw_pile()

func draw_card_data() -> CardData:
	if draw_pile.is_empty():
		_reshuffle_discard_into_draw()
	if draw_pile.is_empty():
		deck_empty.emit()
		return null
	var card: CardData = draw_pile.pop_front()
	return card

func draw_to_hand(count: int, hand_container: Control, card_scene: PackedScene) -> int:
	var drawn := 0
	for _i in range(count):
		if hand.size() >= max_hand_size:
			break
		var card_data := draw_card_data()
		if card_data == null:
			break
		var card: Card = card_scene.instantiate()
		card.setup(card_data)
		hand_container.add_child(card)
		hand.append(card)
		drawn += 1
		EventBus.card_drawn.emit(card_data)
	# 抽牌也改了牌堆（抽牌堆变少，中途洗牌还会动弃牌堆），整批抽完报一次就够。
	# 逐张报会白白刷 5 次界面，所以放在循环外面。
	if drawn > 0:
		pile_changed.emit()
	return drawn

func discard_card(card: Card) -> void:
	if card.card_data == null:
		return
	discard_pile.append(card.card_data)
	hand.erase(card)
	pile_changed.emit()
	EventBus.card_discarded.emit(card.card_data)

func discard_hand(hand_container: Control) -> void:
	for card in hand.duplicate():
		discard_pile.append(card.card_data)
		hand_container.remove_child(card)
		card.queue_free()
	hand.clear()
	pile_changed.emit()

func exhaust_card(card: Card) -> void:
	if card.card_data == null:
		return
	exhaust_pile.append(card.card_data)
	hand.erase(card)
	EventBus.card_exhausted.emit(card.card_data)
	pile_changed.emit()

func add_to_deck(card: CardData, to_draw: bool = false) -> void:
	if to_draw:
		draw_pile.push_front(card)
	else:
		discard_pile.append(card)
	pile_changed.emit()

func remove_from_deck(card_data: CardData) -> bool:
	for i in range(draw_pile.size()):
		if draw_pile[i] == card_data:
			draw_pile.remove_at(i)
			pile_changed.emit()
			return true
	for i in range(discard_pile.size()):
		if discard_pile[i] == card_data:
			discard_pile.remove_at(i)
			pile_changed.emit()
			return true
	for i in range(hand.size()):
		if hand[i].card_data == card_data:
			hand[i].queue_free()
			hand.remove_at(i)
			pile_changed.emit()
			return true
	return false

func get_total_deck_size() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()

func get_draw_pile_size() -> int:
	return draw_pile.size()

func get_discard_pile_size() -> int:
	return discard_pile.size()
