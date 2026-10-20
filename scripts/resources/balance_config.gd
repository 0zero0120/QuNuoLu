class_name BalanceConfig
extends Resource

@export var base_energy: int = 3
@export var cards_per_turn: int = 5
@export var starting_gold: int = 99
@export var potion_drop_chance: float = 0.4
@export var card_reward_skip_gold: int = 20
@export var max_ascension: int = 10
@export var ascension_hp_step: float = 0.05
## 每往后一章，敌人血量/意图数值上浮的幅度。第 1 章不打折也不加成，
## 第 2 章 ×(1+step)、第 3 章 ×(1+2*step)。和难度等级那档是相加的（见 scale_enemy_for_run）。
## 伤害小一点：血量涨了只是打得久，伤害一起按同样倍数涨，第 2 章开场就容易被直接打穿。
@export var chapter_hp_step: float = 0.5
@export var chapter_damage_step: float = 0.25
@export var card_rarity_weights: Dictionary = {"COMMON": 60, "UNCOMMON": 30, "RARE": 10}
## 商店定价：稀有度打底，再按楼层上浮。键名跟 CardData.rarity_to_string() /
## RelicData.rarity_to_string() 对齐，取不到就回落到函数里的兜底价。
@export var card_price_by_rarity: Dictionary = {
	"BASIC": 40, "COMMON": 50, "UNCOMMON": 75, "RARE": 120,
}
@export var relic_price_by_rarity: Dictionary = {
	"STARTER": 100, "COMMON": 150, "UNCOMMON": 200, "RARE": 260, "BOSS": 320,
}
## 每往下走一层，标价上浮的幅度。第 1 层不打折也不加价。
@export var shop_price_floor_step: float = 0.03
## 删卡服务：起步价 + 每在同一家店多删一张的加价。
@export var card_removal_base_price: int = 75
@export var card_removal_price_step: int = 25

## 普通遭遇战的队伍规模：第 floor 层最多刷 1 + floor / encounter_grow_every_floors 只，
## 再夹到 encounter_max_size。默认每 5 层放宽一档（1~4 层 1 只、5~9 层 2 只、10 层起 3 只）——
## 序盘那副 14 张的起始卡组每回合只出 5 张，3 层就两只围上来是接不住的（2026-10-01 试玩反馈）。
## 精英和 BOSS 永远单只出场，不受这里管。
@export var encounter_max_size: int = 3
@export var encounter_grow_every_floors: int = 5
