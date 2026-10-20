class_name EndState
extends State

var _resolved: bool = false

func enter(data: Dictionary = {}) -> void:
	if _resolved:
		return
	if GameManager.current_screen == GameManager.GameScreen.REWARD or GameManager.current_screen == GameManager.GameScreen.GAME_OVER:
		print("[EndState] already on end screen, skipping")
		return

	var bm: BattleManager = state_machine.get_parent() as BattleManager
	if not bm:
		push_error("[EndState] state_machine.get_parent() is not a BattleManager!")
		return

	var result: String = data.get("result", "defeat")
	print("[EndState] enter: result=%s" % result)

	# 这里故意不动 resume_screen：奖励页还没挂出来之前它还是 BATTLE，
	# 此时退出存档仍是开打前那份，读档重打这场战斗。
	# 收尾交给下面两处——奖励页显示时改成 REWARD，通关/死亡由 finish_run() 清回 MAP。
	GameManager.restore_deck_snapshot()

	if result == "victory":
		_resolved = true
		var gold := 0
		for enemy in bm.enemies:
			if enemy and enemy.enemy_data:
				gold += GameManager.run_rng.randi_range(
					enemy.enemy_data.gold_reward_min, enemy.enemy_data.gold_reward_max)
		GameManager.add_gold(gold)
		GameManager.add_souls(_sum_souls(bm))
		if bm.player:
			bm.player.save_state_to_player_data(GameManager.player_data)
		EventBus.battle_ended.emit(true)

		var dropped_potion: PotionData = null
		var bal := DataManager.get_balance()
		if GameManager.run_rng.randf() < (bal.potion_drop_chance if bal else 0.4):
			dropped_potion = DataManager.get_random_potion()
			if dropped_potion:
				GameManager.add_potion(dropped_potion)

		if GameManager.current_encounter_type == MapNodeData.NodeType.BOSS:
			print("[EndState] BOSS victory - gold=%d, potion=%s" % [gold, dropped_potion.potion_name if dropped_potion else "none"])
			_show_relic_pick_overlay(bm)
			return

		GameManager.pending_reward = {
			"gold_earned": gold,
			"potion_drop": dropped_potion
		}

		print("[EndState] victory - gold=%d, potion=%s" % [gold, dropped_potion.potion_name if dropped_potion else "none"])
		_show_reward_overlay(bm)
	else:
		_resolved = true
		EventBus.battle_ended.emit(false)
		GameManager.add_souls(GameManager.current_floor * GameManager.DEFEAT_SOUL_PER_FLOOR)
		GameManager.finish_run(false)
		print("[EndState] defeat")
		GameManager.change_screen(GameManager.GameScreen.GAME_OVER)

func _show_reward_overlay(bm: BattleManager) -> void:
	var scene := load("res://scenes/ui/card_reward_screen.tscn") as PackedScene
	if scene == null:
		push_error("[EndState] Failed to load card_reward_screen.tscn")
		GameManager.finish_node()
		return

	# 奖励页也是「走到一半的界面」：先把它落盘成落点，再挂上去。
	# 奖励内容由 card_reward_screen 的 ensure_node_state 紧接着写进同一份存档。
	GameManager.resume_screen = GameManager.GameScreen.REWARD
	GameManager.save_run()

	var reward_overlay: Control = scene.instantiate()
	reward_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	bm.get_parent().add_child(reward_overlay)
	print("[EndState] CardReward overlay added to battle scene")

## Boss 遗物三选一。和收尾的关系：末章的 Boss 收尾会走 finish_run()——记历史、把进阶难度加一、
## 清掉这个存档槽，所以必须等遗物选完再收，否则遗物入包之前那一局就已经结算完了，
## evaluate_achievements() 也看不到它。前面几章的 Boss 收完只是翻下一章（见 relic_picker_screen）。
## 落点存 RELIC_PICK 而不是像奖励页那样只活在内存里：中途退出再继续时，
## change_screen(RELIC_PICK) 会单独把同一个界面加载起来，不会静默吞掉遗物。
func _show_relic_pick_overlay(bm: BattleManager) -> void:
	var scene := load("res://scenes/ui/relic_picker_screen.tscn") as PackedScene
	if scene == null:
		# 这一屏加载不出来时的兜底。别一律按通关收——第 1 章的 Boss 不该把整局结算掉。
		push_error("[EndState] Failed to load relic_picker_screen.tscn")
		if GameManager.is_final_chapter():
			GameManager.finish_run(true)
			GameManager.change_screen(GameManager.GameScreen.VICTORY)
		else:
			GameManager.advance_chapter()
		return

	GameManager.resume_screen = GameManager.GameScreen.RELIC_PICK
	GameManager.save_run()

	var overlay: Control = scene.instantiate()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	bm.get_parent().add_child(overlay)
	print("[EndState] RelicPicker overlay added to battle scene")


func _sum_souls(bm: BattleManager) -> int:
	var souls := 0
	for enemy in bm.enemies:
		if enemy and enemy.enemy_data:
			souls += enemy.enemy_data.soul_reward
	return souls
