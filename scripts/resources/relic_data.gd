class_name RelicData
extends Resource

enum RelicRarity { STARTER, COMMON, UNCOMMON, RARE, BOSS }

@export var relic_id: String = ""
@export var relic_name: String = "遗物"
@export var description: String = ""
@export var rarity: RelicRarity = RelicRarity.COMMON
@export var trigger_event: String = ""
@export var effect_type: String = ""
@export var effect_value: float = 0.0
@export var effect_target: String = ""
@export var max_charges: int = 0
@export var icon_texture: Texture2D
@export var character_class_restriction: String = "none"


## 商店的遗物价目表按稀有度的字符串取值，跟 CardData.rarity_to_string() 同一套做法。
static func rarity_to_string(rarity: int) -> String:
	match rarity:
		RelicRarity.STARTER: return "STARTER"
		RelicRarity.COMMON: return "COMMON"
		RelicRarity.UNCOMMON: return "UNCOMMON"
		RelicRarity.RARE: return "RARE"
		RelicRarity.BOSS: return "BOSS"
	return "COMMON"


## 按稀有度取代表色，跟 CardData.get_color() 同一套做法。
## 百科的遗物收集、历史记录的遗物小图标都从这里取，别再各写一份 match。
func get_color() -> Color:
	match rarity:
		RelicRarity.STARTER: return Color(0.72, 0.55, 0.35)
		RelicRarity.COMMON: return Color(0.68, 0.68, 0.68)
		RelicRarity.UNCOMMON: return Color(0.30, 0.55, 0.90)
		RelicRarity.RARE: return Color(0.95, 0.72, 0.15)
		RelicRarity.BOSS: return Color(0.90, 0.42, 0.20)
	return Color(0.68, 0.68, 0.68)


const ICON_DIR := "res://assets/art/relics/"

## 图标按 **relic_id** 找，跟 CardData.get_art_path() 同一套口径（id 与名字脱钩，
## 按名字命名会串）。图不在就返回路径，由 ArtIcons.load_or_null() 探到不存在、
## 悄悄退回原样——缺图不是错误状态。
func get_icon_path() -> String:
	if relic_id.is_empty():
		return ""
	return ICON_DIR + relic_id + ".png"
