extends Node

var _relics: Array[RelicData] = []
var _charge_states: Dictionary = {}

func _ready() -> void:
	_connect_signals()

func _connect_signals() -> void:
	EventBus.battle_started.connect(func(group): _on_event("battle_started", group))
	EventBus.battle_ended.connect(func(won): _on_event("battle_ended", won))
	EventBus.turn_started.connect(func(turn): _on_event("turn_started", turn))
	EventBus.first_turn_started.connect(func(turn): _on_event("first_turn_started", turn))
	EventBus.card_played.connect(func(card, target): _on_event("card_played", card, target))
	EventBus.card_drawn.connect(func(card): _on_event("card_drawn", card))
	EventBus.damage_dealt.connect(func(target, amount, dmg_type): _on_event("on_damage_dealt", target, amount, dmg_type))
	EventBus.player_hp_changed.connect(func(cur, maximum): _on_event("player_hp_changed", cur, maximum))
	EventBus.enemy_defeated.connect(func(enemy): _on_event("enemy_defeated", enemy))
	EventBus.turn_ended.connect(func(): _on_event("turn_ended"))
	EventBus.rest_site_entered.connect(func(): _on_event("rest_site"))

func _on_event(event_name: String, arg1 = null, arg2 = null, arg3 = null) -> void:
	var args := {"arg1": arg1, "arg2": arg2, "arg3": arg3}
	for relic in _relics:
		if relic.trigger_event != event_name:
			continue
		if not _consume_charge(relic):
			continue
		RelicEffectResolver.resolve(relic, args)

## 充能：max_charges 是**整局**的额度，不是每场战斗重置——「一次性遗物」就写 1。
## 扣在效果生效之前：额度用完了就不该再响，中途出错也不该白留一格。
## 不填（0）的是无限次，不进这本账。
func _consume_charge(relic: RelicData) -> bool:
	if relic.max_charges <= 0:
		return true
	var left: int = _charge_states.get(relic.relic_id, relic.max_charges)
	if left <= 0:
		return false
	_charge_states[relic.relic_id] = left - 1
	EventBus.relic_charges_changed.emit(relic.relic_id, left - 1)
	return true

## 还剩几次。0 表示「无限」或「已耗尽」，界面按 max_charges 分得清是哪种。
func get_charges(relic_id: String) -> int:
	return _charge_states.get(relic_id, 0)

func add_relic(data: RelicData) -> void:
	if has_relic(data.relic_id):
		return
	_relics.append(data)
	if data.max_charges > 0:
		_charge_states[data.relic_id] = data.max_charges
	EventBus.relic_obtained.emit(data)

func has_relic(relic_id: String) -> bool:
	for relic in _relics:
		if relic.relic_id == relic_id:
			return true
	return false

func get_relic_count() -> int:
	return _relics.size()

func clear_relics() -> void:
	_relics.clear()
	_charge_states.clear()

func get_all_relics() -> Array[RelicData]:
	return _relics
