class_name PotionData
extends Resource

enum PotionRarity { COMMON, UNCOMMON, RARE }

@export var potion_id: String = ""
@export var potion_name: String = "药水"
@export var description: String = ""
@export var rarity: PotionRarity = PotionRarity.COMMON
@export var effect_type: String = ""
@export var effect_value: float = 0.0
@export var is_targeted: bool = false
@export var icon_texture: Texture2D


const ICON_DIR := "res://assets/art/potions/"

## 图标按 **potion_id** 找，跟 CardData.get_art_path() 同一套口径。图不在就返回路径，
## 由 ArtIcons.load_or_null() 探到不存在、退回程序生成的像素画——缺图不是错误状态。
func get_icon_path() -> String:
	if potion_id.is_empty():
		return ""
	return ICON_DIR + potion_id + ".png"


## 按稀有度取代表色，跟 RelicData.get_color() / CardData.get_color() 同一套做法。
## 百科的「药水研究所」和精英奖励页的药水图标槽都从这里取，别再各写一份 match。
func get_color() -> Color:
	match rarity:
		PotionRarity.UNCOMMON: return Color(0.30, 0.55, 0.90)
		PotionRarity.RARE: return Color(0.95, 0.72, 0.15)
	return Color(0.72, 0.72, 0.76)
