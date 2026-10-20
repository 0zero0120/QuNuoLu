class_name MetaProgress
extends Resource

@export var highest_floor_cleared: int = 0
## 已解锁到的最高进阶难度（账号全局共用，三档共享这一个值）。
@export var ascension_level: int = 1
## 上一次实际开新局时选用的难度，给角色详情页做默认值。跟解锁进度一样是全局一份。
@export var last_ascension_choice: int = 1
## 四个角色默认全开，界面不做解锁过滤（character_select 直接遍历 database 全列出）。
## 留着这个字段是为了以后要改成逐个解锁时不用再动存档结构。
@export var unlocked_character_ids: Array[String] = ["jianke", "nuoshi", "gushi", "wuseng"]
@export var unlocked_card_ids: Array[String] = []
@export var tutorial_seen: bool = false
@export var souls: int = 0
@export var permanent_upgrades: Dictionary = {"max_hp": 0, "gold": 0, "strength": 0}

## 百科大全的「遇见过」记录：只增不减，跨存档累积。
@export var seen_card_ids: Array[String] = []
@export var obtained_relic_ids: Array[String] = []
@export var found_potion_ids: Array[String] = []
@export var seen_enemy_ids: Array[String] = []

## 统计内容用的战绩，按角色 id 分开存：{character_id: {计数器...}}。0 层的键没有计数器的就不要。
@export var stats: Dictionary = {}
@export var unlocked_achievement_ids: Array[String] = []

## 单个角色的计数器初值。fastest_win_seconds 用 -1 表示「还没赢过」。
## floors_climbed 是累计，best_floor 是最高——后者要在 add_stat 之外单独取最大。
const STAT_DEFAULTS := {
	"runs": 0,
	"wins": 0,
	"deaths": 0,
	"floors_climbed": 0,
	"best_floor": 0,
	"enemies_killed": 0,
	"bosses_killed": 0,
	"play_seconds": 0,
	"fastest_win_seconds": -1,
}

func to_dict() -> Dictionary:
	return {
		"highest_floor_cleared": highest_floor_cleared,
		"ascension_level": ascension_level,
		"last_ascension_choice": last_ascension_choice,
		"unlocked_character_ids": unlocked_character_ids,
		"unlocked_card_ids": unlocked_card_ids,
		"tutorial_seen": tutorial_seen,
		"souls": souls,
		"permanent_upgrades": permanent_upgrades,
		"seen_card_ids": seen_card_ids,
		"obtained_relic_ids": obtained_relic_ids,
		"found_potion_ids": found_potion_ids,
		"seen_enemy_ids": seen_enemy_ids,
		"stats": stats,
		"unlocked_achievement_ids": unlocked_achievement_ids,
	}

func from_dict(data: Dictionary) -> void:
	highest_floor_cleared = int(data.get("highest_floor_cleared", 0))
	ascension_level = int(data.get("ascension_level", 1))
	last_ascension_choice = int(data.get("last_ascension_choice", 1))
	unlocked_character_ids = _string_array(data.get("unlocked_character_ids",
			["jianke", "nuoshi", "gushi", "wuseng"]))
	unlocked_card_ids = _string_array(data.get("unlocked_card_ids", []))
	tutorial_seen = bool(data.get("tutorial_seen", false))
	souls = int(data.get("souls", 0))
	var upg: Variant = data.get("permanent_upgrades", null)
	if typeof(upg) != TYPE_DICTIONARY:
		upg = {"max_hp": 0, "gold": 0, "strength": 0}
	permanent_upgrades = _int_dict(upg)
	seen_card_ids = _string_array(data.get("seen_card_ids", []))
	obtained_relic_ids = _string_array(data.get("obtained_relic_ids", []))
	found_potion_ids = _string_array(data.get("found_potion_ids", []))
	seen_enemy_ids = _string_array(data.get("seen_enemy_ids", []))
	stats = _normalize_stats(data.get("stats", {}))
	unlocked_achievement_ids = _string_array(data.get("unlocked_achievement_ids", []))

func get_upgrade_rank(key: String) -> int:
	return int(permanent_upgrades.get(key, 0))


# --- 遇见记录 ---

