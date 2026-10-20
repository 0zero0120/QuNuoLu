extends Node

var card_database: Dictionary = {}
var enemy_database: Dictionary = {}
var relic_database: Dictionary = {}
var potion_database: Dictionary = {}
var character_database: Dictionary = {}
var achievement_database: Dictionary = {}
var event_database: Dictionary = {}
var balance: BalanceConfig

func _ready() -> void:
	_load_all_databases()

func _load_all_databases() -> void:
	_load_resources("res://resources/cards/", card_database, "card_id")
	_load_resources("res://resources/enemies/", enemy_database, "enemy_id")
	_load_resources("res://resources/relics/", relic_database, "relic_id")
	_load_resources("res://resources/characters/", character_database, "character_id")
	_load_resources("res://resources/potions/", potion_database, "potion_id")
	_load_resources("res://resources/achievements/", achievement_database, "achievement_id")
	_load_resources("res://resources/events/", event_database, "event_id")
	balance = ResourceLoader.load("res://resources/balance.tres") as BalanceConfig
	if balance == null:
		balance = BalanceConfig.new()

func get_balance() -> BalanceConfig:
	return balance


## 界面上要摆角色（选人页、统计页、战报页）一律走这里，别直接遍历 character_database——
## 那是个 Dictionary，次序是按**文件名**排序加载出来的，跟设计次序无关。
## 次序的唯一来源是 PlayerData.order_index；同号（比如新加的角色忘了填）按 id 兜底，
## 免得同号的两个角色每次运行先后不定。
func characters_in_order() -> Array[PlayerData]:
	var list: Array[PlayerData] = []
	for character: PlayerData in character_database.values():
		list.append(character)
	list.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		if a.order_index != b.order_index:
			return a.order_index < b.order_index
		return a.character_id < b.character_id)
	return list

