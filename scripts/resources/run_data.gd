class_name RunData
extends Resource

@export var character_id: String = ""
@export var current_hp: int = 0
@export var max_hp: int = 0
@export var gold: int = 0
## 全局层数（第 3 章能到 50 层），和 chapter 一起存。
@export var floor: int = 0
## 打到第几章，1..GameManager.CHAPTER_COUNT。不能拿 floor 现推：测试和读档都会单独拨 floor。
@export var chapter: int = 1
@export var strength: int = 0
@export var dexterity: int = 0
@export var base_energy: int = 3
@export var deck_card_ids: Array[String] = []
@export var deck_card_upgraded: Array[bool] = []
@export var relic_ids: Array[String] = []
@export var potion_ids: Array[String] = []
@export var visited_node_ids: Array[String] = []
## 本局已见过的事件 id。跨章累计，所以它和 visited_node_ids 一样要进存档：
## 不存的话中途退出再进，同一个事件会重新冒出来。
@export var seen_event_ids: Array[String] = []

## 局内计数：start_new_run 和 load_run 都要能续上，所以不能只挂在 GameManager 上。
@export var enemies_killed: int = 0
@export var bosses_killed: int = 0
@export var elapsed_seconds: int = 0
## 本局已经记进 meta 的秒数。和 elapsed_seconds 一起存，读档时两个都要续上：
## 只续显示值的话，秒表下一帧就归零；只续显示值不续这个的话，后面那段 flush 会把
## 已经算过的时长往统计里再加一遍。负数表示存档里没这一项（改动之前的老档）。
@export var unflushed_seconds: int = -1
@export var ascension: int = 1
@export var run_seed: int = 0
## 随机数发生器的当前状态。存成字符串：它是 64 位整数，而 JSON 的数字是浮点，直接存会丢精度，
## 读档后整条随机流就跑偏了。中途退出再进要能抽出和存盘前一样的牌，靠的就是它。
@export var rng_state: String = ""

func populate() -> void:
	var gm := GameManager
	var pd := gm.player_data
	character_id = pd.character_id
	current_hp = pd.current_hp
	max_hp = pd.max_hp
	gold = pd.gold
	floor = gm.current_floor
	chapter = gm.current_chapter
	strength = pd.strength
	dexterity = pd.dexterity
	base_energy = pd.base_energy
	deck_card_ids.clear()
	deck_card_upgraded.clear()
	for card in gm.current_deck:
		deck_card_ids.append(card.card_id)
		deck_card_upgraded.append(card.upgraded)
	relic_ids.clear()
	for relic in gm.current_relics:
		relic_ids.append(relic.relic_id)
	potion_ids.clear()
	var slots := gm.get_potion_slots()
	for potion in slots:
		if potion:
			potion_ids.append(potion.potion_id)
		else:
			potion_ids.append("")
	visited_node_ids.clear()
	for node_id in gm.visited_node_ids:
		visited_node_ids.append(node_id)
	seen_event_ids.clear()
	for event_id in gm.seen_event_ids:
		seen_event_ids.append(event_id)
	enemies_killed = gm.run_enemies_killed
	bosses_killed = gm.run_bosses_killed
	elapsed_seconds = gm.run_elapsed_seconds
	unflushed_seconds = gm.get_unflushed_seconds()
	ascension = gm.run_ascension
	run_seed = gm.run_seed
	rng_state = str(gm.run_rng.state)

func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"gold": gold,
		"floor": floor,
		"chapter": chapter,
		"strength": strength,
		"dexterity": dexterity,
		"base_energy": base_energy,
		"deck_card_ids": deck_card_ids,
		"deck_card_upgraded": deck_card_upgraded,
		"relic_ids": relic_ids,
		"potion_ids": potion_ids,
		"visited_node_ids": visited_node_ids,
		"seen_event_ids": seen_event_ids,
		"enemies_killed": enemies_killed,
		"bosses_killed": bosses_killed,
		"elapsed_seconds": elapsed_seconds,
		"unflushed_seconds": unflushed_seconds,
		"ascension": ascension,
		"run_seed": run_seed,
		"rng_state": rng_state,
	}

