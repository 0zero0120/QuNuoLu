class_name Achievement
extends Resource

## 达成条件。绝大多数是「某个计数器 >= threshold」，集合类的看玩家收集到多少。
enum Condition {
	WINS,
	DEATHS,
	ENEMIES_KILLED,
	BOSSES_KILLED,
	FLOORS_CLIMBED,
	FASTEST_WIN,
	ASCENSION,
	SOULS,
	ALL_RELICS,
	ALL_CARDS,
	ALL_POTIONS,
	ALL_ENEMIES,
}

## 字段名必须是 achievement_id——DataManager._load_resources 靠这个键判断。
@export var achievement_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var condition: Condition = Condition.WINS
@export var threshold: int = 1
## 只给 ALL_RELICS 用，填 RelicData.RelicRarity 的值；-1 表示不限稀有度。
@export var rarity_filter: int = -1
@export var icon_texture: Texture2D


const ICON_DIR := "res://assets/art/achievements/"

## 图标按 **achievement_id** 找，跟 CardData.get_art_path() 同一套口径。图不在就返回路径，
## 由 ArtIcons.load_or_null() 探到不存在、退回「底色 + 首字」占位——缺图不是错误状态。
func get_icon_path() -> String:
	if achievement_id.is_empty():
		return ""
	return ICON_DIR + achievement_id + ".png"
