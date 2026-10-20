class_name MapConfig
extends Resource

## 一章有多少层（含起点层和 Boss 层）。三章共用这一份规模，别在别处再写一遍 17。
const FLOORS_PER_CHAPTER: int = 17

## 第 chapter 章的最底层在全局层数里的编号。全局连续编号：第 1 章从 0 层起、第 2 章从 17 层起——
## 商店按层涨价、敌人成群规模、爬塔成就、历史记录全都照旧按全局层数走，一处都不用改。
static func first_floor_of_chapter(chapter: int) -> int:
	return maxi(0, chapter - 1) * FLOORS_PER_CHAPTER

@export var chapter_id: int = 1
@export var total_floors: int = FLOORS_PER_CHAPTER
@export var nodes_per_floor: int = 3
## 战斗权重。每层本来就强制至少一个 BATTLE，这一项只决定「剩下的格子」里战斗占多少：
## 0.28 实测分支层（不含起点/Boss）普通战斗约 60%、战斗+精英约 66%，落在 3/5~2/3。
## 原来的 0.50 实际生成出来是 67% / 73%，怪物房明显偏多。
@export var battle_weight: float = 0.28
@export var shop_weight: float = 0.09
@export var rest_weight: float = 0.11
@export var elite_weight: float = 0.07
## 本章第几层起才可能刷出精英节点（本地层号，0 是起点层）。
## 序盘卡组只有 14 张、一回合十来点输出，第 1~3 层撞上 110 血的精英是没有胜算的——
## 试玩日志里第 3 层就是被精英钦原打死的。中段那个固定精英（mid_boss_floor）不受这条限制。
@export var elite_first_floor: int = 4
@export var event_weight: float = 0.17
@export var chest_weight: float = 0.06
## 诅咒祭坛：分池事件的入口，稀有度比宝箱还低一点。这里不摊薄别的权重——
## 生成时按总和归一化，多出来的这点权重是让每个既有类型等比稀一档，不是改动它们之间的比例。
@export var altar_weight: float = 0.05
@export var mid_boss_floor: int = 8