func from_dict(data: Dictionary) -> void:
	character_id = str(data.get("character_id", ""))
	current_hp = int(data.get("current_hp", 0))
	max_hp = int(data.get("max_hp", 0))
	gold = int(data.get("gold", 0))
	floor = int(data.get("floor", 0))
	# 三章之前的老存档没有这一项。它们最高只走到 16 层，默认成第 1 章正好对得上，不必写迁移。
	chapter = int(data.get("chapter", 1))
	strength = int(data.get("strength", 0))
	dexterity = int(data.get("dexterity", 0))
	base_energy = int(data.get("base_energy", 3))
	deck_card_ids = _string_array(data.get("deck_card_ids", []))
	deck_card_upgraded = _bool_array(data.get("deck_card_upgraded", []))
	relic_ids = _string_array(data.get("relic_ids", []))
	potion_ids = _string_array(data.get("potion_ids", []))
	visited_node_ids = _string_array(data.get("visited_node_ids", []))
	# 加这个字段之前的存档里没有这一项，缺了就当「一个都没见过」——不必写迁移。
	seen_event_ids = _string_array(data.get("seen_event_ids", []))
	enemies_killed = int(data.get("enemies_killed", 0))
	bosses_killed = int(data.get("bosses_killed", 0))
	elapsed_seconds = int(data.get("elapsed_seconds", 0))
	unflushed_seconds = int(data.get("unflushed_seconds", -1))
	ascension = int(data.get("ascension", 1))
	run_seed = int(data.get("run_seed", 0))
	rng_state = str(data.get("rng_state", ""))

func _string_array(raw: Variant) -> Array[String]:
	var arr: Array[String] = []
	if raw is Array:
		for v in raw:
			arr.append(str(v))
	return arr

func _bool_array(raw: Variant) -> Array[bool]:
	var arr: Array[bool] = []
	if raw is Array:
		for v in raw:
			arr.append(bool(v))
	return arr

func apply_to_player() -> void:
	var gm := GameManager
	var pd := gm.player_data
	pd.current_hp = current_hp
	pd.max_hp = max_hp
	pd.gold = gold
	gm.current_floor = floor
	gm.current_chapter = chapter
	# current_gold 也得还原：战斗 HUD 读的是它，add_gold/spend_gold 也以它为基数，
	# 漏了这一步读档后打一场会把金币直接覆盖成该场收益。
	gm.current_gold = gold
	pd.strength = strength
	pd.dexterity = dexterity
	pd.base_energy = base_energy
	gm.current_deck.clear()
	for i in range(deck_card_ids.size()):
		var base_card := DataManager.get_card(deck_card_ids[i])
		if base_card:
			var card := base_card.duplicate()
			# 走 upgrade() 而不是直接写 upgraded 标志：它还会补上名字的「+」和
			# upgrade_bonus_cost 的减费，只写标志位会让读档后的卡面少个「+」、费用偏高。
			# 升级表比卡表短（很老的档 / 手改过的档）时按未升级处理，别越界把整次读档中断。
			var upgraded: bool = deck_card_upgraded[i] if i < deck_card_upgraded.size() else false
			if upgraded:
				card.upgrade()
			gm.add_card_to_deck(card)
		else:
			push_warning("[RunData] 存档卡牌 %s 不在卡库里，已跳过" % deck_card_ids[i])
	gm.current_relics.clear()
	RelicManager.clear_relics()
	for relic_id in relic_ids:
		var relic := DataManager.get_relic(relic_id)
		if relic:
			gm.add_relic(relic)
		else:
			push_warning("[RunData] 存档遗物 %s 不在遗物库里，已跳过" % relic_id)
	gm.visited_node_ids = visited_node_ids.duplicate()
	gm.seen_event_ids = seen_event_ids.duplicate()
	gm.run_enemies_killed = enemies_killed
	gm.run_bosses_killed = bosses_killed
	gm.restore_run_timer(elapsed_seconds, unflushed_seconds)
	gm.run_ascension = ascension
	gm.run_seed = run_seed
	# 随机流接着存盘那一刻往下走。没有这一项（更早的存档）就退回按种子重来，
	# 至少是确定的一串，不是随机的。
	if rng_state.is_empty():
		gm.run_rng.seed = run_seed
	else:
		gm.run_rng.state = int(rng_state)
	gm.clear_map_state()
	gm._ensure_potion_manager()
	gm.potion_manager = PotionManager.new()
	for potion_id in potion_ids:
		if not potion_id.is_empty():
			var potion := DataManager.get_potion(potion_id)
			if potion:
				gm.add_potion(potion)
			else:
				push_warning("[RunData] 存档药水 %s 不在药水库里，已跳过" % potion_id)
