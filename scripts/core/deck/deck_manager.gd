class_name DeckManager
extends RefCounted

var current_deck: Array[CardData] = []

func initialize(starting_cards: Array[CardData]) -> void:
	current_deck = starting_cards.duplicate()

func add_card(card: CardData) -> void:
	current_deck.append(card)
	EventBus.card_added_to_deck.emit(card)

func remove_card(card: CardData) -> bool:
	var idx := current_deck.find(card)
	if idx >= 0:
		current_deck.remove_at(idx)
		EventBus.card_removed_from_deck.emit(card)
		return true
	return false

func get_cards_of_type(type: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in current_deck:
		if card.card_type == type:
			result.append(card)
	return result

func get_deck_size() -> int:
	return current_deck.size()