func mark_seen_card(card_id: String) -> bool:
	return _mark(seen_card_ids, card_id)

func mark_obtained_relic(relic_id: String) -> bool:
	return _mark(obtained_relic_ids, relic_id)

func mark_found_potion(potion_id: String) -> bool:
	return _mark(found_potion_ids, potion_id)

func mark_seen_enemy(enemy_id: String) -> bool:
	return _mark(seen_enemy_ids, enemy_id)

func has_seen_card(card_id: String) -> bool:
	return card_id in seen_card_ids

func has_obtained_relic(relic_id: String) -> bool:
	return relic_id in obtained_relic_ids

func has_found_potion(potion_id: String) -> bool:
	return potion_id in found_potion_ids

func has_seen_enemy(enemy_id: String) -> bool:
	return enemy_id in seen_enemy_ids

func mark_achievement(achievement_id: String) -> bool:
	return _mark(unlocked_achievement_ids, achievement_id)

func has_achievement(achievement_id: String) -> bool:
	return achievement_id in unlocked_achievement_ids


# --- 战绩统计 ---

## 取某个角色的计数器，不存在就地建一份。返回的是同一份字典，可直接改。
## JSON 回来的值是无类型的，读的时候一律过 int()。
func stats_for(character_id: String) -> Dictionary:
	var entry: Variant = stats.get(character_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		entry = STAT_DEFAULTS.duplicate()
		stats[character_id] = entry
	return entry

func stat_int(character_id: String, key: String) -> int:
	return int(stats_for(character_id).get(key, STAT_DEFAULTS.get(key, 0)))

func add_stat(character_id: String, key: String, amount: int) -> void:
	var entry := stats_for(character_id)
	# 外面这层 int() 是防复发：老档里读回来的计数器是浮点，直接加会把整个值变成浮点（0.0）。
	entry[key] = int(int(entry.get(key, STAT_DEFAULTS.get(key, 0))) + amount)

## 最高层数取最大而不是累加，跟 record_win_time 一样单独走。
func record_best_floor(character_id: String, floor: int) -> void:
	var entry := stats_for(character_id)
	if floor > int(entry.get("best_floor", 0)):
		entry["best_floor"] = floor

## 最快胜利要取最小而不是累加，单独走这里。
func record_win_time(character_id: String, seconds: int) -> void:
	if seconds <= 0:
		return
	var entry := stats_for(character_id)
	var current := int(entry.get("fastest_win_seconds", -1))
	if current <= 0 or seconds < current:
		entry["fastest_win_seconds"] = seconds

## 全局汇总（所有角色相加）。fastest_win_seconds 不能加，另见 fastest_win()。
func stat_total(key: String) -> int:
	var total := 0
	for character_id: Variant in stats.keys():
		total += int(stats_for(str(character_id)).get(key, 0))
	return total

## 所有角色里最快的胜利，一个都没有时返回 -1。
func fastest_win() -> int:
	var best := -1
	for character_id: Variant in stats.keys():
		var value := int(stats_for(str(character_id)).get("fastest_win_seconds", -1))
		if value > 0 and (best < 0 or value < best):
			best = value
	return best


func _mark(list: Array[String], id: String) -> bool:
	if id.is_empty() or id in list:
		return false
	list.append(id)
	return true

## 老存档里 stats / permanent_upgrades 的值是旧版浮点默认值留下的（0.0 / 15.0 / -1.0），
## 跟新写的整数混在同一个文件里。这些计数器全是整数语义，读档时统一收成 int：
## 旧档一读就洗干净，下次保存出去就是一致的。
func _int_dict(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for key: Variant in (raw as Dictionary).keys():
		out[str(key)] = int((raw as Dictionary)[key])
	return out

## stats 是两层的：{character_id: {计数器: 值}}，里外都得过一遍 int。
func _normalize_stats(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for character_id: Variant in (raw as Dictionary).keys():
		var entry: Variant = (raw as Dictionary)[character_id]
		if typeof(entry) == TYPE_DICTIONARY:
			out[str(character_id)] = _int_dict(entry)
	return out

func _string_array(raw: Variant) -> Array[String]:
	var arr: Array[String] = []
	if raw is Array:
		for v in raw:
			arr.append(str(v))
	return arr
