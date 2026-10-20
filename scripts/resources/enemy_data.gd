class_name EnemyData
extends Resource

enum EnemyTier { NORMAL, ELITE, BOSS }

@export var enemy_id: String = ""
@export var display_name: String = "敌人"
@export var max_hp: int = 50
@export var sprite_path: String = ""
@export var normal_intent_pattern: Array[IntentResource] = []
@export var aggressive_intent_pattern: Array[IntentResource] = []
@export var hp_threshold: float = 0.5
@export var gold_reward_min: int = 10
@export var gold_reward_max: int = 20
@export var soul_reward: int = 5
@export var tier: EnemyTier = EnemyTier.NORMAL
## 最早出现在第几层（全局层数，第 2 章从 17 层起，见 MapConfig.first_floor_of_chapter）。
## 普通敌人靠它做楼层递进（第一层固定只有蛊雕）；BOSS 靠它分三章三档，
## 一章只在一段区间里挑，三章的 Boss 就不重样了。精英都填默认值 1，等于不受限。
@export var min_floor: int = 1
@export var portrait: Texture2D

## 脚本化出招：意图按 normal/aggressive 池的顺序轮转，不走 AI 收益评分。
## 蓄力怪靠它拿到固定节拍（蓄 N 回合 → 放大招），池子里最后一条就是那一发。
@export var scripted_intents: bool = false

## 开场自带的「怪物特性」状态（0 = 不带）。这三样是持续光环，靠这里一上场就摆出来，
## 而不是挂在意图池里碰运气——AI 评分排不上它就等于这只怪没有这个机制，
## 玩家也看不到。激怒（仪式）不在这三栏里：那是「怪物发怒」这个动作，走意图。
## 数值上限见 _ui_frame_test.gd 的 WARD_CAP / THORNS_CAP，别填到玩家完全打不动。
@export var starting_thorns: int = 0
@export var starting_ward: int = 0
@export var starting_artifact: int = 0

## 召唤：意图池里挂一条 SUMMON 就会叫帮手。叫谁由这里定，一次 summon_count 只，
## 整场战斗最多叫 summon_max 只，而且受场上敌位上限（BattleManager.MAX_ENEMY_SLOTS）约束——
## 位子满了就白放一个回合，所以 AI 那边给 SUMMON 的分值也会跟着归零。
@export var summon_enemy_id: String = ""
@export var summon_count: int = 1
@export var summon_max: int = 2

## 分裂：血量被打到 max_hp * split_hp_threshold 以下时裂成 split_count 只 split_enemy_id。
## 0 表示不分裂。和 hp_threshold 的二阶段是两码事，一只怪可以只开其中一个。
@export var split_enemy_id: String = ""
@export var split_count: int = 2
@export var split_hp_threshold: float = 0.0

## 复活变身：血量打到 0 时不倒下，而是换成 revive_enemy_id 那套数据接着打（刑天断首再起）。
## 空串表示不复活。
##
## revive_hp_ratio 写在**这一份**（也就是先出场的第一形态）身上，意思是「我复活时带着
## 几成血回来」，不是写在第二形态上；1.0 = 满血。这个字段只有第一形态读得到——
## 复活那一刻 enemy_data 已经换成第二形态了。
##
## 第二形态那份数据必须和第一形态对得上两件事：金币/魂的奖励区间一模一样
## （EndState 读的是 enemy.enemy_data，变身后漂了玩家打完这场拿到的奖励就变了），
## 而且 tier 也得还是 BOSS。另外它要标 pool_hidden = true，不然会自己混进 Boss 池和图鉴。
@export var revive_enemy_id: String = ""
@export var revive_hp_ratio: float = 1.0

## 只当「变身第二形态」「召唤物」这类中间态用，不进任何随机池、也不进图鉴。
## 它们不是玩家会独立遇到的一只怪，是别的怪的一件衣服。
@export var pool_hidden: bool = false

## 给玩家看的那一句机制说明。图鉴条目和按 Space 的状态面板里都读它——
## 反伤、复活、蓄力这些机制光靠图标和数值看不出来，得有一句话直说。
@export var mechanic_desc: String = ""