## 加载顺序会影响 card_database.values() / enemy_database.values() 的遍历顺序，而那几处
## 随机抽取是按遍历顺序下标的。dir.get_next() 的顺序跟文件系统有关（同机器稳定、换台机器未必），
## 所以先收文件名排序再加载——否则同一个种子换台机器会抽出不同的东西。
##
## 导出版里 Godot 把文本资源转成二进制，目录列出来的名字带 `.remap` 后缀（strike.tres.remap），
## 直接 ends_with(".tres") 会一个都不中、所有数据表全空。必须先剥掉 .remap 再判后缀；
## ResourceLoader.load() 自己能认 remap，用剥好的原名去 load 即可。
func _load_resources(dir_path: String, target: Dictionary, id_prop: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			var raw := file_name.trim_suffix(".remap")
			if raw.ends_with(".tres"):
				file_names.append(raw)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()
	for name in file_names:
		var res: Resource = ResourceLoader.load(dir_path + name)
		if res and id_prop in res:
			target[res.get(id_prop)] = res

func get_card(card_id: String) -> CardData:
	if card_database.has(card_id):
		return card_database[card_id]
	return null

func get_enemy(enemy_id: String) -> EnemyData:
	if enemy_database.has(enemy_id):
		return enemy_database[enemy_id]
	return null

func get_relic(relic_id: String) -> RelicData:
	if relic_database.has(relic_id):
		return relic_database[relic_id]
	return null

func get_potion(potion_id: String) -> PotionData:
	if potion_database.has(potion_id):
		return potion_database[potion_id]
	return null

func get_achievement(achievement_id: String) -> Achievement:
	if achievement_database.has(achievement_id):
		return achievement_database[achievement_id]
	return null

func get_character(character_id: String) -> PlayerData:
	if character_database.has(character_id):
		return character_database[character_id]
	return null

func get_event(event_id: String) -> EventData:
	if event_database.has(event_id):
		return event_database[event_id]
	return null

func is_card_unlocked(card: CardData) -> bool:
	if card.unlock_cost <= 0:
		return true
	var mp := GameManager.meta_progress
	if mp == null:
		return true
	return card.card_id in mp.unlocked_card_ids

## 这张牌是不是当前角色抽得到的。character_id 空着的是通用牌（打击、防御），谁都能抽。
## 还没开局（player_data 没角色）时一律放行——编辑器和自检脚本会不经对局直接调抽卡函数，
## 那里没有「当前角色」可言，卡住只会让池子凭空变空。
func is_card_for_current_character(card: CardData) -> bool:
	if card.character_id.is_empty():
		return true
	var pd := GameManager.player_data
	if pd == null or pd.character_id.is_empty():
		return true
	return card.character_id == pd.character_id

## 会自己出场、图鉴里也有一席之地的敌人有多少只。变身的第二形态（pool_hidden）不算：
## 它只在别人血空的那一刻顶替上来，永远不会被单独抽出来。拿整个敌人库当分母的话，
## 「遇见过的敌人」永远差一只、「集齐所有敌人」这个成就永远拿不到。
func codex_enemy_count() -> int:
	var count := 0
	for enemy: EnemyData in enemy_database.values():
		if not enemy.pool_hidden:
			count += 1
	return count


func get_random_card(rarity: int = -1) -> CardData:
	var pool: Array[CardData] = []
	for card: CardData in card_database.values():
		if not is_card_unlocked(card) or not is_card_for_current_character(card):
			continue
		# 诅咒（不可打出）不是能抽到的东西，只能由敌人塞进战斗牌堆。
		if not card.is_obtainable():
			continue
		if rarity == -1 or card.rarity == rarity:
			pool.append(card)
	if pool.is_empty():
		return null
	return GameManager.rand_pick(pool)

func get_weighted_random_cards(count: int, weights: Dictionary) -> Array[CardData]:
	var pool: Array[CardData] = []
	for card: CardData in card_database.values():
		if not is_card_unlocked(card) or not is_card_for_current_character(card):
			continue
		if not card.is_obtainable():
			continue
		var r_key: String = CardData.rarity_to_string(card.rarity)
		if weights.has(r_key):
			pool.append(card)
	var result: Array[CardData] = []
	for _i in range(count):
		if pool.is_empty():
			break
		var total_weight: float = 0.0
		for card: CardData in pool:
			var r_key: String = CardData.rarity_to_string(card.rarity)
			total_weight += weights.get(r_key, 10)
		var roll := GameManager.run_rng.randf() * total_weight
		var cumulative: float = 0.0
		var selected: CardData = pool[0]
		for card: CardData in pool:
			var r_key: String = CardData.rarity_to_string(card.rarity)
			cumulative += weights.get(r_key, 10)
			if roll <= cumulative:
				selected = card
				break
		result.append(selected)
		pool.erase(selected)
	return result

## exclude_rarities 用来把某些档整体挡在池外——精英掉落不该发出角色初始遗物、
## 也不该发出留给 Boss 三选一的 BOSS 档。rarity 传具体值时它没意义，留空即可。
func get_random_relic(rarity: int = -1, exclude_ids: Array[String] = [],
		exclude_rarities: Array[int] = []) -> RelicData:
	var pool: Array[RelicData] = []
	for relic: RelicData in relic_database.values():
		if relic.relic_id in exclude_ids:
			continue
		if int(relic.rarity) in exclude_rarities:
			continue
		if rarity == -1 or relic.rarity == rarity:
			pool.append(relic)
	if pool.is_empty():
		return null
	return GameManager.rand_pick(pool)

## 「打怪掉落 / 事件奖励」能发出的遗物：排掉已经有的，再挡掉 STARTER（角色自带那件）
## 和 BOSS（留给 Boss 三选一的独占档）。精英掉落和事件奖励都走这里——各写一份的话，
## 改一处忘一处就会让 Boss 档提前从别处漏出去。
func get_random_obtainable_relic() -> RelicData:
	var exclude_ids: Array[String] = []
	for owned: RelicData in GameManager.current_relics:
		exclude_ids.append(owned.relic_id)
	var exclude_rarities: Array[int] = [
		RelicData.RelicRarity.STARTER, RelicData.RelicRarity.BOSS,
	]
	return get_random_relic(-1, exclude_ids, exclude_rarities)

func get_random_potion(rarity: int = -1) -> PotionData:
	var pool: Array[PotionData] = []
	for potion: PotionData in potion_database.values():
		if rarity == -1 or potion.rarity == rarity:
			pool.append(potion)
	if pool.is_empty():
		return null
	return GameManager.rand_pick(pool)
