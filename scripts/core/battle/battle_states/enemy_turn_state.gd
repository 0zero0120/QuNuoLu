class_name EnemyTurnState
extends State

const PROCESS_TIMEOUT: float = 5.0

func enter(_data: Dictionary = {}) -> void:
	var bm: BattleManager = state_machine.get_parent()
	if bm.end_turn_button:
		bm.end_turn_button.disabled = true
	bm.set_potions_active(false)
	# 格挡在自己回合开始时清（和玩家同一套规则）。清在这儿，敌人上一轮攒的格挡才能
	# 撑过整个玩家回合、真正替它挡下玩家的攻击，头顶那行 🛡 也才看得见。
	for enemy in bm.enemies:
		if enemy.is_alive:
			enemy.reset_block()
	_process_enemies(bm)

func _process_enemies(bm: BattleManager) -> void:
	print("[EnemyTurn] processing %d enemies" % bm.enemies.size())
	var t0 := Time.get_ticks_msec()

	# 先照这一刻的名单抄一份再遍历：中途被召唤/分裂出来的小怪这一回合不该动。
	# 直接遍历 bm.enemies 的话，GDScript 的 for 每轮都会重看数组长度，
	# 新来的会当场插进来打一拳——「刚上场就出手」既不讲理，头顶也没有预告过。
	var actors: Array[EnemyBase] = []
	actors.assign(bm.enemies)

	for enemy in actors:
		if not enemy.is_alive:
			continue
		# 执行玩家回合开始时预告的那一招。只有没预告过（老存档、中途生成的敌人）才现算兜底。
		var intent := enemy.current_intent
		if intent == null:
			intent = enemy.get_next_intent(bm.player)
		if intent:
			# 协程：攻击类要演完「出手」才轮到伤害落地，这里必须等它。
			await enemy.execute_intent(intent, bm.player)
		else:
			print("[EnemyTurn] enemy %s has no intent!" % (enemy.enemy_data.display_name if enemy.enemy_data else "???"))
		await bm.get_tree().create_timer(SettingsManager.enemy_step_delay()).timeout

		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		if elapsed > PROCESS_TIMEOUT:
			print("[EnemyTurn] TIMEOUT after %.1fs, forcing Resolve" % elapsed)
			break

	print("[EnemyTurn] done, transitioning to Resolve")
	state_machine.transition_to("Resolve")

func exit() -> void:
	var bm: BattleManager = state_machine.get_parent()
	if bm.end_turn_button:
		bm.end_turn_button.disabled = false
	bm.set_potions_active(true)
