class_name RelicEffectResolver
extends RefCounted

static func resolve(relic: RelicData, event_data: Dictionary) -> void:
	var bm := _get_battle_manager()
	var args := event_data

	# card_played 是唯一一种要挑牌看的事件：遗物只想认某一类牌时，把牌型写进 effect_target
	# （attack / skill / ability），空着或写 any 就是什么牌都认。放在 match 前面统一判，
	# 这样「打出攻击牌后加格挡」「打出技能牌后抽一张」这类效果都能直接复用现成的 effect_type。
	if relic.trigger_event == "card_played" and not _card_matches(relic, args.get("arg1")):
		return

	match relic.effect_type:
		"heal_on_event":
			if bm and bm.player:
				bm.player.heal(int(relic.effect_value))
			else:
				var pd := GameManager.player_data
				pd.current_hp = mini(pd.current_hp + int(relic.effect_value), pd.max_hp)
				EventBus.player_hp_changed.emit(pd.current_hp, pd.max_hp)
		"gain_energy":
			# 必须走 add_permanent()：每个玩家回合开头 energy_system.reset() 会把
			# current_energy 直接重写成 max_energy + permanent_energy，add() 加的那一点
			# 一进玩家回合就被抹掉，玩家永远花不到。
			if bm and bm.energy_system:
				bm.energy_system.add_permanent(int(relic.effect_value))
		"gain_energy_temp":
			# 和 gain_energy 是两码事：这条是「本回合多一点」，下回合开头就被 reset() 抹平。
			# 挂在 turn_started 上时必须用这条——另一条是永久的，每回合触发会一路叠上去。
			if bm and bm.energy_system:
				bm.energy_system.add(int(relic.effect_value))
		"gain_block":
			if bm and bm.player:
				bm.player.add_block(int(relic.effect_value))
		"draw_cards":
			if bm:
				var scene := BattleManager.instantiate_card_scene()
				bm.card_pile.draw_to_hand(int(relic.effect_value), bm.hand_container, scene)
		"gain_gold":
			GameManager.add_gold(int(relic.effect_value))
		"gain_strength":
			if bm and bm.player:
				bm.player.add_status_effect(StatusEffect.Type.STRENGTH, int(relic.effect_value))
		"gain_dexterity":
			if bm and bm.player:
				bm.player.add_status_effect(StatusEffect.Type.DEXTERITY, int(relic.effect_value))
		"deal_aoe":
			if bm:
				for enemy in bm.get_alive_enemies():
					enemy.take_damage(int(relic.effect_value))
				bm._check_battle_end()
		# 和 deal_aoe 一样打全体，区别是既不上伤害也不判胜负：只叠中毒层数，
		# 真正的扣血发生在敌人自己回合开始（见 StatusEffect.DOT_TYPES）。
		"poison_all":
			if bm:
				for enemy in bm.get_alive_enemies():
					enemy.add_status_effect(StatusEffect.Type.POISON, int(relic.effect_value))
		"heal_percent":
			if bm and bm.player:
				var heal := int(float(bm.player.max_hp) * relic.effect_value)
				bm.player.heal(heal)

## 打出的那张牌算不算数。牌型用 CardData 自己的枚举名比对，写错了（比如 "atack"）
## 就是永远不触发——所以 relic 的 effect_target 取值也在测试里对着枚举过一遍。
static func _card_matches(relic: RelicData, card: Variant) -> bool:
	var filter := relic.effect_target.strip_edges().to_lower()
	if filter.is_empty() or filter == "any":
		return true
	if not (card is CardData):
		return false
	var type_name := (card as CardData).type_to_string()
	return type_name.to_lower() == filter


## 战斗管理器一律从 GameManager 取。
## 从前读 tree.current_scene，但主菜单/奖励页/无头测试下 current_scene 要么不是战斗、
## 要么干脆是空的，那时遗物效果会静默不生效——断言看着还是绿的。
static func _get_battle_manager() -> BattleManager:
	return GameManager.get_active_battle()
