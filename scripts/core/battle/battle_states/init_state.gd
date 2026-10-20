class_name InitState
extends State

func enter(data: Dictionary = {}) -> void:
	var bm: BattleManager = state_machine.get_parent()
	bm.turn_number = 0
	bm.player = bm.player_node

	var enemy_data_list: Array[EnemyData] = data.get("enemies", [] as Array[EnemyData])

	if enemy_data_list.is_empty():
		enemy_data_list = _roll_encounter()

	GameManager.mark_enemies_seen(enemy_data_list)

	# Spawn all enemies
	for edata in enemy_data_list:
		bm.spawn_enemy(edata)
	if enemy_data_list.size() > 0:
		EventBus.battle_started.emit(bm.enemies)

	state_machine.transition_to("PlayerTurn")

## 组一支进去打的队伍。精英和 BOSS 永远单只出场——一局里最硬的那只成群围上来没法打；
## 普通遭遇按楼层抽一队（见 _roll_size），群伤牌、指向牌和召唤/分裂都靠这个才有意义。
func _roll_encounter() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for i in _roll_size():
		var data := DataManager.get_enemy(_pick_enemy_id())
		if data == null:
			# 兜底敌人也得走一遍缩放，否则「一个 tier 都没标」时难度就静默失效了。
			data = _create_default_enemy()
		out.append(GameManager.scale_enemy_for_run(data))
	return out


## 这一场刷几只。楼层越深越可能成群，上限同时受 balance 和战斗场景的敌位上限约束。
func _roll_size() -> int:
	if GameManager.current_encounter_type != MapNodeData.NodeType.BATTLE:
		return 1
	var bal := DataManager.get_balance()
	var grow := bal.encounter_grow_every_floors if bal else 3
	var ceiling := bal.encounter_max_size if bal else BattleManager.MAX_ENEMY_SLOTS
	var by_floor := 1 + floori(float(GameManager.current_floor) / float(maxi(1, grow)))
	var upper := clampi(by_floor, 1, mini(ceiling, BattleManager.MAX_ENEMY_SLOTS))
	return GameManager.run_rng.randi_range(1, upper)


## 精英和BOSS都从对应的 tier 池里随机挑，加新敌人时只要标好 tier 就能出场。
## 一个都没标时返回空串，走下面的默认敌人兜底。
func _pick_enemy_id() -> String:
	match GameManager.current_encounter_type:
		MapNodeData.NodeType.BOSS:
			return _pick_by_tier(EnemyData.EnemyTier.BOSS)
		MapNodeData.NodeType.ELITE:
			return _pick_by_tier(EnemyData.EnemyTier.ELITE)
	return _pick_normal_enemy_id()


## 精英和 BOSS 都从对应的 tier 池里随机挑，两档都按章分池：min_floor 当「这只属于哪一章」用，
## 于是三章各有自己的一批，不会三章都撞见同一只。
##
## 这里**不能**照搬 _pick_normal_enemy_id 那句「min_floor <= 当前层」：那是「最早何时出场」，
## 池子只会越往后越大——第 2 章的 33 层会连第 1 章那批一起算进来，第 3 章的 50 层全部出场，
## 三章就又挑到重复的了。按区间认才切得开。
##
## 池子被楼层挡空时（min_floor 填漏了）退回不过滤的整个 tier 池——不然会静默换成兜底敌人，
## 「数据没填」和「难度没标」这两种错就分不出来了，这条和 _pick_normal_enemy_id 一样。
func _pick_by_tier(tier: EnemyData.EnemyTier) -> String:
	var pool: Array[String] = []
	var all_of_tier: Array[String] = []
	for enemy: EnemyData in DataManager.enemy_database.values():
		# pool_hidden 是变身第二形态、召唤物这类中间态，它们只由别的怪带出来，不进任何随机池。
		if enemy.tier != tier or enemy.pool_hidden:
			continue
		all_of_tier.append(enemy.enemy_id)
		if _min_floor_is_this_chapter(enemy.min_floor):
			pool.append(enemy.enemy_id)
	if pool.is_empty():
		pool = all_of_tier
	return str(GameManager.rand_pick(pool)) if not pool.is_empty() else ""


## 这条 min_floor 是不是落在当前章的层号区间里。第 1 章从 1 层起算——
## 0 层是起点层，min_floor 的下限本来就是 1，没有敌人标 0。
func _min_floor_is_this_chapter(min_floor: int) -> bool:
	var first := MapConfig.first_floor_of_chapter(GameManager.current_chapter)
	return min_floor >= maxi(1, first) and min_floor <= first + MapConfig.FLOORS_PER_CHAPTER - 1


## 普通敌人的楼层递进走 EnemyData.min_floor：第一层只出蛊雕，往上逐步解锁更强的。
## 全被楼层挡掉时（min_floor 填漏了）退回不过滤的整个普通池——不然会静默换成兜底敌人，
## 「难度没标」和「数据没填」这两种错就分不出来了。
##
## 合格池里不是均匀抽的，而是拿 min_floor 当权重。min_floor 是「这怪最早该在第几层出现」，
## 拿它当权重正好等于「越深的怪越容易在深处遇到」：不加权的话第 16 层有 18 只合格，
## 第一层的蛊雕仍然占 1/18，深层的血量堆得再高也挡不住开头的小怪反复冒出来。
func _pick_normal_enemy_id() -> String:
	var floor := GameManager.current_floor
	var usable: Array[String] = []
	var weights: Array[float] = []
	var all_normal: Array[String] = []
	for enemy: EnemyData in DataManager.enemy_database.values():
		if enemy.tier != EnemyData.EnemyTier.NORMAL or enemy.pool_hidden:
			continue
		all_normal.append(enemy.enemy_id)
		if enemy.min_floor <= floor:
			usable.append(enemy.enemy_id)
			weights.append(float(enemy.min_floor))
	if usable.is_empty():
		usable = all_normal
		weights.clear()
		for id in all_normal:
			var data := DataManager.get_enemy(id)
			weights.append(float(data.min_floor) if data else 0.0)
	return str(GameManager.rand_pick_weighted(usable, weights)) if not usable.is_empty() else ""


func _create_default_enemy() -> EnemyData:
	var data := EnemyData.new()
	data.enemy_id = "default"
	data.display_name = "敌人"
	data.max_hp = 30
	data.gold_reward_min = 5
	data.gold_reward_max = 15
	var intent := IntentResource.new()
	intent.intent_type = IntentResource.IntentType.ATTACK
	intent.value = 6
	intent.description_template = "造成 {value} 点伤害。"
	data.normal_intent_pattern.append(intent)
	return data
