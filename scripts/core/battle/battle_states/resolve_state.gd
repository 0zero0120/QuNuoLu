class_name ResolveState
extends State

func enter(data: Dictionary = {}) -> void:
	var bm: BattleManager = state_machine.get_parent()

	bm.player.on_turn_end()
	for enemy in bm.enemies:
		if enemy.is_alive:
			enemy.on_turn_end()

	bm.card_pile.discard_hand(bm.hand_container)
	# 只清玩家的格挡——玩家清在「自己回合开始」，整个敌人回合都挡得住，这是对的。
	# 敌人的清在敌人回合开始时（enemy_turn_state.enter），不在这里：清在这儿的话
	# 敌人刚攒的格挡下一瞬间就没了，永远挡不住玩家这一回合的攻击。
	bm.player.reset_block()

	EventBus.turn_ended.emit()

	if not bm.player.is_alive():
		print("[ResolveState] player dead -> End (defeat)")
		state_machine.transition_to("End", {"result": "defeat"})
		return

	var all_dead := true
	for enemy in bm.enemies:
		if enemy.is_alive:
			all_dead = false
			break
	print("[ResolveState] all_dead=%s, enemies=%d" % [all_dead, bm.enemies.size()])
	if all_dead and bm.enemies.size() > 0:
		print("[ResolveState] all enemies dead -> End (victory)")
		state_machine.transition_to("End", {"result": "victory"})
	else:
		state_machine.transition_to("PlayerTurn")
